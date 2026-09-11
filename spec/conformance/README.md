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

`<name>.grid`, `<name>.lint`, `<name>.puml` and `<name>.cov` are written by the
Rust harness (`--bless`) and **read** by every other implementation. Neither
Kotlin nor Swift blesses: a renderer or a lint that drifts by a single space
fails there rather than quietly rewriting the shared file.

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

The `.puml` golden is the newest, and it exists because of a drift it would
have caught. Diagram output was uncompared for three phases, and in that time
Rust's mermaid renderer came to emit every `GO` edge before every self-loop
while Kotlin and Swift interleaved them in cell order — the same edge set in a
different order, in three implementations that are supposed to agree. All three
now render mermaid, DOT and PlantUML from one row-major edge walk, and this
golden pins it.

PlantUML rather than mermaid, and only one diagram format: all three come off
the same walk, so pinning any one of them pins the order, and PlantUML's
`A --> B : label` is the easiest of the three to read in a review diff. A
second diagram golden would cost a file per fixture and prove the same thing.

`<name>.cov` is the coverage report, and it was added by following the lesson
below rather than by finding a bug first. It was the last output that was
rendered in only one language and compared by nothing — and it had drifted from
the lint on two rules: it warned on a *single* deliberate `UNREACHABLE`, which
`spec/cells.md` and `tabula::unreachable-heavy` both say must stay silent, and
it reported statically-unreachable states without the fully-static gate, so a
state reached only from a `HANDLE` cell was announced as unreachable. Both
copies of those rules now come from the lint's constants.

Two of these four goldens would look different before that fix: `toggle.cov`
carried the spurious `UNREACHABLE` warning that the fixture's own comment
argues against, and `timer.cov` announced `Done` as having no incoming
transition when a `HANDLE` cell leads there.

The general lesson is worth stating, because it has now found three defects.
This suite compares behaviour and committed output, and it is good at both.
None of the three lived in either place: `tabula::empty-emit` was behaviour no
fixture exercises, the mermaid ordering was output no golden compares, and the
coverage report was output only one language produced. When looking for the
next one, ask what is *uncompared* rather than what is unchecked.

By that test, the diagram and report renderers are now covered. What is left
uncompared is the **generated source** — deliberately, since Rust names cells
by trait bound and the other two by identifier, so there is nothing to compare.
The compile-fail suites are the substitute, and they are per-language.

`tools/verify` checks that every `<name>.tbl` has all four siblings before it
runs any harness. That guard exists because the harness's own "no golden X; run
with --bless" is the wrong advice in the common case: the file usually does
exist and is merely untracked, so nix left it out of the build, and blessing
would have regenerated files already sitting in the tree.

## Adding a fixture

1. Write `<name>.tbl` and `traces/<name>.trace`. Run the Rust harness with
   `--bless` to create `<name>.grid`, `<name>.lint`, `<name>.puml` and
   `<name>.cov`; never write those by hand, since the whole value of a golden
   is that a machine wrote it.
2. Add an adapter in each language mapping action names and payload fields to
   real values. The adapter is the only per-fixture code; everything else is
   shared.
3. A fixture with no adapter in some language is reported as **skipped**, not
   passed. Phase 4 and 5 will start with everything skipped, and that must be
   visible rather than silently green.
