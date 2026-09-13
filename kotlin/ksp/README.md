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

## It ran

`gradle build` in `examples/kotlin/06-generated` succeeded. The processor read
`@Machine` and `@Row` off `Machine.tb.kt`, built a `MachineDesc`, handed it to
`TabulaCodegen`, and the emitted dispatcher compiled — with `Impl.kt`
satisfying a `Cells` interface that did not exist until the build ran, and the
behavioural checks passing against it.

This file used to hold four predictions about what would break first. Keeping
score, because the scoring is the useful part:

1. **`getDeclaredFunctions` could not compile.** Correct, and fixed before the
   first run: the shim called a KSP extension by fully-qualified name with the
   receiver as an argument, which is not Kotlin.
2. **`CellSpec` needs an `args` parameter.** Wrong — already there, and the
   prediction was stale. Removed.
3. **Annotation argument shapes.** Did not bite. `classes()` now throws on a
   shape it cannot read rather than dropping it silently, so if a future KSP
   version changes the shape it will say so instead of producing a machine with
   no states.
4. **`DELEGATE` is not wired.** Still true, still deliberate: `children` is
   passed empty, so a `DELEGATE` cell fails with `tabula::unknown-child`.

The two bugs that actually stopped it were in `build.gradle.kts`, not the
processor — `files()` where sources were meant, and undeclared source sets —
and both were found by reading. The third, a missing harness on the test path,
took a real run.

## Building it## Building it

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
