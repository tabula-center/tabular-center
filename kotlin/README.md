# tabula — Kotlin

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

## Why there is no Gradle build yet

Gradle needs Maven Central for the Kotlin stdlib, and the environment this was
developed in cannot reach it. Shipping a build file that has never run would
repeat the mistake of shipping unverified code.

`kotlinc` alone is enough to prove the thing that matters, so that is what runs:

```sh
./tools/verify kotlin
./tools/verify kotlin-compile-fail
```

Both are wired into `nix flake check`. Gradle, KSP, and Maven publication come
next, and the `@Row` annotation shape they will read is already validated here.

A side effect worth keeping: with no build system there is no classpath but the
stdlib, so the zero-runtime-dependency rule is enforced by construction rather
than by a dependency report. `SuspendDriver` needs only the `suspend` keyword —
no `kotlinx.coroutines` — and `test/RunSuspend.kt` proves it by driving a
suspending machine with `kotlin.coroutines` intrinsics alone.

## Layout

```
src/dev/tabula/     Step, Cell, Table, Export, Lint, Driver, Annotations
test/               the reference machine (KSP's specification) and its tests
compile_fail/       one fixture per guarantee
```

`test/ReferenceTimer.kt` is the artifact to read first. It is marked with a
`GENERATED` line: everything below is what KSP must emit, everything around it
is what a person writes. It plays the same role `reference_timer.rs` plays for
the Rust macro — the generator needs a target before it needs an implementation.
