# tabula-ksp — the one file that has never been run

KSP is a Maven artifact. The environment this was developed in cannot reach
Maven, and the jars are not published as GitHub release assets either (checked).
So `TabulaProcessor.kt` is unverified, while **everything it feeds into is
covered**.

That is a deliberate arrangement, not a shrug. The work went into making this
file as small and as dumb as possible:

| | where | verified |
|---|---|---|
| `KSP API -> RawMachine` | `ksp/` | **no** — this file |
| validation + every declaration diagnostic | `codegen/Raw.kt` | yes, 14 cases |
| source emission | `codegen/Emit.kt` | yes: golden, then compiled |
| the emitted code still enforces the guarantee | `codegen/compile_fail/` | yes |

A bug here is an *extraction* bug — a wrong argument name, a missing null check
— not a logic bug. It surfaces as an obviously wrong `RawMachine` rather than as
subtly wrong generated code.

## What to expect on the first run

Re-read against the code rather than remembered, because one of these had
already been fixed and would have sent someone hunting a problem that no longer
exists.

1. **`getDeclaredFunctions` — fixed, and the fix is unverified.** The file used
   to carry a shim calling `com.google.devtools.ksp.getDeclaredFunctions(this)`.
   KSP declares that as an *extension*, and Kotlin has no syntax for calling an
   extension by fully-qualified name with the receiver as an argument, so it
   could not have compiled. The shim is gone and the extension is imported.

   Still first on this list, because it is the item most likely to be wrong in
   a new way: if the symbol has moved package between KSP versions, the import
   is where it fails, and it fails at compile time.

2. **Annotation argument shapes.** KSP hands `KClass` arguments back as
   `KSType`, arrays as `List<*>`, and enums inconsistently across versions —
   `enumName` tries `KSType` and falls back to `toString()` after the last dot
   for that reason. If something arrives as a `KSClassDeclaration` rather than
   a `KSType`, `classes()` is where to look: it filters for `KSType` and would
   silently return an empty list, which surfaces as a machine with no states
   rather than as an error.

   **This no longer fails silently.** `classes()` used `filterIsInstance`, so a
   shape it did not recognise was dropped and surfaced as a machine with no
   states — the one item on this list that could look like success. It now
   throws, naming the class it actually got, and `process` reports it against
   the declaration. Unverified code against an API that has moved between
   versions should fail loudly or not at all.

3. **`DELEGATE` is deliberately not wired.** `children = emptyList()` is passed
   unconditionally, so a `DELEGATE` cell fails with `tabula::unknown-child` —
   correctly, and with a clear message. Resolving a child means following a
   `KClass` to another `@Machine` and reading *its* types, which is a second
   pass this file does not attempt.

**No longer expected:** `CellSpec.args`. An earlier version of this list said
the annotation had no `args` parameter and would need one. It has had
`val args: String = ""` since, with the rule-R3 reasoning in its doc comment,
and `readCell` reads it. Nothing to do.

## Building it

Needs Gradle with Maven access, which is exactly what is missing here, so
`build.gradle.kts` is written from the KSP documentation rather than from a
successful run. Treat it the same way as the processor — and it got the same
read, which turned up one near-certain bug.

It used to depend on the generator with `implementation(files("../codegen"))`.
`files()` puts a path on the compile classpath as a directory of **class**
files, and `../codegen` holds `.kt` sources, so every `import codegen.*` in
`TabulaProcessor.kt` would have failed to resolve. Those sources are compiled
into this module instead.

Filtered with exclude patterns rather than by listing files, because `srcDir`
takes a directory. Without them the build would sweep in `Main.kt` (a CLI entry
point), `Tests.kt` (the golden-diff suite, which reads paths relative to the
repository root), and `compile_fail/` — fixtures that are *supposed* not to
compile.

Still unverified, and two things are worth knowing before the first run:

- There is **no `settings.gradle.kts`**. Gradle will synthesise one for a
  standalone build and take the project name from the directory, which is
  `ksp`. Harmless for a build, wrong for publication.
- The KSP version is pinned to `2.1.20-1.0.32`, matching the Kotlin version.
  KSP releases are tied to a specific Kotlin compiler build, so this pair moves
  together or not at all.

The first useful signal is whether `codegen/golden/timer.kt.golden` comes back
out of the processor unchanged when it is pointed at
`test/ReferenceTimer.kt`'s annotations. That single comparison exercises the
whole path.
