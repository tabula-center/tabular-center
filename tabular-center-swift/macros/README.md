# TabularCenterMacros

**A separate SwiftPM package, on purpose.** This is the packaging decision the
backlog was blocked on, taken as option 2.

## Why it is not in `tabular-center-swift/`

A Swift macro implementation must link
[swift-syntax](https://github.com/swiftlang/swift-syntax), which is a remote
package. `nix flake check` builds with no network, so putting the macro in the
main package takes down **every** Swift check — the core, the conformance
runner, the reference harness — to add one target that cannot build there
anyway.

The subtlety that settles it: a macro's *declaration* has to live wherever
users import it from, and the declaration's `#externalMacro` names the
implementation module. Declaring `@Machine` in `TabularCenter` would therefore make
`TabularCenter` itself depend on the macro target, and the whole library would acquire
swift-syntax. There is no arrangement where the macro lives in the main package
and the main package stays offline-buildable.

So the declaration lives here too, in `TabularCenterMacroDecl`, and a user who wants
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

*Updated in the October 2026 audit.* The network half is solved: option 1 was
adopted as `tools/swift-lock` and `nix/swift-deps.nix`, which pin swift-syntax
509.1.1 and lay it out as SwiftPM's checkout set, so `swift-macros` builds this
package and runs `TabularCenterMacroSyntaxCheck` offline under
`nix flake check`.

What is still not covered is macro *expansion*: there is no `.macro` target to
build until a SwiftPM with `CompilerPluginSupport` is available.
`swift-macro-support` reports how far `nix/swiftpm-plugin-support.nix` has got,
and says `skip` with its reason rather than passing quietly.

## What is here, and what is not

- `Sources/TabularCenterMacroSyntax` — `MachineSyntax`: **SwiftSyntax nodes
  to a `RawMachine`**, the macro's whole job, as a plain library so it builds
  without plugin support.
- `Sources/TabularCenterMacroSyntaxCheck` — runs it over `SURFACE.md`'s
  declaration and the rejection fixtures in `fixtures/`.
- `pending/` — the `@Machine` declaration (`Machine.swift`) and the expansion
  glue (`TabularCenterMacros/`), waiting for a `.macro` target.

Everything after `RawMachine` already exists and is tested. `TabularCenterCodegen`
validates it into a `MachineDesc` with every declaration diagnostic, and
emits source. That split is why this package is small and why the Kotlin side
survived KSP being unrunnable — the generator's logic never depended on the
thing that parses syntax.

**The traversal is written** (`MachineSyntax`); expansion is what waits, and it
is the part with no decisions in it. *(This paragraph said the implementation
was unwritten until the October 2026 audit.)*

`SURFACE.md` pins the input half: what a user writes, and which part of it
becomes which field of `RawMachine`. It is written before the traversal on
purpose. The traversal is a mapping, its input contract decides its shape, and
no toolchain reachable from here can compile a line of it to tell us we got the
contract wrong — so the half that can be reviewed by reading is the half to
settle first.

## The manifest could not compile (resolved)

nixpkgs' swiftpm 5.10.1 ships no `CompilerPluginSupport` in its ManifestAPI, so
`Package.swift` failed to compile before dependency resolution began:

```
error: 'macros': Invalid manifest
Package.swift:5:8: error: no such module 'CompilerPluginSupport'
```

Worth being precise about, because the obvious reading is wrong: this was never
a network problem, and vendoring swift-syntax would not have touched it.
Nothing had got far enough to want a dependency.

The manifest now declares a plain `.target` and imports only
`PackageDescription`. `TabularCenterMacroDecl` — the `@Machine` declaration — moved to
`pending/`, because `#externalMacro` names a module SwiftPM only wires up for a
`.macro` target and a macro nobody can apply is worse than an absent one.

That leaves the part with all the logic in it. `MachineMacro` is SwiftSyntax
nodes to a `RawMachine` (`SURFACE.md`) and that is an ordinary function over
syntax trees — writable, buildable and testable here by parsing source with
`SwiftParser`. Expansion is the only piece needing the plugin wiring, and it is
the piece with no decisions in it.

It also makes `SURFACE.md`'s two open questions answerable by a test instead of
by a toolchain upgrade.
