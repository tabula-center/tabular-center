# Happy paths

**Status: design. Nothing implements this yet.**

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

- **`tabula::path-broken` becomes precise.** It checks *that* cell rather than
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

An even number of elements, or two states adjacent, is `tabula::path-broken`:
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

Provisional, and normative once implemented. Each needs a section in
`spec/diagnostics.md`, a row in `spec/diagnostics-coverage.md`, and a UI test
per PLAN line 809.

| code | when |
| --- | --- |
| `tabula::path-broken` | a hop names a cell the matrix does not have, or the elements do not alternate state-action-state |
| `tabula::path-unterminated` | a path does not reach a state with no outgoing transition |
| `tabula::path-unknown-state` | a `@Path` names a state the machine does not declare |
| `tabula::path-duplicate` | two paths share a name |

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

## Diagnostics are compile-time, not lints

The four `path-*` codes join the nine existing compile-time diagnostics
(`row-arity`, `unknown-state` and the rest) rather than the seven runtime
lints, because a broken spine is rejected by `buildDesc` before a table exists.

That is a much smaller surface than the first revision assumed: compile-fail
fixtures in `rust/tabula/tests/compile_fail/`,
`kotlin/ksp/compile-fail/fixtures/` and `swift/macros/fixtures/`, following the
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
- [ ] Alternate states and actions, per the decision above. Touches `RawPath`,
      both validations, both declaration surfaces and the eight fixtures --
      cheap now, expensive once examples exist.
- [ ] Derived defaults: a `HANDLE` named by a hop becomes a `GO` to that hop's
      next state. The additive test is that a spine-derived machine and the
      longhand one produce byte-identical `TABLE`, `.grid`, `.lint`, `.cov`
      and `.mmd`.
- [ ] The four lints above, with fixtures.
- [ ] Defaults derived from the spine — the half that motivated the feature, and
      the half that cannot be designed until the two above are settled.
- [ ] The narrowed calling surface: one member per hop, per the section above.
      The two open questions there are decisions, not implementation.
- [ ] The Compose and iced examples (PLAN backlog). They are the acceptance
      test: if the sugar does not read well in a `@Composable` or a `view()`,
      the sugar is wrong, not the app.
