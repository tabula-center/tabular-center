# Examples — Kotlin

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
| 7 | `spec-check` | pinning a matrix to a reviewable `.tbl` fixture with `TabulaTesting` (Swift only) |

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

**Kotlin: `06-generated`, which needs Gradle.** KSP is a Maven artifact and
runs as a build step, so that example carries its own `settings.gradle.kts` and
`build.gradle.kts`, and its generated sources land in `build/generated/ksp/`
and are not committed. Skipped where Gradle is absent, because the alternative
is standing in for the processor by hand.

## Each one is a project, not a module

They were four modules in a single crate per language. They are now four
**projects**: own manifest, own dependency line on tabular-center, own `tests/`
directory. An example is read as a template for a real project, and a real
project does not keep its tests in a `mod tests` at the bottom of `lib.rs`.

Kotlin has no build system, so "its own project" means its own `kotlinc`
invocation: `<n>/src/` compiled alone, then `<n>/test/` compiled against that
output rather than alongside it, then run. Compiling the tests as a separate
unit is the point — a test in the same unit can reach anything, so it never
demonstrates that the example's public surface is usable. The Rust half learned
that the hard way when `login`'s test turned out to be reaching through a
private alias.

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

For the N×M cost at realistic scale, see `tabular-center/tests/scale.rs` in tabular-center-rust — a
genuine 8×12 machine, measured rather than described.

## Running them

```sh
./tools/verify kotlin-examples   # 01-05, kotlinc
./tools/verify kotlin-ksp        # 06-generated, Gradle + KSP
./tools/verify kotlin-compose    # 07-compose
```

Part of `nix flake check`, at the root and in this language's own flake.

The examples depend on the library by path, the way a user would: `kotlinc`
compiles them against the artifacts `tools/verify kotlin` builds, and the two
Gradle builds (`06-generated`, `07-compose`) take `../../core` as a source set
and include `../../ksp` as a build.
