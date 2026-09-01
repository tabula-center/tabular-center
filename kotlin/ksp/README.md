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

Honest guesses at what will need fixing, in order of likelihood:

1. **Annotation argument shapes.** KSP hands `KClass` arguments back as
   `KSType`, arrays as `List<*>`, and enums inconsistently across versions —
   `enumName` tries two shapes for that reason. If something comes back as a
   plain `String` or a `KSClassDeclaration`, the helpers at the bottom of the
   file are where to look.
2. **`args` on `CellSpec`.** `RawCell.targetArgs` carries literal constructor
   arguments (`"(0)"`) for rule R3, but `dev.tabula.CellSpec` has no `args`
   parameter yet — it needs adding, since an annotation cannot hold an
   expression. A string is the only option.
3. **`getDeclaredFunctions`.** It moved between an extension and a member
   across KSP versions; the shim at the bottom of the file may need inverting.
4. **`DELEGATE`.** Deliberately not wired: resolving a child machine means
   following a `KClass` to another `@Machine` and reading *its* types.
   `children` is passed empty, so a `DELEGATE` cell will fail with
   `tabula::unknown-child` — correctly, and with a clear message.

## Building it

Needs Gradle with Maven access, which is exactly what is missing here, so
`build.gradle.kts` is written from the KSP documentation rather than from a
successful run. Treat it the same way as the processor.

The first useful signal is whether `codegen/golden/timer.kt.golden` comes back
out of the processor unchanged when it is pointed at
`test/ReferenceTimer.kt`'s annotations. That single comparison exercises the
whole path.
