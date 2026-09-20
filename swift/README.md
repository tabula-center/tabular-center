# tabula — Swift

## Status: passing

40 checks green on Linux under Swift 5.10.1, and back in `nix flake check`.

Three predicted failures did not happen: `Step`'s `Equatable` synthesis on a
generic enum with labelled associated values, tuple pattern matching on
`(S, A)` in the dispatcher, and `Assert.eq` on arrays of enums with associated
values all worked first time. The eight rounds it took were entirely nixpkgs
packaging; not one was a mistake in the Swift.

```sh
nix develop .#swift
./tools/verify swift        # or: cd swift && swift test
```

`tools/verify swift` skips with a note when `swift` is absent, rather than
reporting a green that means nothing.

### The library compiles

Round five got there: all six `Sources/Tabula` files build under Swift 5.10.1.
The design survives three languages.

Two things had to change to get the *checks* running alongside it, and both are
toolchain accommodations rather than design changes:

- **No XCTest.** The checks are a plain executable with a thirty-line
  assertion harness — exactly what the Kotlin side does about JUnit, for the
  same reason: a test framework that has to be resolved is one that can stop
  the tests running at all. The cost is no `swift test` integration and no
  per-test isolation.

  **XCTest turned out to be available after all.** `swift-corelibs-xctest` is
  in nixpkgs; the original `no such module 'XCTest'` was because it was not in
  the inputs, and `swiftCorelibs` now names it. So this is a live choice rather
  than a constraint, and the harness stays:

  - It works, and it is the same shape as the Kotlin side, which makes the
    three implementations read alike.
  - It has no dependency to resolve, which matters for a library whose whole
    claim is that its guarantees are checkable anywhere.
  - Switching back would cost a round and buy no new guarantee — the four
    `compile_fail/` fixtures are what prove the design, and they do not use a
    test framework either.

  If per-test isolation or `swift test` integration becomes worth it, XCTest is
  one `Package.swift` change away.
- **Release, not debug.** Emitting debug info failed with `emit-module command
  failed` on the same missing-glibc warning; release skips the AST-wrapping
  step that needs it, and the checks do not care about debug info.

`main.swift` also uses `fatalError` rather than `exit` on failure: `exit` lives
in Glibc, and importing a C module is precisely what keeps breaking here.

- **The runtime needs to be on the loader path.** The binary links against
  libdispatch and nothing puts the Swift runtime where the loader will find it:

  ```
  error while loading shared libraries: libdispatch.so
  ```

  **nix supplies `LD_LIBRARY_PATH`** — `swiftLibraryPath` in
  `nix/context.nix`, exported by the `swift` dev shell and the Darwin check.
  nix knows where every package in the toolchain is; the script would be
  guessing.

  `swiftc -print-target-info` is appended as a fallback for a non-nix
  toolchain, but it reports *module* search paths and on nixpkgs does not
  contain libdispatch at all — which is why it was not enough on its own.

  The corelibs — Dispatch, Foundation, XCTest — are **separate derivations**
  from the `swift` wrapper, so `${swift}/lib/swift/linux` does not exist.

  `swift-unwrapped` is a trap here. Its `lib` output is wanted, but putting the
  package in the inputs shadows `swift-wrapper/bin/swiftc`, and the unwrapped
  compiler does not know nix's target triple. It is in `swiftLibOnly`, which
  contributes to the library path and never to PATH. `tools/verify swift` now
  prints which `swiftc` it is using, because the two are indistinguishable from
  the version string. They
  are named explicitly in `swiftCorelibs` (`nix/context.nix`), guarded with
  `or null` so the set can differ between nixpkgs revisions without breaking
  eval.

  If it still is not found, `tools/swift-probe` prints what the toolchain
  advertises, which `LD_LIBRARY_PATH` entries actually contain
  `libdispatch.so`, and where it is under the toolchain root. That output is
  worth more than another round of guessing.

  Outside `nix develop .#swift`, point `LD_LIBRARY_PATH` at your toolchain's
  lib directory. `tools/verify swift` checks for `libdispatch.so` up front and
  says which case you are in, because a missing shared library is otherwise
  reported after a successful build in a message that reads like a build
  failure.

### The eight rounds, for the next person

The Swift check was Darwin-only for four of them. `nix flake check` should not
fail on a dependency's packaging while it is being untangled — and it was
untangled, so it is back on for Linux.

| | error | cause |
|---|---|---|
| 1 | `NIX_CC: unbound variable` | the setup-hook needs it |
| 2 | `could not find module '_Concurrency'` | caused by fixing (1) with `stdenv.cc`; a **triple mismatch**, not a missing module |
| 3 | `toolchain is invalid: could not find ar` | SwiftPM needs `binutils` |
| 4 | `cannot load underlying module for 'Dispatch'` | the triple again |
| 5 | *the library compiled* | — |
| 6 | `no such module 'XCTest'` | nixpkgs' Swift does not ship it |
| 7 | `emit-module command failed` | debug-info emission; build release |
| 8 | `libdispatch.so: cannot open shared object file` | the corelibs are **separate derivations** from the `swift` wrapper |
| 9 | `could not find module 'Swift' for target 'x86_64-pc-linux-gnu'` | **round 2 again** — `swift-unwrapped` in the inputs shadowed `swift-wrapper/bin/swiftc`, and the unwrapped compiler does not know nix's target triple |

Every one carried the same warning:

```
glibc not found for 'x86_64-pc-linux-gnu'
```

That was the cause the whole time, not noise. swiftc resolves the host triple
as `x86_64-pc-linux-gnu` while nixpkgs builds everything for
`x86_64-unknown-linux-gnu`, so anything with an underlying C module — Dispatch,
Foundation — fails to load.

The likely reason, and my mistake: round 3 put `binutils` from the pinned
nixpkgs next to `swift` from unstable. **Two nixpkgs generations disagree about
the host triple.** The whole Swift toolchain now comes from one of them.

It did fix it — the library compiled on the next run, and rounds 6 to 8 were
about running the checks rather than building the library.

The lesson worth keeping is round 8's: I spent three rounds guessing at a store
layout I could not see. `tools/swift-probe` answers it in one run, and should
be the first thing tried next time.

## Which shape Swift takes

ARCHITECTURE §11.0 records a divergence that runs one way: *Rust reaches for
generics wherever `macro_rules!` cannot build an identifier; Kotlin names
things.* The prediction was that Swift would land with Kotlin, for two
independent reasons:

1. Swift macros **can** build identifiers, so there is no reason to reach for a
   generic protocol the way `macro_rules!` must.
2. A Swift type cannot conform to one generic protocol at two different
   arguments — the same restriction that killed `Cells : Delegate<A.Run>,
   Delegate<A.Tick>` in Kotlin.

Both hold, so the cell surface is a **protocol with named members**, one per
cell, exactly like Kotlin's.

A protocol rather than a base class for the same reason Kotlin uses an
interface: composition needs `protocol Cells: AuthCells`, and a base class
would cap a machine at one child.

## What is here, and what is not

| | |
|---|---|
| `Sources/Tabula` | `Step`, `Cell`, `Table`, `Export`, `Lint`, `Driver`, `AsyncDriver`, `Store`, `AsyncStore` |
| `Sources/TabulaCheck/ReferenceTimer.swift` | the macro's specification, hand-written |
| `Sources/TabulaCheck/main.swift` | 40 checks, the same assertions as the other two languages |
| `compile_fail/` | one fixture per guarantee |

### What `compile_fail/` proves

The library's whole claim is that an incomplete machine does not compile.
Swift now has the evidence, four fixtures, checked by
`./tools/verify swift-compile-fail`:

| fixture | proves |
|---|---|
| `missing_cell` | omitting a `HANDLE` cell fails — `does not conform to protocol` |
| `missing_effect_handler` | the same for the effect surface |
| `new_state_breaks_dispatcher` | adding a state breaks the generated `switch` — Swift's own exhaustiveness check, the free second guarantee |
| `child_hole_breaks_parent` | **the composition property**: a type implementing every parent cell still fails, because `protocol SessionCells: AuthCells` |

`swiftc -typecheck` against the built module, not `swift build`: the fixtures
must not be part of a target, or the package itself would stop building.

### `TabulaTesting` and the conformance harness

`Sources/TabulaTesting` parses the shared `.tbl` and `.trace` fixtures — a third
parser, deliberately. The format was chosen to parse in about sixty lines
precisely so each language could own its parser with no dependency; three small
parsers that agree are worth more than one that no language can build offline.

It depends on `Tabula` and **nothing else — not even Foundation**. Trimming a
string is not worth putting the whole of Foundation on a consumer's link line,
so `trim` and `splitOnArrow` are written out. The *runner* imports Foundation,
because it needs file IO, and it is an executable rather than a published
library.

`./tools/verify swift-conformance` compares three things, and the third only
exists because there are three implementations:

1. the generated table, cell by cell;
2. traces — outcomes and effects, step by step;
3. the golden `.grid` file, **byte for byte**.

Rust owns `--bless`; Kotlin and Swift read and never bless, so a renderer that
drifts by one space fails rather than quietly rewriting the shared snapshot.

Every fixture in `spec/conformance` has a Swift adapter. `Sources/TabulaConformance/Compose.swift`
holds the composition reference — a `job` machine delegating to a `retry` one —
and its shape is the composition property in one line:

```swift
protocol JobCells: RetryCells { ... }
```

Implementing the parent requires implementing the child, so a hole anywhere in
the child breaks any type conforming to the parent.
`compile_fail/child_hole_breaks_parent.swift` proves that at the type level;
the conformance fixtures prove the behaviour.

**Protocols are Swift's trait bounds**, exactly as interfaces are Kotlin's —
and a protocol rather than a base class for the same reason: a class extends
one parent, which would cap a machine at one child.

The composition machines live beside the adapters rather than in `TabulaCheck`,
because Swift executables cannot import one another. Kotlin keeps its reference
in `test/` and adapts it from `conformance/` because kotlinc compiles loose
files. A language-shaped difference, like every other one in ARCHITECTURE §11.0.

Two things the first run taught, both about the harness rather than the design:

- **Swift enum cases are lowerCamel; the fixtures are UpperCamel.**
  `"\(TimerF.stopClock)"` is `stopClock`, and the shared fixtures use
  `StopClock` — the variant names the other two languages generate. Adapters
  name their effects explicitly rather than interpolating. `lastSegment` could
  have been made case-insensitive instead, but that would hide real drift as
  well as this.

- **SwiftPM's flags go before the executable name.** `swift run` passes
  everything *after* it to the program, so
  `swift run tabula-check --scratch-path X` hands `--scratch-path` to
  `tabula-check` and leaves swiftpm on its defaults. That is why the
  `/var/empty` warnings survived being "fixed" twice, and why the conformance
  runner once tried to read `--scratch-path/timer.tbl`. The runner ignores
  flag-shaped arguments now, so the mistake is harmless rather than merely
  legible.

- **`fatalError` loses the diagnostics.** stdout is block-buffered when piped,
  and `fatalError` traps without flushing, so the first run reported
  "2 fixture(s) failed" with every explanatory line swallowed. Both executables
  use `exit(1)` now, which flushes stdio on the way out.

### The generator, split so its logic can be verified

`Sources/TabulaCodegen` turns a `MachineDesc` into Swift source: validation with
every declaration diagnostic, plus the emitter. It has **no swift-syntax
dependency and no network**.

That split is not stylistic. A Swift macro implementation must link
swift-syntax, which is a *remote package*, and `nix flake check` builds
offline — so putting it in this package would break every Swift check rather
than only the macro's. The same reasoning produced the Kotlin split, where KSP
is the piece that needs Maven.

```sh
./tools/verify swift-codegen   # the diagnostics, determinism, and the emitted
                               # source compiled against codegen-support/
```

**`TabulaMacros` is not written yet**, and swift-syntax has to be solved first:
either vendored for the sandbox, or the macro target excluded from
`nix flake check`. Worth deciding deliberately rather than discovering when the
checks go red — see `PLAN.md`.

## Two drivers, one per color

`Driver` and `AsyncDriver` are the same loop written twice. Swift has no
`reasync`, so an `async` caller needs its own type rather than a generic
parameter — the same one-file-per-color shape as Kotlin's `SuspendDriver`.

Written twice and, until Phase 5's store work, run once: `AsyncDriver` had no
check of any kind. `TabulaCheck` now drives both and asserts they report
identical `Progress` for identical input, which is the property duplication
actually threatens — not that the async one is broken, but that the two quietly
stop being the same loop.

`Store` and `AsyncStore` sit on top. The difference is only that they bind
`step` and `perform` once at construction instead of taking them per call: a
driver is generic over machines and should own none of them, while a caller has
exactly one and should not get to pass the wrong pair at one call site out of
twenty.

The closures capture rather than taking a shared environment, unlike Rust's
driver. That is not an oversight: Rust needs the parameter because two closures
cannot each capture the same `&mut`, and Swift has no such rule. Where the
languages differ, follow the language.

### Path dependencies are named by their directory

`examples/swift-examples` depends on the library by path. It is not called
`examples/swift`: SwiftPM derives a path dependency's identity from its
directory basename, so two directories named `swift` become one identity and
the package appears to depend on itself —
`cyclic dependency declaration found: TabulaExamples -> TabulaExamples`. SwiftPM identifies such a
dependency by its **directory name** — `swift` — not by the `name` in its
manifest, so `.product(name: "Tabula", package: "Tabula")` is
`unknown package 'Tabula'`.

So the target uses `.product(name: "Tabula", package: "swift")`, with `swift`
being the directory.

The bare `dependencies: ["Tabula"]` form does not work either: by-name lookup
matches the *package* name `Tabula`, resolves to the examples package itself,
and reports `cyclic dependency declaration found: TabulaExamples ->
TabulaExamples`.

## Toolchain

**Swift comes from its own flake input** (`nixpkgs-swift`, tracking
`nixos-unstable`). The pinned nixpkgs ships 5.8, below the 5.9 the manifest
now requires, so the separate input is what makes the bump possible at all. A separate input
means chasing a Swift toolchain never moves the Rust or Kotlin ones, which are
pinned deliberately and working.

`Package.swift` declares **tools-version 5.9**, raised from 5.7 once rather
than twice: `@Observable` and macros both need it, so `ObservableStore` and
`TabulaMacros` were one decision. The pinned toolchain is 5.10.1, so 5.9 is
below it rather than at it.

There is still **no `platforms:` clause**, which is the part that matters. A
deployment target in the manifest is a floor for every consumer, and someone
using `Store` on an older OS should not pay for a type they never import.
`ObservableStore` carries `@available(macOS 14, iOS 17, …)` instead, and sits
behind `#if canImport(Observation)` so a toolchain shipping without that module
gets a package missing one type rather than a package that does not build.

In practice the guard is `os(macOS) || os(iOS) || os(tvOS) || os(watchOS)`,
not `canImport(Observation)`. On the pinned Linux toolchain the module is
present, `@Observable` does not resolve, and with the macro removed the binary
links and then dies on startup with `libswiftObservation.so: undefined symbol`.
Darwin is the type's honest scope anyway — it exists to be watched by SwiftUI.

It also conforms to `Observable` **by hand**, driving `ObservationRegistrar`
directly. That is what the macro expands to, SwiftUI observes it identically,
and a library gains nothing by requiring macro plugins to load.

### What SwiftPM needs beyond the Swift toolchain

`binutils`, for `ar`. SwiftPM builds a static library and the Swift toolchain
does not ship an archiver:

```
error: toolchain is invalid: could not find ar
```

Unlike `stdenv.cc`, adding it does not change what swiftc thinks it targets.

### The nix setup-hook, and the trap in fixing it

Swift's nix setup-hook reads `NIX_CC` and dies with `NIX_CC: unbound variable`
without it. The obvious fix — putting `stdenv.cc` in the inputs — is **wrong**,
and produces a second error that looks unrelated:

```
could not find module '_Concurrency' for target 'x86_64-pc-linux-gnu';
found: x86_64-unknown-linux-gnu
```

That is a **target-triple mismatch, not a missing module**. Putting gcc on the
hook's path makes swiftc take its default target from gcc
(`x86_64-pc-linux-gnu`) while Swift's own stdlib is built for
`x86_64-unknown-linux-gnu`.

`NIX_CC` is therefore supplied as a plain environment variable in
`nix/context.nix`'s `mkCheck`, satisfying the hook without changing what swiftc
thinks it targets.

If the mismatch reappears anyway, the honest next step is to gate the *check*
to Darwin — `nix flake check` should not fail on a packaging problem in a
dependency we do not control — while leaving `nix develop .#swift` available
for anyone with a working toolchain. ARCHITECTURE §13 already treats nixpkgs'
Linux Swift as best-effort; that would just be acting on it.

## Likely first failures

Honest guesses, in order:

0. ~~**Key paths on tuple members.**~~ Found and fixed before shipping:
   `payloads.map(\.state)` where the element is a labelled tuple. Swift has no
   key paths to tuple members, and the error it gives says something else
   entirely. Now a closure.
1. **`Step` equality.** `extension Step: Equatable where S: Equatable, F:
   Equatable` should synthesise, but a generic enum with labelled associated
   values is exactly where synthesis sometimes needs help.
2. **Tuple pattern matching on `(S, A)`.** Swift is stricter than Rust here,
   and `case (.running, .start)` next to `case let (.running(since), .tick(now))`
   may need reordering or explicit binding.
3. **`XCTest` on Linux** occasionally wants `@testable import` to be plain
   `import` for a library with no internal access needed.
4. **`Payloads` as a tuple typealias** may need a struct if the labels get in
   the way of `Equatable`.

None of these touch the design; they are the kind of thing one compile finds.
