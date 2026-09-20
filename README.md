# tabula

State machines whose declaration *is* the transition matrix.

```rust
transition_matrix! {
    machine Timer;
    context Ctx;
    state   State;
    action  Action;
    effects Effect { StartClock, StopClock { reason: u32 } }
    initial Idle;

    states  { Idle, Running { since: u32 }, Done }
    actions { Start, Tick { now: u32 }, Cancel }

    //            Start                              Tick     Cancel
    Idle    => [  HANDLE,                            IGNORE,  IGNORE                             ];
    Running => [  IGNORE,                            HANDLE,  GO!(Idle, StopClock { reason: 0 }) ];
    Done    => [  GO!(Running { since: 0 }, StartClock), IGNORE, IGNORE                          ];
}
```

## The one guarantee

> Every cell of the state x action matrix is a required member.
> **An incomplete machine does not compile.**

Not enforced by pattern-matcher exhaustiveness — that is defeated by `else`,
`default`, `_`, and guard clauses. Not enforced by function purity — that is
unenforceable in Kotlin and Swift, so any claim built on it is broken by a
single `println`. Enforced by the oldest mechanism in every one of these
languages: *you declared a required member and did not implement it.*

States, actions, **and effects** are all generated sum types. Effects too,
because the generator can only demand one handler per effect variant if it
knows the variants — so adding an effect breaks every handler's build, the
same way adding a state breaks every matrix.

## The composition property

> Scoping a total child machine into a total parent yields a total parent,
> and the compiler proves it by the same mechanism as everything else.

## Status

| Phase | Content | State |
|---|---|---|
| 0 | Foundations, flake, CI | done |
| 1 | Rust core, hand-written reference | done |
| 2 | `transition_matrix!` | done, `prototype async fn handle;` included |
| 3 | Cross-language conformance spec | done |
| 4 | Kotlin core + KSP | done; the processor runs under `nix flake check` |
| 5 | Swift core + macro | everything but macro expansion; `MachineSyntax` reads the surface, and the emitter's output is compiled by `swift-codegen` |
| 6 | Composition | done (all three) |
| 7 | Effects surface | done (all three) |
| 8 | Introspection, lints, golden snapshots | done (all three); shared goldens read by all three |
| 9a | Driver and mailbox | done (all three) |

See `ARCHITECTURE.md` for the design, `PLAN.md` for the task breakdown, and
`examples/` for the worked machines — the same four core examples in every
language, ordered by what each one adds, plus a few that exist in only one
(a suspend driver and a KSP-generated machine in Kotlin, `ObservableStore` and
`TabulaTesting` in Swift).

## Development

```sh
./tools/verify       # everything CI checks
./tools/verify test  # one step

nix develop          # all three toolchains
nix flake check      # the same steps, sandboxed, as CI runs them
nix run .#conformance
nix run .#table-diff

nix run .#release -- 0.1.0   # set the version everywhere, verify, tag
nix run .#publish            # dry run; --execute to ship
```

`flake.nix` is a table of contents; the pieces live in `nix/`. `VERSION` is the
single source of truth for the version number and every manifest is derived
from it — three files drifting apart is the normal way a polyglot release goes
wrong.

Without nix: `./tools/verify` runs the same steps `nix flake check` does, and
falls back to rustc's lints where clippy is unavailable.
