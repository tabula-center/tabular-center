# tabula

State machines whose declaration *is* the transition matrix.

```rust
transition_matrix! {
    machine Timer;
    states  { Idle, Running(u32), Done }
    actions { Start, Tick, Cancel }
    effects Fx;

    //            Start                        Tick      Cancel
    Idle    => [  HANDLE,                      IGNORE,   IGNORE                 ];
    Running => [  IGNORE,                      HANDLE,   GO!(Idle, Fx::Stop)    ];
    Done    => [  GO!(Running(0), Fx::Start),  IGNORE,   IGNORE                 ];
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

## The composition property

> Scoping a total child machine into a total parent yields a total parent,
> and the compiler proves it by the same mechanism as everything else.

## Status

| Phase | Content | State |
|---|---|---|
| 0 | Foundations, flake, CI | done |
| 1 | Rust core, hand-written reference | done |
| 2 | `transition_matrix!` | done |
| 3 | Cross-language conformance spec | done |
| 4 | Kotlin core + KSP | blocked (needs Kotlin 2.x + KSP toolchain) |
| 5 | Swift core + macro | todo |
| 6 | Composition | done (Rust) |
| 7 | Effects surface | needs a grammar change |
| 8 | Introspection, lints, golden snapshots | done (Rust) |
| 9a | Driver and mailbox | done (Rust) |

See `ARCHITECTURE.md` for the design and `PLAN.md` for the task breakdown.

## Development

```sh
nix develop          # all three toolchains
nix develop .#rust
nix flake check      # fmt + lint + test, all implementations
nix run .#conformance
```

Without nix: `cd rust && cargo test`.
