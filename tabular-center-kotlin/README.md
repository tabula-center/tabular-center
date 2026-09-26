# tabular-center — Kotlin

## Status: M2 passed

The gate the whole plan hung on was whether required-member enforcement
delivers a clean developer experience in Kotlin. It does, and the error is
arguably better than Rust's:

```
error: class 'Timer' is not abstract and does not implement abstract base
class member:
suspend fun runningTick(state: S.Running, action: A.Tick): Step<S, F>
```

It names the cell *and* shows its narrowed argument types. Three properties
were verified against kotlinc 2.1.20, each with a fixture in `compile_fail/`:

1. **Omitting a cell fails to compile** — a plain unimplemented-member error
   from kotlinc, not from tabula. It survives even if the generator is
   bypassed.
2. **Adding a state breaks the generated dispatcher** — `'when' expression must
   be exhaustive`. The same free second guarantee rustc gives the Rust macro.
3. **`else` is not available.** The developer's file contains no `when` at all,
   because the dispatcher exists only in generated code.

Point 3 is the one that changed the design. KSP cannot rewrite code — it only
generates new files — so the only way to own the dispatch is to be its sole
author. That is why the matrix lives in annotations rather than in a function
body, and it converts what was Kotlin's weakest guarantee into one as strong as
Rust's.

## Why the library has no Gradle build

The library is compiled with `kotlinc` directly, on purpose (ARCHITECTURE
11.2): with no build system there is no classpath but the stdlib, so the
zero-runtime-dependency rule holds by construction.

```sh
./tools/verify kotlin
./tools/verify kotlin-compile-fail
./tools/verify kotlin-conformance
./tools/verify kotlin-codegen
./tools/verify kotlin-examples
```

All of them compile into a temporary directory, never into the tree. Building
by hand writes wherever you point `-d`, so prefer the script — a stray
`kotlinc ... -d out` put 59 class files and a 4.7 MB jar into a commit once
already.

Every one is a `nix flake check` check. Gradle appears in exactly two places,
both for KSP: `ksp/` (the processor) and `tabular-center-kotlin/examples/06-generated` (its
consumer), resolved offline from `tabular-center-kotlin/nix/gradle-lock.json`. Maven publication is
still to come (`RELEASING.md`).

**One compiler version, everywhere: 2.1.20.** The flake pins `kotlinc` to it
(`kotlinVersion` in `tabular-center-kotlin/nix/context.nix`) rather than taking whatever the nixpkgs
channel ships, because the compile-fail fixtures match kotlinc's own wording
and the Gradle builds and KSP (`2.1.20-1.0.32`) are tied to it. Bump it in
`tabular-center-kotlin/nix/context.nix`, both `build.gradle.kts` files, `ci.yml` and this line
together; `tools/verify` prints a `note:` when the `kotlinc` on PATH differs.

A side effect worth keeping: with no build system there is no classpath but the
stdlib, so the zero-runtime-dependency rule is enforced by construction rather
than by a dependency report. `SuspendDriver` needs only the `suspend` keyword —
no `kotlinx.coroutines` — and `test/RunSuspend.kt` proves it by driving a
suspending machine with `kotlin.coroutines` intrinsics alone.

That proved it *compiles* without coroutines, which is not the same as running
it. `SuspendDriver` had no check of its own until Swift's `AsyncDriver` turned
out to have the identical gap: in both languages the blocking driver was
exercised from the day it was written and its colored twin was exercised by
nothing. `test/Main.kt` now drives both over the same machine with the same
input and asserts identical `Progress`, which is the property two hand-copied
loops actually threaten — not that one is broken, but that they quietly stop
being the same loop.

## The generator, split in two

KSP is a Maven artifact and this environment cannot reach Maven. Rather than
ship an unrunnable processor, the generator is split:

- **`codegen/`** turns a `MachineDesc` into Kotlin source. Pure — no KSP, no
  compiler plugin — and therefore testable here.
- **`ksp/`** reads annotations, builds a `RawMachine`, and calls `buildDesc` +
  `emit`. Mechanical, ~270 lines, written before it could run and now exercised
  by `kotlin-ksp`, `kotlin-ksp-compile-fail` and `kotlin-ksp-incremental` —
  see `ksp/README.md`.

Worth keeping now that KSP runs: a code generator whose logic can only be
exercised through a compiler plugin is a generator nobody refactors.

`./tools/verify kotlin-codegen` does four things, and the last two are the
point:

```
ok   timer                              # emitted source matches the golden
ok   toggle
ok   emitted source compiles            # it is valid Kotlin
ok   complete implementation compiles   # every member it demands is satisfiable
ok   hole_in_generated.kt               # and an incomplete one still fails
```

A golden diff alone would only prove the emitter is deterministic. Compiling
its output, then compiling both a complete and an incomplete implementation
against that output, proves the emitted code **still enforces the guarantee**.

## Layout

```
core/               tabula-core        runtime; compiles against nothing
annotations/        tabula-annotations compile-time only
testing/            tabula-testing     fixture parser; needs only core
codegen/            tabula-codegen     validation and the emitter
ksp/                tabula-ksp         the processor (Gradle; artifacts from tabular-center-kotlin/nix/gradle-lock.json)
test/               the reference machine (KSP's specification) and its tests
conformance/        the shared spec/conformance fixtures, run against Kotlin
compile_fail/       one fixture per guarantee
```

The directory split is the artifact split — see `RELEASING.md`. `tools/verify
kotlin` compiles each against **only** its declared dependencies, so
`tabula-core` building with an empty classpath is the zero-runtime-dependency
rule enforced by construction rather than asserted.

`test/Composition.kt` holds a parent machine delegating to a child. Its shape
is the composition property in one line — `interface Cells : retry.Cells` — so
a hole anywhere in the child breaks any class implementing the parent.
Interfaces are Kotlin's trait bounds, which is also why the cell surface is an
interface rather than abstract members on a class: a class extends one parent,
and that would have capped composition at a single child.

`conformance/` is what keeps the two implementations from drifting. It parses
the same `.tbl` and `.trace` files the Rust harness reads, and compares the
rendered grid **byte for byte** against the golden `.grid` file Rust writes.
Verified to catch both table drift and behavioural drift.

`test/ReferenceTimer.kt` is the artifact to read first. It is marked with a
`GENERATED` line: everything below is what KSP must emit, everything around it
is what a person writes. It plays the same role `reference_timer.rs` plays for
the Rust macro — the generator needs a target before it needs an implementation.
