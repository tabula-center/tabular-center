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
// In state Connecting, sending Ready.
val live: S.Live = cells.connectingReady(ctx, state) elvis (
    Failed = { showBanner(it) },
)
```

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

### Open, and worth settling before implementation

- **The `elvis` spelling in each language.** Kotlin's named-argument form is
  `hadilq/happy`'s and reads well. Rust's is `?` over a generated `Result`-alike
  and probably needs no DSL at all. Swift's is a `throws` overload with `try`,
  because `guard case ... else` does not reject a missing case.
- **Whether the effects pump is part of it.** `step` returns a `Step` carrying
  effects, and this returns a state. Something has to run `perform`, and doing
  it inside the generated member would hide an effect execution inside what
  looks like a state transition.

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
- [ ] The narrowed calling surface: one member per hop, per the section above.
      The two open questions there are decisions, not implementation.
- [ ] The Compose and iced examples (PLAN backlog). They are the acceptance
      test: if the sugar does not read well in a `@Composable` or a `view()`,
      the sugar is wrong, not the app.
