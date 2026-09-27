# Examples — Swift

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

**Swift: not yet, and not for want of an example.** There is no compile-time
generator to consume. `TabularCenterMacros` is still blocked on the swift-syntax
packaging question, and `TabularCenterCodegen` is a `MachineDesc -> String` emitter
with no way to invoke it from a build — it takes a Swift value, not a file.

When one lands, the example is a SwiftPM build-tool plugin, and the shape is
already decided by the other two: a declaration in the example, generated
sources in `.build/`, nothing committed, and the example skipped rather than
faked where the toolchain cannot run it.

## Each one is a project, not a module

They were four modules in a single crate per language. They are now four
**projects**: own manifest, own dependency line on tabular-center, own `tests/`
directory. An example is read as a template for a real project, and a real
project does not keep its tests in a `mod tests` at the bottom of `lib.rs`.

Swift splits by SwiftPM *target*: one executable per example, each naming its
own dependencies. The checks sit beside the implementation rather than in a
separate module, which is weaker than the other two and deliberate — the
example types are not `public`, and making them so would be a sweep across
every example for the harness's benefit rather than a reader's.

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
./tools/verify swift-examples
```

Part of `nix flake check`, at the root and in this language's own flake.

The examples are their own SwiftPM package, depending on the library by path
(`.package(path: "..")`), the way a user would. SwiftPM names a path
dependency by its directory's basename, so the products are
`.product(name: "TabularCenter", package: "tabular-center-swift")`.

History worth keeping: this directory was `examples/swift-examples`, not
`examples/swift`, because with the library at `swift/` both basenames were
`swift` and the package appeared to depend on itself (`cyclic dependency
declaration found`). Here the package's own identity is `examples` and the
library's is `tabular-center-swift`, so nothing collides; a future rename
that makes them equal would bring the cycle back.
