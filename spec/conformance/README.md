# Conformance suite

The three implementations will drift unless something forces them not to.
Each fixture describes a machine declaratively; every language commits a real
machine implementing it, and the harness checks two things:

1. **Table conformance** — the generated `TABLE` matches the fixture cell for
   cell. Catches a generator that mis-parses a cell kind.
2. **Trace conformance** — replaying the trace produces the declared outcomes
   and effects. Catches a dispatcher that is wired up wrong.

## Why not JSON

The harness has to parse this offline, in a Nix sandbox, from a crate with no
dependencies. A hand-rolled JSON parser is 150 lines that prove nothing. The
`.tbl` format is line-oriented, human-diffable, and parses in about 60 lines —
and being diffable is what `table-diff` wants anyway, so the format does double
duty as the golden-snapshot format.

## What is compared, and what is not

**Compared:** cell kinds, `GO` targets, effect names, outcome per step,
effects emitted per step, state variant names, optional payload field values.

Names are compared **exactly**, in the fixture's spelling — the variant names
the generators produce. Swift enum cases are lowerCamel, so its adapters map
effects to the fixture spelling rather than interpolating the enum. Making the
comparison case-insensitive would have been easier and would have hidden real
drift alongside the casing.

**Not compared:** generated source. Rust names cells by trait bound
(`Handle<Timer, Idle, Start>`) because `macro_rules!` cannot concatenate
identifiers; Kotlin and Swift name them by identifier (`idleStart`). Both give
the same guarantee. Comparing source would encode that accident as a
requirement — see ARCHITECTURE.md section 11.0.

**Not compared:** diagnostic text, except for the codes tabula itself authors.
The missing-implementation error comes from each language's own compiler and
reads differently in each. See `spec/diagnostics.md`.

## `.tbl` format

```
machine Timer
initial Idle
states  Idle Running Done
actions Start Tick Cancel

Idle    | HANDLE                  | IGNORE | IGNORE
Running | IGNORE                  | HANDLE | GO(Idle, StopClock)
Done    | GO(Running, StartClock) | IGNORE | IGNORE
```

- Blank lines and `#` comments are skipped.
- Row order must match `states`; cell order must match `actions`.
- Cells: `IGNORE`, `HANDLE`, `UNREACHABLE`, `GO(Target)`,
  `GO(Target, Eff, ...)`, `EMIT(Eff, ...)`, `DELEGATE(Child)`.
- Effect names are compared by their **last path segment**, so a Rust table
  holding `Effect::StopClock` matches a fixture saying `StopClock`. Languages
  spell qualification differently and that is not a behavioural difference.

## `.trace` format

```
trace reaches-done
  ctx  limit=3
  from Idle
  Start      => go Running  ! StartClock
  Tick now=1 => stay
  Tick now=9 => go Done     ! StopClock
  Cancel     => ignored
```

- `ctx` seeds cross-state data; `from` is the starting state, and accepts
  payload fields exactly as `go` does (`from Running since=4`). The two must
  stay symmetric — an earlier version parsed fields on `go` only, which
  silently dropped them from `from` and started a composition trace in the
  wrong child state.
- A nested state is addressed by a prefixed field (`child_attempt=1`) rather
  than by nesting. The format is flat on purpose; nesting would buy little and
  cost every implementation a recursive parser.
- Outcomes: `go <State> [field=value ...]`, `stay`, `ignored`.
- `!` introduces the effects expected from that step, in emission order.
  Absent means none.
- `stay` and `ignored` are distinct assertions. A machine that returns
  `Step::stay()` where the trace says `ignored` fails, and should — the
  distinction is load-bearing for the reachability linter.

## What the goldens prove

`<name>.grid` and `<name>.lint` are written by the Rust harness (`--bless`) and
**read** by every other implementation. Neither Kotlin nor Swift blesses: a
renderer or a lint that drifts by a single space fails there rather than quietly
rewriting the shared file.

The lint golden matters more than it looks. The lints hold the most
per-language logic in the project — the 70% and 25% thresholds, `dead-row`
subsuming `no-static-exit`, the fully-static gate on reachability — and until
this existed the three implementations printed their warnings side by side with
nothing checking that they agreed.

One caveat: Rust computes its lint report with `PAYLOADS`, and the fixture
machines in the other two languages do not declare payload metadata. No fixture
currently triggers `payload-hoist`, so the outputs match. A fixture that did
would need payload metadata in all three.

Three renderers agreeing byte for byte is a stronger statement than it looks. It
means the padding rules, the right-trimming, and the cell text for all six
kinds match across three languages — and those are exactly the details that rot
silently.

## Adding a fixture

1. Write `<name>.tbl` and `traces/<name>.trace`.
2. Add an adapter in each language mapping action names and payload fields to
   real values. The adapter is the only per-fixture code; everything else is
   shared.
3. A fixture with no adapter in some language is reported as **skipped**, not
   passed. Phase 4 and 5 will start with everything skipped, and that must be
   visible rather than silently green.
