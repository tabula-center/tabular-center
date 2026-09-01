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

- `ctx` seeds cross-state data; `from` is the starting state.
- Outcomes: `go <State> [field=value ...]`, `stay`, `ignored`.
- `!` introduces the effects expected from that step, in emission order.
  Absent means none.
- `stay` and `ignored` are distinct assertions. A machine that returns
  `Step::stay()` where the trace says `ignored` fails, and should — the
  distinction is load-bearing for the reachability linter.

## Adding a fixture

1. Write `<name>.tbl` and `traces/<name>.trace`.
2. Add an adapter in each language mapping action names and payload fields to
   real values. The adapter is the only per-fixture code; everything else is
   shared.
3. A fixture with no adapter in some language is reported as **skipped**, not
   passed. Phase 4 and 5 will start with everything skipped, and that must be
   visible rather than silently green.
