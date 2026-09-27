# Examples — Rust

Four machines, the same four in every language, ordered by what they add:

| | machine | introduces |
|---|---|---|
| 1 | `traffic_light` | the minimum: three states, two actions, no payloads, no effects |
| 2 | `timer` | payloads on states and actions, effects, the effect handler |
| 3 | `retry` | the driver: effects producing follow-up actions through the mailbox |
| 4 | `login` | composition: a `session` machine delegating to an `auth` machine |
| 5 | `suspend` | the other color: a machine whose `step` suspends (Kotlin only) |
| 6 | `generated` | matrix declared in **annotations**; KSP generates the dispatcher (Kotlin only, needs Gradle) |
| 6 | `observable-counter` | `ObservableStore`, and the only example that can *skip* (Swift only) |
| 7 | `spec-check` | pinning a matrix to a reviewable `.tbl` fixture with `TabularCenterTesting` (Swift only) |

Each is a working machine with tests, and each is written twice — once per
language — because the second writing is a review of the first. Two findings
that changed the design came out of exactly that (see `PLAN.md`).

The same four machines exist in every implementation, each directory holding
its own: `tabular-center-rust/examples`, `tabular-center-kotlin/examples`,
`tabular-center-swift/examples`. Each language's set lives inside that
language's directory so the directory stands alone -- its flake checks its
examples with nothing from the other two.

## Compile-time generation

The library's whole claim is that the dispatcher is generated. An example that
hand-writes one demonstrates the runtime and nothing else, so what each
language's examples do about generation is worth stating plainly — the three
are in genuinely different positions, and only one of them needs a build
configuration for it.

**Rust: every example, with no configuration at all.** `transition_matrix!` is
a `macro_rules!` macro, so expansion is `rustc`'s job. There is no build
script, no plugin, and nothing written to disk — which is why all four Rust
examples exercise the generator by existing, and why there is nothing here to
gitignore. `cargo build` is the whole story.

## Each one is a project, not a module

They were four modules in a single crate per language. They are now four
**projects**: own manifest, own dependency line on tabular-center, own `tests/`
directory. An example is read as a template for a real project, and a real
project does not keep its tests in a `mod tests` at the bottom of `lib.rs`.

Splitting them also lets each cover a different **configuration**, which a
single crate structurally cannot — one set of features, one edition, one shape
for everybody:

| | crate | configuration it covers |
|---|---|---|
| 1 | `traffic-light` | `#![no_std]`, tabular-center with `default-features = false` |
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

For the N×M cost at realistic scale, see `tabular-center/tests/scale.rs` in tabular-center-rust — a
genuine 8×12 machine, measured rather than described.

## Running them

```sh
./tools/verify examples     # or tabular-center-rust/tools/verify examples
./tools/verify rust-gui     # 05-iced
```

Part of `nix flake check`, at the root and in this language's own flake.

The examples depend on the library **by path, the way a user would**, and sit
outside its workspace: this directory is its own cargo workspace, and
`05-iced` its own package with its own lock and its own `rust-toolchain.toml`
(current stable; the four above hold the library's 1.75). That is the only
place the public API is exercised from outside, and it is how the driver's
borrow bug was found -- every unit test had passed because none of them needed
two closures to touch the same state.
