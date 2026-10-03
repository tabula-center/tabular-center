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

**Not compared:** diagnostic text, except for the codes tabular-center itself authors.
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

## What the renderings prove

`<name>.grid`, `<name>.mmd`, `<name>.lint` and `<name>.cov` are **not
committed**. Every implementation renders its own from the `.tbl` at check
time, into a scratch directory, and `tools/verify renderings-agree` diffs them
against each other. What is asserted is that three implementations produce the
same bytes.

They were committed until September 2026: Rust blessed them and the other two
compared against them. That made one implementation's output the expectation
for the other two, and every renderer change meant re-blessing a file that was
a second copy of what the code already said. The property under test was never
"matches this file"; it was "all three agree", and that is what is checked now.

What is lost, and worth naming: a change in lint wording or coverage no longer
shows up as a diff in review. It shows up as agreement or disagreement.

The lints matter more than they look. The lints hold the most
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

`<name>.mmd` is the diagram golden, and it is the only output compared ACROSS
the three implementations. That is what makes it worth a file per fixture:
before a diagram golden existed the three had already drifted on edge ordering,
Rust emitting every `GO` edge before every self-loop while Kotlin and Swift
interleaved them in cell order, and nothing said so.

It was `.puml` first. PlantUML was removed and the check went with it; for the
stretch in between, each language pinned its own edge order against a literal
in its unit tests, which catches one renderer growing a second walk but not the
three disagreeing with each other -- the failure that actually happened.
Mermaid is a format the library still supports, and since every renderer comes
off one walk, pinning one pins the order for all of them.

`<name>.cov` is the coverage report, and it was added by following the lesson
below rather than by finding a bug first. It was the last output that was
rendered in only one language and compared by nothing — and it had drifted from
the lint on two rules: it warned on a *single* deliberate `UNREACHABLE`, which
`spec/cells.md` and `tabular-center::unreachable-heavy` both say must stay silent, and
it reported statically-unreachable states without the fully-static gate, so a
state reached only from a `HANDLE` cell was announced as unreachable. Both
copies of those rules now come from the lint's constants.

Two of the goldens would look different before that fix: `toggle.cov`
carried the spurious `UNREACHABLE` warning that the fixture's own comment
argues against, and `timer.cov` announced `Done` as having no incoming
transition when a `HANDLE` cell leads there.

The general lesson is worth stating, because it has now found three defects.
This suite compares behaviour and committed output, and it is good at both.
None of the three lived in either place: `tabular-center::empty-emit` was behaviour no
fixture exercises, the mermaid ordering was output no golden compares, and the
coverage report was output only one language produced. When looking for the
next one, ask what is *uncompared* rather than what is unchecked.

By that test, the diagram and report renderers are now covered. What is left
uncompared is the **generated source** — deliberately, since Rust names cells
by trait bound and the other two by identifier, so there is nothing to compare.
The compile-fail suites are the substitute, and they are per-language.

`fixtures-complete` checks that every `<name>.tbl` has a trace, and that none
of the four renderings is committed beside it. A committed rendering is a
golden nobody asked for: it would be read by nothing and would drift in
silence.

`renderings-agree` needs two implementations to compare. A run finding only one
FAILS rather than passing, because one implementation agreeing with itself
asserts nothing.

`effects-never` is the fixture that pins the fully-static gate deliberately
rather than by accident: its `Open` state is reachable only through a `HANDLE`
cell, so an implementation that drops the gate announces `Open` as unreachable
— and disagrees with the other two, in its `.cov` and `.lint`.

## Adding a fixture

1. Write `<name>.tbl` and `traces/<name>.trace`. That is the whole fixture:
   the renderings are produced by each implementation at check time, and none
   of them is committed.
2. Add an adapter in each language mapping action names and payload fields to
   real values. The adapter is the only per-fixture code; everything else is
   shared.
3. A fixture with no adapter in some language is reported as **skipped**, not
   passed. Phase 4 and 5 will start with everything skipped, and that must be
   visible rather than silently green.

## `step-algebra.cases`

The composition operations of `spec/cells.md` §6, as cases every harness
replays against its own `Step`. One case per line; blank lines separate
groups:

    map       <step>                    => <step>     f(n) = n + 10
    and_then  <step>  then <step'>      => <step>     f(n) = step', where its
                                                      target may be s or s+N
    zip       <step>  <step>            => <step>     a pair target: go(1,2)

A step is `go(N)`, `go(N,M)`, `stay` or `ignored`, followed for `go` and
`stay` by its effects in brackets, `[a,b]`, or nothing for none. An
`ignored` with effects is not a step this format can express, because it is
not one the spec allows. Expected and actual are compared as text in exactly
this spelling. Each harness also requires every outcome combination to be
present -- three for `map`, nine each for `and_then` and `zip` -- so a case
file that loses one fails rather than passing on less.
