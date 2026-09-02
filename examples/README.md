# Examples

Four machines, the same four in every language, ordered by what they add:

| | machine | introduces |
|---|---|---|
| 1 | `traffic_light` | the minimum: three states, two actions, no payloads, no effects |
| 2 | `timer` | payloads on states and actions, effects, the effect handler |
| 3 | `retry` | the driver: effects producing follow-up actions through the mailbox |
| 4 | `session` | composition: a parent delegating to a child machine |

Each is a working machine with tests, and each is written twice — once per
language — because the second writing is a review of the first. Two findings
that changed the design came out of exactly that (see `PLAN.md`).

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
- **`session`** is a parent and a child, so it exercises `DELEGATE`, the lens,
  and the property that a hole in the child breaks the parent's build.

For the N×M cost at realistic scale, see `rust/tabula/tests/scale.rs` — a
genuine 8×12 machine, measured rather than described.

## Running them

```sh
./tools/verify examples          # Rust
./tools/verify kotlin-examples   # Kotlin
```

Both are part of `nix flake check`.
