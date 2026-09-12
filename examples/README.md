# Examples

Four machines, the same four in every language, ordered by what they add:

| | machine | introduces |
|---|---|---|
| 1 | `traffic_light` | the minimum: three states, two actions, no payloads, no effects |
| 2 | `timer` | payloads on states and actions, effects, the effect handler |
| 3 | `retry` | the driver: effects producing follow-up actions through the mailbox |
| 4 | `login` | composition: a `session` machine delegating to an `auth` machine |

Each is a working machine with tests, and each is written twice — once per
language — because the second writing is a review of the first. Two findings
that changed the design came out of exactly that (see `PLAN.md`).

## Each one is a project, not a module

They were four modules in a single crate per language. They are now four
**projects**: own manifest, own dependency line on tabula, own `tests/`
directory. An example is read as a template for a real project, and a real
project does not keep its tests in a `mod tests` at the bottom of `lib.rs`.

Splitting them also lets each cover a different **configuration**, which a
single crate structurally cannot — one set of features, one edition, one shape
for everybody:

| | crate | configuration it covers |
|---|---|---|
| 1 | `traffic-light` | `#![no_std]`, tabula with `default-features = false` |
| 2 | `timer` | default features: `TABLE`, export, lint |
| 3 | `retry` | a **binary** as well as a library, so the driver is watched and not only asserted on |
| 4 | `login` | two machines in one crate, parent and child |

`tools/verify examples` builds `traffic-light` **on its own** as well as with
the workspace. That is not belt and braces: cargo unifies features across the
members it is building, so under the workspace `timer`'s `alloc` is enabled for
everyone and the `no_std` claim is never tested. Alone, it is the only place
`--no-default-features` is exercised through the macro rather than through the
library's own surface.

One workspace rather than four detached packages, for one reason: a single
`Cargo.lock`, which `tools/verify version` checks against `VERSION`. Four
lockfiles would be four chances to forget.

Kotlin has no build system, so "its own project" means its own `kotlinc`
invocation: `<n>/src/` compiled alone, then `<n>/test/` compiled against that
output rather than alongside it, then run. Compiling the tests as a separate
unit is the point — a test in the same unit can reach anything, so it never
demonstrates that the example's public surface is usable. The Rust half learned
that the hard way when `login`'s test turned out to be reaching through a
private alias.

Swift splits by SwiftPM *target*: one executable per example, each naming its
own dependencies. The checks sit beside the implementation rather than in a
separate module, which is weaker than the other two and deliberate — the
example types are not `public`, and making them so would be a sweep across
every example for the harness's benefit rather than a reader's.

The configuration axis there is the **classpath**. `01-traffic-light` is built
against `core` alone, with no annotations and no testing module, because the
minimum a machine needs is a claim worth checking and a shared classpath checks
it for nobody.

## Why these four

They are chosen to cover the edges rather than to look impressive:

- **`traffic_light`** has no payloads and no effects, so it exercises the
  degenerate cases: `effects Effect { }` (an uninhabited enum), a machine whose
  entire matrix is static except one cell, and `Table::is_fully_static`
  returning true — which is the only condition under which the
  `no-static-entry` lint says anything.
- **`timer`** carries payloads on *both* a state and an action, which is what
  makes narrowed cell arguments worth having. It also has an effect with a
  payload, so the effect handler is narrowed too.
- **`retry`** is the only one where an effect handler returns an action. That
  path is the reason `step` is non-reentrant: the follow-up goes through the
  mailbox rather than recursing.
- **`login`** is a parent and a child, so it exercises `DELEGATE`, the lens,
  and the property that a hole in the child breaks the parent's build.

For the N×M cost at realistic scale, see `rust/tabula/tests/scale.rs` — a
genuine 8×12 machine, measured rather than described.

## Running them

```sh
./tools/verify examples          # Rust
./tools/verify kotlin-examples   # Kotlin
./tools/verify swift-examples    # Swift
```

All three are part of `nix flake check`.

Each language's examples live in a package that depends on tabula **by path,
the way a user would**, outside the main build: `examples/rust` is its own cargo
workspace and `examples/swift-examples` its own SwiftPM package.

That last directory is not called `swift` because SwiftPM derives a path
dependency's identity from its directory basename: with the library at `swift/`
and the examples at `examples/swift/`, both become `swift` and the package
appears to depend on itself. That is the only place
the public API is exercised from outside, and it is how the driver's borrow bug
was found — every unit test had passed because none of them needed two closures
to touch the same state.
