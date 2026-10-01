# Happy paths

**Status: declaration, validation and derived defaults implemented in Kotlin
and Swift. The narrowed calling surface is not. Rust has none of it yet.**

A machine's success case reads differently from its failures, and a `when` over
every outcome flattens that back out. Kotlin's null-safety is loved for the same
reason `Optional` is not: the shape of the code says which case is ordinary.

Prior art is [`hadilq/happy`](https://github.com/hadilq/happy), which does this
for sealed classes. This is the state-machine version: the happy path is
declared **in the matrix**, defaults are derived from it, and the calling
surface narrows to it.

## The rule that constrains everything else

A happy-path sugar is an `else` unless it is built very carefully, and `else` is
the thing this library exists to make unavailable (ARCHITECTURE 1).

`happy` ships two shapes and they land on opposite sides of that line:

- **`elseIf`** takes one lambda for everything that is not the happy variant.
  That is an `else`. Add a state and the lambda still compiles, still runs, and
  now silently swallows a case nobody has considered.
- **`elvis`** takes one named parameter per non-happy variant. Add one and every
  call site stops compiling.

**Only the `elvis` shape is permitted.** The `elseIf` shape is allowed where a
machine has exactly two outcomes, because there the two are indistinguishable.
The generator enforces that; it is not a documented convention.

## A path is a spine, not a cell

Two readings were available and they are different features. A cell could be
marked happy, or a *route* through the table could be — a sequence of states
from `initial` to a terminal one.

The spine is the one that earns its keep:

- **Defaults become derivable.** A `HANDLE` on the spine with no declared target
  defaults to the next state along it, so the common case stops being typed at
  all. A per-cell marker cannot do this — it does not know what comes next.
- **The lints have something to check.** A spine that never reaches a terminal
  state, or one that leaves the matrix through an `IGNORE`, are errors a route
  can have and a square cannot.
- **Per-cell falls out of it for free.** The cells a spine passes through are
  marked by definition. The reverse does not hold.

## Declaration

A separate `@Path`, naming a state sequence. Not a cell kind and not a flag on
existing kinds.

States and actions **alternate**, starting and ending with a state:

```kotlin
@Path(
    "connect",
    [S.Idle::class, A.Start::class, S.Connecting::class, A.Ready::class, S.Live::class],
)
```

A states-only spine was the first design and it does not survive contact with
the feature it exists for. Defaults are derived by turning a `HANDLE` on the
spine into a `GO` to the next state -- but a `HANDLE` has no target by
definition, and a row may hold several. `Connecting` being
`[HANDLE, HANDLE, IGNORE]` with a spine saying `Connecting -> Live` names no
cell at all.

Three ways out: refuse rows with more than one `HANDLE` (a fifth diagnostic,
refusing machines that are fine), derive only where there is exactly one (the
sugar quietly doing less on some rows than others), or name the action. Naming
the action is the only one where nothing is refused and nothing is silent.

It buys more than it costs:

- **`tabular-center::path-broken` becomes precise.** It checks *that* cell rather than
  *some* cell in the row, which closes the weakness a states-only spine had --
  a `HANDLE` anywhere made a row connect to anything.
- **The declaration reads as the run it describes.** `Idle -Start-> Connecting
  -Ready-> Live` is what a developer would write on a whiteboard, and it is
  what the narrowed surface will be named after.
- **It is the anchor for the sugar.** A spine that names actions can generate a
  method per hop, a "what happens next" the IDE can complete, and an `elvis`
  whose non-happy parameters are exactly the cells the spine does not pass
  through. A states-only spine can generate none of those, because it does not
  know which action it meant.

An even number of elements, or two states adjacent, is `tabular-center::path-broken`:
a route is a sequence of hops, and a hop is a state, an action, and a state.

`Kind.HAPPY` reads wrong: happiness is orthogonal to what a cell *does*, and a
cell is already `GO`, `HANDLE`, `EMIT` or `IGNORE`. A `happy = true` argument on
the existing kinds is honest and puts noise in a file whose entire point is that
a reader scans columns.

The objection to a separate annotation is that the route lives somewhere a
reader of the matrix will not see it. That is answered by a lint rather than by
syntax: a spine whose consecutive states are not connected by a real cell is an
error, so the declaration and the table cannot drift.

Paths are named, so a machine may have more than one, and the narrowed calling
surface says which it narrows to.

## Three languages, or it is not in the core

ARCHITECTURE 2: one guarantee, three implementations. `elvis` is Kotlin-shaped
and does not transfer directly.

- **Rust.** The narrowed result is a `Result`-alike and `?` already does this.
  The question is whether the generated type can be `Try`-compatible, so the
  happy path is a `?` and nothing else is needed.
- **Swift.** `guard case .happy(let x) = step else { ... }` is the existing
  idiom and is **not** sufficient: `guard ... else` does not reject a missing
  case, so it is `elseIf` wearing different syntax. A generated `throws` overload
  with `try` is the closer analogue, because the compiler enforces handling.

If it cannot hold in all three it is Kotlin sugar and belongs behind the gate
that PLAN 9b's rendering surface sits behind, not in the core.

## Diagnostics this introduces

Normative: all four are implemented in Kotlin and Swift. Each has a section in
`spec/diagnostics.md`, a row in `spec/diagnostics-coverage.md`, and a UI test,
per PLAN's cross-cutting rule that every diagnostic gets one.

| code | when |
| --- | --- |
| `tabular-center::path-broken` | a hop names a cell the matrix does not have, or the elements do not alternate state-action-state |
| `tabular-center::path-unterminated` | a path does not reach a state with no outgoing transition |
| `tabular-center::path-unknown-state` | a `@Path` names a state the machine does not declare |
| `tabular-center::path-duplicate` | two paths share a name |

## Additive, and that is the whole constraint

**Existing code keeps working, unchanged.** A developer who never writes a
`@Path` sees nothing new: same `step`, same `perform`, same `Cells`, same
`TABLE`. The spine is opt-in, and what it buys is that the ordinary case reads
as ordinary and the corner cases sit where corner cases belong.

That rules out the obvious design, which was the first one written here and was
wrong. Putting `paths` on `Table` would make the spine part of the inert data
every implementation is guaranteed to carry, and make every `Table(...)` in the
repository a thing that could now be wrong -- for a feature most machines will
not use.

### What that means, concretely

- **`@Path` is read at generation time and discarded.** The generator uses it
  to derive defaults and to emit the narrowed surface. Nothing survives into
  the runtime types.
- **`Table` does not change.** No `paths` field, in any of the three cores.
- **`.tbl` and `.trace` do not change.** A conformance fixture describes the
  *resolved* matrix, and the spine resolves away before anything a fixture
  compares. The previous revision of this file concluded `.tbl` needed a `path`
  line; that followed from the `Table` mistake and goes with it.
- **A machine with a spine and the same machine written longhand produce
  byte-identical `TABLE`, `.grid`, `.lint`, `.cov` and `.mmd`.** Nothing
  downstream can tell which was written, which is the test for whether this
  stayed additive.

### Two consequences worth stating

**A spine changes generated output, and only generated output.** A `HANDLE` on
the spine with no declared target becomes a `GO` to the next state along it, so
that machine's golden shows the derived target -- written by the generator
rather than by the developer. `TABLE` is the same either way; the dispatcher is
what the spine shortens.

**The narrowed surface is a second way to call the same machine.** `elvis` is a
new generated member. `step`, `perform` and `Cells` are untouched, so a caller
that ignores it compiles exactly as before. Both surfaces exist, deliberately.

## The narrowed surface: one member per hop

A hop is `(from, action, to)`, and that is exactly the signature of a call a
developer makes. So the surface is generated per hop, named after both halves:

```kotlin
// In state Connecting, whatever arrived: Ready is the happy continuation.
val (live, effects) = cells.connectingReady(ctx, state, action).elvis(
    Connecting = { return stillWaiting() }, // an IGNOREd action: nothing moved
    Failed = { return showBanner(it.state) },
)
```

(The first sketch here wrote `x elvis (Failed = { ... })`, which is not
Kotlin: an `infix` call takes one expression, and a named argument is not one.
Named handlers need `.elvis(...)`; the `infix` form is for exactly one
alternative, with a trailing lambda -- `hop elvis { ... }`.)

Three things fall out of the hop, none of which a states-only spine could give:

- **The happy result is a single, narrowed type.** `S.Live`, not `S`. The hop
  says where `Ready` goes from `Connecting`, so the caller gets that state and
  not a `when` over four.
- **The parameters are the cells the hop does not reach.** From `Connecting`,
  `Drop` goes to `Failed`, so `Failed` is the one named parameter. `Ready` from
  anywhere else is not this call's business.
- **Adding a state adds a parameter.** A new outcome reachable from
  `Connecting` becomes a new required argument and every call site stops
  compiling, which is `elvis` rather than `elseIf` and is the whole reason only
  one of the two is permitted.

### What it is not

**Not a replacement for `step`.** `step`, `perform` and `Cells` are unchanged
and a caller that ignores the spine sees nothing new. Both surfaces exist.

**Not a path runner.** `connectingReady` advances one hop. A member that ran
the whole path would have to decide what happens when a corner case interrupts
it halfway, and there is no answer to that which is not a policy -- which is
the kind of decision this library pushes back to the developer rather than
inventing.

**Not available off the spine.** There is no `liveDrop`, because no hop names
it. A cell the happy path does not pass through is reached through `step`, the
way everything was before. That asymmetry is the feature: corner cases are
second-class in the interface because they are second-class in the intent.

### Settled before implementation

Three questions, answered here because three implementations depend on the
answers, and "worth settling before implementation" meant exactly that.

**What a hop member takes: the action that arrived.** Not the hop's own
action -- the one the caller has, from the outside world. The reason is
derivation, above: a `HANDLE` named by a hop is turned into a `GO` to the hop's
next state, so after derivation every hop cell is a `GO`, and a member that
performed the hop's own action would have exactly one outcome. Its `elvis`
would handle nothing. What the example above means -- `Failed` as a parameter
because `Drop` leads there -- is the row: *in `Connecting`, whatever arrives,
the happy continuation is `Live`, and here is what else can happen*. So:

```kotlin
val (live, effects) = cells.connectingReady(ctx, state, action).elvis(
    Connecting = { return stillWaiting() }, // an IGNOREd action: nothing moved
    Failed = { return showBanner(it.state) },
)
```

The member is named for the hop, because the hop is what makes it exist and
what an IDE should offer "next" on; it dispatches through `step`, so the
matrix, not the member, decides.

**Its outcomes are the states the `from` row can produce**, by cell kind:

| cell in the `from` row | outcome |
|---|---|
| the hop's own cell (`GO(to)` after derivation) | `to` -- the happy one |
| `GO(t)` | `t` |
| `EMIT`, `IGNORE`, `DELEGATE` | `from` -- the machine stays |
| a `HANDLE` the path does not name | any state: its code decides |
| `UNREACHABLE` | none: it is a trap, not an outcome |

Every outcome but `to` is a named, required parameter, keyed by **state** --
two actions reaching `Failed` are one `Failed` parameter, and an action
reaching `to` by another route is the happy outcome too. This is what makes
"adding a state adds a parameter" true: a state becomes reachable from
`Connecting` by a new `GO`, or by any `HANDLE` in the row, and every call site
stops compiling until it says what to do there.

**Effects come back with the state; the member never runs them.** The outcome
carries the `Step`'s effects beside its state, so the happy result is
`(state, effects)` and running them stays the caller's, visible at the call
site. Running `perform` inside would hide an effect execution inside what
looks like a transition -- the concern this question was left open for.

**The spelling, per language** -- each keeps the property that a new outcome
breaks every call site:

- **Kotlin:** `hadilq/happy`'s shape, which its source shows is required.
  The member returns a generated sealed outcome type, one per hop; `elvis` is
  an `inline` extension on it, one UpperCamel lambda per non-happy outcome,
  `infix` when there is exactly one. `inline` is what lets a handler `return`
  from the caller -- the railway -- and why it cannot be a `Cells` member.
- **Swift:** labelled closures, one per non-happy outcome, `rethrows`:
  `try hop.elvis(failed: { ... })`. A missing label does not compile; a
  handler escapes by throwing, which is Swift's non-local exit. (Not
  `guard case`, which does not reject a missing case.)
- **Rust:** `narrow::<Connecting, Ready, _>(cells, ctx, state, action)`,
  returning `Result<(Live, Effects), (State, Effects)>`, so `?` is the
  railway. *Revised when implemented,* from a generated enum per hop with an
  exactly-row-shaped `Else`: `macro_rules!` cannot join identifiers into a new
  name (`connecting_ready`, `ConnectingReadyElse`) or deduplicate a set (two
  `GO`s to `Failed` must be one variant), and the crate takes no proc-macro or
  `paste` dependency to get round that. So `transition_matrix!` implements a
  `Hop<Ready>` trait on the hop's existing `from` type, and the `Err` side is
  the machine's whole `State`. The guarantee stands -- a `match` on it is
  exhaustive, so a new state breaks every call site that matches -- and the
  cost is precision: a handler sees states a given row cannot produce. One
  more: a hop shared by two paths generates its `Hop` impl twice, which rustc
  reports as a conflict (E0119), where Kotlin and Swift deduplicate.

## What `hadilq/happy` does, read from its source

Read in September 2026 from `happy-processor-common` -- `FindCases.kt`,
`GenerateElvisFunction.kt`, `GenerateBuilderFunction.kt`,
`GenerateHappyFile.kt` -- and the nested tests in `happy-sample`. What it does,
and what each part means here.

- **Nested cases flatten to their leaves, named by path.** `findCases` walks
  the sealed hierarchy; an intermediate sealed level contributes only its name,
  a leaf becomes a case, and the names are joined with nothing between them:
  `A.SituationOne.OptionTwo` is `SituationOneOptionTwo`. The happy type is
  filtered at every level, so it may itself be nested (`A.B.HappyA`, beside
  `BOptionOne`). *Here:* a hop is `(from, action)`, so a cell never nests
  beyond those two names -- except through `DELEGATE`, where a hop's non-happy
  outcomes include the child's. Those should flatten the same way, child
  then state (`AuthLockedOut`), which is the scheme `happy` settled on.
- **`elvis` takes one parameter per leaf, named by the flattened path, in
  UpperCamel** -- `BOptionOne = { ... }` -- matching the variant it stands
  for, as this spec's `Failed = { ... }` already does. Each handler receives the
  whole narrowed value and must return the happy type. The body is an
  exhaustive `when(this)`: happy first, then every leaf, **no `else`**.
- **`elvis` is an `inline` extension on the sealed type**, and that is what
  makes the railway style work: a handler may `return` from the enclosing
  function (`{ return B.failure(it.why) }`). *Here, a constraint on the
  design:* a Kotlin interface member cannot be `inline`, so a hop's `elvis`
  cannot be a `Cells` member. The hop member returns a generated per-hop
  outcome type -- the happy state, or one of the states the hop can otherwise
  reach -- and `elvis` is an `inline` extension on it, which is `happy`'s own
  architecture, one sealed type per hop.
- **`infix` only when there is exactly one non-happy leaf.** With more, Kotlin
  needs the parentheses of named arguments; `happy`'s README calls it the one
  disadvantage. The same holds for a hop with one alternative outcome.
- **`elseIf` loses a forgotten case at runtime, and this is why it is
  forbidden here.** The generated body starts from `var result: HappyA? = null`,
  each case function assigns it only if the value matches, and it ends in
  `return result!!` (the many-case builder uses a `lateinit` the same way). A
  case the caller omits is a `NullPointerException`, not a compile error --
  the property "The rule that constrains everything else" exists to rule out,
  now documented from the source rather than asserted.
- **Flattened names are never checked for collisions.** `happy` joins names
  with `""` and trusts the result; so do this project's emitters, whose cell
  members are `lower(state) + Cap(action)`. States `LogIn`/`Log` and actions
  `Start`/`InStart` both give `logInStart`. In Kotlin the two stay legal
  overloads (their parameters differ) and in Rust cells are keyed by type, not
  name; but a Swift cell whose state and action carry no payload takes only
  `_ ctx`, so two colliding payload-free cells are an "invalid redeclaration"
  in generated code instead of a diagnostic at the matrix. The narrowed
  surface would inherit the same scheme. PLAN.md, happy paths, tracks it.

## A path may name how it is walked backwards

**All three.** Swift spells it as a labelled third argument,
`@Path("checkout", [..], back: .back)`; Rust as a suffix in the `paths`
block, `checkout: [..] back Back;`. Both are optional, so every path already
written parses unchanged.

One difference worth knowing: a **forward** hop's cell is checked -- it must
be able to reach the next state, or `path-broken` -- while a **back** cell is
not. A path has no opinion about what else a back action does, so a cell it
does not derive passes untouched. That is also what keeps a back cell clear
of `path-unterminated` at the path's end.

```kotlin
@Path("checkout", [Cart, Next, Address, Next, Payment, Next, Review, Next, Placed],
      back = Back::class)
```

For each hop `A -next-> B`, the cell `(B, back)` derives to `GO(A)` — over
`HANDLE` cells only, exactly as the forward direction derives, so an explicit
cell is left alone and a path without `back` behaves as before.

It is here because the first version of this feature did not earn its place.
Deriving only the forward direction saved one target per step, which is not
worth a declaration; the wizard example still wrote its whole `Back` column by
hand, which is the route again in the opposite order — the one place where a
wrong target looks exactly like a right one and only a reader walking the
machine in their head can tell.

What a spine is *for* is the duplication, not the character count: a route
that exists twice can disagree with itself, and no diagnostic can catch that
because both halves are well-formed tables. With `back` the route exists once
in each direction it is actually travelled, and the four `path-*` codes hold
it to the rows.

What it still does not buy is a smaller machine. Decline, abandon and retry
are a third of a checkout's cells and no route describes them. That is the
honest limit: a path removes what was duplicated, not what was decided.

## Rust: the spine without identifier comparison

**Status: A chosen and implemented -- derivation and the four `path-*`
codes.**

A was chosen over B to keep Rust close to Kotlin and Swift: derivation is the
part B could not do. (B's checks would have run in `const` evaluation, at
compile time; neither option could panic at runtime.)

Everything a spine does in Kotlin and Swift -- the four `path-*` codes and the
`HANDLE`-to-`GO` derivation -- asks one question: *is this identifier that
one?* Is `Connecting` a declared state; is the cell at `(Idle, Start)` a hop.
`macro_rules!` cannot ask it: two `$x:ident` fragments cannot be compared, only
matched against literal tokens written in a rule. So the Rust arm is a choice
between two ways around that, with different costs.

### A. A generated lookup macro — full parity

The path expands into a local `macro_rules!` whose rules are the path's own
identifiers as literals: `(Idle, Start) => ...`, `(Connecting, Ready) => ...`,
and a fallback. Every cell the row muncher visits is passed through it:

- **Derivation.** A `HANDLE` at a hop comes back as `GO!(next)`, so its
  `Handle` bound is never generated and the dispatcher arm is static -- the
  same as Kotlin and Swift, and the additive test holds as stated.
- **All four codes as `compile_error!`**, with tabular-center's own text:
  `path-unknown-state` by a second generated macro whose rules are the
  declared states; `path-broken` by the fallback seeing a hop's cell that is
  neither `HANDLE` nor `GO` to the next state; `path-duplicate` and
  `path-unterminated` structurally, while the path is parsed.

The cost is real. A macro that defines a macro needs the `$` token passed in
from outside (a nested definition cannot write `$` itself); the lookup has to
be continuation-passing, because a macro cannot return a value mid-munch, so
all three munchers -- bounds, dispatch, `TABLE` -- have to be threaded through
it; and every cell costs another expansion step against the recursion limit,
which large machines already approach.

### B. Const evaluation over `TABLE` — validation only

`TABLE` is already a `const` of strings. The path becomes a `const` slice of
names, and a `const _: () = { .. }` block walks both with byte comparison,
which stable `const fn` allows, and `panic!`s with the code:

- **All four codes, detected at compile time**, as "evaluation of constant
  value failed" carrying `tabular-center::path-broken: ...`. The machine and path
  names can be in the message (`concat!` of `stringify!`); *which* hop broke
  cannot, since stable `const` panics take no formatted arguments.
- **No derivation.** The bound is syntactic and the check is a value, so a
  hop cell must already be written `GO!(next)`. In Rust that loses less than
  it sounds: a `GO!` cell already needs no `Handle` impl, which is the entire
  benefit derivation buys Kotlin and Swift. What is lost is writing the target
  once, in the path, instead of once per hop.

That makes B's `path-broken` **stricter** than Kotlin's and Swift's: a hop
must be `GO!` to the next state, not `HANDLE` or `GO!`. The additive test holds
trivially, since the longhand is the only form.

### Recommendation

**B first.** It closes the four codes in Rust -- the named requirement below --
with a few dozen lines outside the munchers, and every piece of it is ordinary
Rust a reviewer can read. A stays available if writing `GO!` at each hop turns
out to be the friction the spine exists to remove; the iced examples in PLAN's
backlog are the place that would show it. The cost of B is one semantic
difference, recorded above, and a less specific message than the other two
languages give.

## Diagnostics are compile-time, not lints

The four `path-*` codes join the nine existing compile-time diagnostics
(`row-arity`, `unknown-state` and the rest) rather than the seven runtime
lints, because a broken spine is rejected by `buildDesc` before a table exists.

That is a much smaller surface than the first revision assumed: compile-fail
fixtures in `tabular-center-rust/tabular-center/tests/compile_fail/`,
`tabular-center-kotlin/ksp/compile-fail/fixtures/` and `tabular-center-swift/macros/fixtures/`, following the
`//~ EXPECT:` convention all three already share. No conformance fixture, no
adapters, no goldens.

## Order of work

Behaviour lands in `spec/conformance` before any implementation
(PLAN, cross-cutting). That is not ceremony here: a happy path changes what a
*run* means, so the fixture format itself may need a field, and finding that out
after three implementations is the expensive version.

- [x] Answered: nothing in `Table`, `.tbl` or `.trace` changes. The spine is
      read at generation time and discarded, so a machine with one is
      indistinguishable downstream from the same machine written longhand.
- [x] `@Path` in the Kotlin and Swift declaration surfaces, `RawMachine`
      carrying it, and all four `path-*` diagnostics in both `buildDesc`
      implementations, with eight compile-fail fixtures. Rust follows as a
      macro arm; see `spec/diagnostics-coverage.md`.
- [x] Alternate states and actions, per the decision above. `RawPath.hops`
      in both generators; the fixtures and `Spine.tb.kt` use the alternating
      form.
- [x] Derived defaults: a `HANDLE` named by a hop becomes a `GO` to that hop's
      next state (`derive` in `tabular-center-kotlin/codegen/Raw.kt` and
      `tabular-center-swift/Sources/TabularCenterCodegen/Raw.swift`).
- [x] The additive test for the above: a spine-derived machine and the
      longhand one produce equal descriptions and byte-identical emitted
      source, `TABLE` included -- and so identical `.grid`, `.lint`, `.cov`
      and `.mmd`, which are functions of it. `runAdditiveTest` in
      `tabular-center-kotlin/codegen/Tests.kt` and its twin in `TabularCenterCodegenCheck`, each
      with a control showing the path is what makes the difference.
- [x] The four `path-*` diagnostics above, with four compile-fail fixtures each
      in Kotlin and Swift. Compile-time rejections rather than lints — see
      the section below.
- [x] Rust: `paths { .. }` as a `transition_matrix!` arm, with derivation:
      approach A below. `tests/spine.rs` shows a hop needs no `Handle` impl,
      that the spine-derived `TABLE` equals the longhand one, and that without
      the path the same rows differ.
- [x] Rust: the four `path-*` codes. Three are tabular-center's own text, from
      lookups generated out of the declared names -- the same technique as
      derivation. `path-duplicate` is rustc's "defined multiple times": it
      compares two names the machine chose, so there is no declared list to
      generate a lookup from, which is why `unknown-child` is rustc's too.
      Four compile-fail fixtures. One message differs from Kotlin's: a path
      of the wrong shape cannot say how many elements it has, because a
      `compile_error!` message is a literal and the count is not
- [x] The narrowed calling surface, decided: a hop member takes the action
      that arrived, its outcomes are the states the `from` row can produce,
      effects come back with the state, and each language has its spelling.
      See "Settled before implementation". Answered by derivation: after it,
      every hop cell is a `GO`, so the only reading with anything for `elvis`
      to handle is the row.
- [x] Kotlin (emitter and KSP): `HopDesc` on `MachineDesc`, from the validated
      paths' forward hops, deduplicated by `(from, action)`; per hop a sealed
      outcome type, the member (`Cells.` extension, or a `cells` parameter when
      the prototype's receiver takes that slot), and an `inline` `elvis`,
      `infix` for one alternative. States the row cannot produce map to
      `error(...)` in an exhaustive `when` -- unreachable, and no `else`. Hop
      members join `member-collision`'s list. Proven by `kotlin-codegen` (a
      `connect` machine whose `Drop` is an unnamed HANDLE, a call site using
      both `elvis` forms, and `connect_missing_outcome.kt` refused), by
      `Tests.kt` (outcome sets, and the additive property with hops set
      aside), and by `kotlin-ksp`/`kotlin-compose`, which compile the surface
      KSP generates for `Spine.tb.kt` and the Compose checkout
- [x] Swift (emitter; the macro follows when it can build): `HopDesc` on
      `MachineDesc`, and per hop an outcome enum inside the machine's
      extension -- one case per state the row can produce, a payload state's
      carrying its narrowed struct, every case its effects -- with an `elvis`
      method taking one required label per non-happy state, `rethrows` so a
      handler leaves by throwing (plain when there are no alternatives:
      `rethrows` alone does not compile), and a static member taking the
      action that arrived. States the row cannot produce are `fatalError`
      traps, and no `default:`. Hop members join `member-collision`'s list.
      Proven by `swift-codegen` (a `Connect` machine, a call site that throws
      out of both `elvis` forms, `connect_missing_outcome.swift` refused) and
      `TabularCenterCodegenCheck` (outcome sets, exact signatures, and the
      additive property via `withoutHops`). The payload branch -- a hop from,
      or an outcome in, a payload state -- is emitted but not yet compiled by
      a machine that has one
- [x] Rust, in the revised shape above: the `Hop` trait (`src/hop.rs`), a
      `Hop` impl per forward hop and a `narrow` per machine with paths, both
      from `__tabula_narrow!` at the end of the macro's path walk, `narrow` in
      the machine's color. Tests in `tests/spine.rs` (the hop taken; `Drop`
      and an `IGNORE` handed back as the state reached; a `?` railway), and
      `narrow_unmatched_outcome.rs`: a `match` on the `Err` state that leaves
      a state out does not compile
- [ ] Backward walks (`back`) generate no narrowed members yet: a hop walked
      backwards is `(next, back) -> previous`, and whether it earns a member
      of its own is a question the Compose example should answer
- [ ] The Compose and iced examples (PLAN backlog). They are the acceptance
      test: if the sugar does not read well in a `@Composable` or a `view()`,
      the sugar is wrong, not the app.
