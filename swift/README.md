# tabula — Swift

## Status: unverified, and not in `nix flake check` on Linux

`Sources/Tabula` and `Tests/TabulaTests` have never been compiled. Everything
here is written from the Rust and Kotlin implementations, which are verified.

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

- **No XCTest.** nixpkgs' Swift does not ship it (`no such module 'XCTest'`),
  so the checks are a plain executable with a thirty-line assertion harness —
  exactly what the Kotlin side does about JUnit, for the same reason: a test
  framework that has to be resolved is one that can stop the tests running at
  all. The cost is no `swift test` integration and no per-test isolation.
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

  Outside `nix develop .#swift`, point `LD_LIBRARY_PATH` at your toolchain's
  lib directory. `tools/verify swift` checks for `libdispatch.so` up front and
  says which case you are in, because a missing shared library is otherwise
  reported after a successful build in a message that reads like a build
  failure.

### Why the check is Darwin-only in `nix flake check`

A retreat, not a preference. Four rounds of nixpkgs packaging on Linux never
reached a compile of the library:

| | error | cause |
|---|---|---|
| 1 | `NIX_CC: unbound variable` | the setup-hook needs it |
| 2 | `could not find module '_Concurrency'` | caused by fixing (1) with `stdenv.cc`; a **triple mismatch**, not a missing module |
| 3 | `toolchain is invalid: could not find ar` | SwiftPM needs `binutils` |
| 4 | `cannot load underlying module for 'Dispatch'` | the triple again |

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

It did fix it — the library compiled on the next run. `nix flake check` stays
Darwin-only until the *checks* have gone green on Linux too; flipping
`swiftChecked` in `nix/context.nix` is one line once they have.

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
| `Sources/Tabula` | `Step`, `Cell`, `Table`, `Export`, `Lint`, `Driver`, `AsyncDriver` |
| `Tests/TabulaTests/ReferenceTimer.swift` | the macro's specification, hand-written |
| `Tests/TabulaTests/ReferenceTimerTests.swift` | 19 tests, the same assertions as the other two languages |

Not yet: `TabulaMacros` (needs swift-syntax), `TabulaTesting` (the conformance
harness), and the four examples. Deliberately — a first failure should not be
ambiguous between the core and a macro plugin.

## Two drivers, one per color

`Driver` and `AsyncDriver` are the same loop written twice. Swift has no
`reasync`, so an `async` caller needs its own type rather than a generic
parameter — the same one-file-per-color shape as Kotlin's `SuspendDriver`.

The closures capture rather than taking a shared environment, unlike Rust's
driver. That is not an oversight: Rust needs the parameter because two closures
cannot each capture the same `&mut`, and Swift has no such rule. Where the
languages differ, follow the language.

## Toolchain

**Swift comes from its own flake input** (`nixpkgs-swift`, tracking
`nixos-unstable`). The pinned nixpkgs ships 5.8, below the 5.9 that macros
require, so `TabulaMacros` needs a newer toolchain regardless. A separate input
means chasing a Swift toolchain never moves the Rust or Kotlin ones, which are
pinned deliberately and working.

`Package.swift` still declares **tools-version 5.7**. Nothing in the core needs
newer — conditional conformance is 4.2, async closures are 5.5 — and a low
tools-version works on any toolchain above it. Raise it when the macro lands
and the newer toolchain is confirmed working.

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
