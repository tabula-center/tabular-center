# TabulaMacros

**A separate SwiftPM package, on purpose.** This is the packaging decision the
backlog was blocked on, taken as option 2.

## Why it is not in `swift/`

A Swift macro implementation must link
[swift-syntax](https://github.com/swiftlang/swift-syntax), which is a remote
package. `nix flake check` builds with no network, so putting the macro in the
main package takes down **every** Swift check — the core, the conformance
runner, the reference harness — to add one target that cannot build there
anyway.

The subtlety that settles it: a macro's *declaration* has to live wherever
users import it from, and the declaration's `#externalMacro` names the
implementation module. Declaring `@Machine` in `Tabula` would therefore make
`Tabula` itself depend on the macro target, and the whole library would acquire
swift-syntax. There is no arrangement where the macro lives in the main package
and the main package stays offline-buildable.

So the declaration lives here too, in `TabulaMacroDecl`, and a user who wants
the macro takes a second dependency. A user who does not — one writing their
dispatcher against `ReferenceTimer.swift`, or generating it another way — pays
nothing, and the core keeps its "no dependencies" claim without an asterisk.

## A second blocker, found by running it

The network was the expected obstacle. It is not the first one. On the pinned
toolchain (nixpkgs `swift-wrapper-5.10.1`) the manifest does not compile at
all:

```
Package.swift:5:8: error: no such module 'CompilerPluginSupport'
```

`CompilerPluginSupport` is the module that provides `.macro(...)`, and this
SwiftPM does not ship it in its `ManifestAPI` directory. So **no macro package
can be declared with this toolchain**, regardless of network: the failure
happens while compiling the manifest, before dependency resolution is even
attempted.

That is worth separating from the network problem because the fixes are
different. Vendoring swift-syntax — option 1 in the backlog — would not help
here at all; the manifest would still fail on the import. What is needed is a
SwiftPM that ships `CompilerPluginSupport`, which means either a different
Swift derivation or a toolchain installed outside nix.

It also means this package cannot be verified on the Linux path even in the dev
shell, which is a stronger statement than the one this file made before. Darwin
toolchains ship `CompilerPluginSupport`, so the macro is a Darwin-first piece of
work in the same way `ObservableStore` is — for a different reason, and the two
should not be conflated.

## What that costs, stated plainly

The macro is **not** covered by `nix flake check`. It is built in the dev shell
with network access, and the check step reports `skip` otherwise rather than
passing silently. That is the same call the Swift checks already make off
Darwin and the Kotlin `06-generated` example makes without Gradle: a check that
quietly passes where a thing is absent claims the thing works.

Option 1 in the backlog — vendoring swift-syntax with `swiftpm2nix` or a fixed
output derivation — remains the correct end state and is strictly more work. It
can be adopted later without moving any code: only `nix/` changes.

## What is here, and what is not

- `Sources/TabulaMacroDecl` — the `@Machine` declaration users import.
- `Sources/TabulaMacros` — the implementation. Its job is exactly one
  transformation: **SwiftSyntax nodes to a `RawMachine`.**

Everything after that already exists and is tested. `TabulaCodegen` takes a
`RawMachine`, validates it into a `MachineDesc` with all 13 diagnostics, and
emits source. That split is why this package is small and why the Kotlin side
survived KSP being unrunnable — the generator's logic never depended on the
thing that parses syntax.

**The implementation is not written yet.** This package is the decision and the
shape; the SwiftSyntax parsing is the next piece of work, and it is the only
piece, because nothing downstream of `RawMachine` needs anything from here.

`SURFACE.md` pins the input half: what a user writes, and which part of it
becomes which field of `RawMachine`. It is written before the traversal on
purpose. The traversal is a mapping, its input contract decides its shape, and
no toolchain reachable from here can compile a line of it to tell us we got the
contract wrong — so the half that can be reviewed by reading is the half to
settle first.
