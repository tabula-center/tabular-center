# tabular-center — Architecture

A state machine library whose declaration *is* the transition matrix, and whose
completeness is enforced by the compiler rather than by convention.

Three implementations — Rust, Kotlin, Swift — sharing one conceptual model, one
conformance suite, and one repository.

---

## 1. The one guarantee

> **Every cell of the state × action matrix is a required member.
> An incomplete machine does not compile.**

That is the entire value proposition. Everything else in this document is
ergonomics layered on top of it.

Note what this guarantee is *not* built on:

- Not on exhaustive pattern matching. Pattern matchers are defeated by `else`,
  `default`, `_`, and guard clauses. In Kotlin nothing stops a developer writing
  `else -> ignore()`, so a guarantee resting on `when` exhaustiveness is a
  guarantee resting on code review.
- Not on function purity. Kotlin and Swift do not enforce purity at the language
  level, so any claim built on it is broken by a single `println`. We do not
  claim it.
- Not on runtime validation. A machine with a hole must fail at build time, in
  CI, on the developer's machine, before anything runs.

Instead it rests on the oldest and most boring mechanism in every one of these
languages: *you declared an abstract member and did not implement it.* That
error is produced by `rustc`, `kotlinc`, and `swiftc` themselves, not by our
code generator, which means it survives even if someone bypasses our generator
entirely.

### The two enforcement layers

| Layer | Produced by | Catches |
|---|---|---|
| 1. Matrix well-formedness | tabular-center generator | missing cell, duplicate cell, bad row arity, unknown state/action, unconstructible `GO` target, illegal delegation |
| 2. Member implementation | language compiler | a declared `HANDLE` cell with no body |

Layer 1 gives good diagnostics. Layer 2 gives the actual guarantee.

---

## 2. Vocabulary

Four types define a machine. Three are yours; one is ours.

| Name | Meaning | Shape |
|---|---|---|
| `S` | State — where the machine is | closed sum type |
| `A` | Action — what happened | closed sum type |
| `F` | Effect — what should be done about it (optional) | closed sum type, or `Never` |
| `Step<S, F>` | The outcome of one cell | library type |

`Step` has exactly three constructors:

```
Step.go(next: S, effects: [F])   // transition, optionally emitting effects
Step.stay(effects: [F])          // handled, no transition, optionally emitting
Step.ignored()                   // this pair is meaningless; nothing happened
```

`ignored()` and `stay([])` are behaviourally identical and deliberately
distinct in the source. `ignored` means *the developer asserts this action is
not applicable in this state.* `stay` means *the developer handled it and chose
not to move.* The introspection layer reports them differently, and the
reachability linter treats them differently.

### Cell kinds

A cell is one entry in the matrix. There are six kinds, and the split matters:
three are *static* (fully resolved by the generator, no developer code) and
three are *dynamic* or *structural*.

| Kind | Static? | Meaning |
|---|---|---|
| `IGNORE` | yes | no-op. Action not applicable in this state. |
| `GO(target, emit: [...])` | yes | unconditional transition. Target must be statically constructible. |
| `EMIT(...)` | yes | stay in state, emit the listed effects. |
| `HANDLE` | no | generates a required member; developer writes the body. |
| `DELEGATE(child)` | no | forward to a composed child machine (§8). |
| `UNREACHABLE` | no | developer asserts this pair cannot occur; generates a trap. |

> **Correction (Phase 2).** An earlier draft of this document said `UNREACHABLE`
> both generates a required member and compiles to a trap. Those conflict.
> Writing `UNREACHABLE` *is* the developer's statement of intent, so it
> produces a trap and **no** member. It still counts in the coverage report.

The design intent of the static kinds is that the boring 60–70% of a large
matrix — the cells that are just "not applicable here" — cost one word each and
generate no members. `HANDLE` is reserved for cells that genuinely need logic.
This is what makes an N×M matrix survivable at N=8, M=12.

`UNREACHABLE` compiles to `unreachable!()` / `preconditionFailure()` /
`error("unreachable")`. It is a load-bearing declaration, not a shortcut: it
says *if this fires, the surrounding system has a bug.* The generator counts
`UNREACHABLE` cells and surfaces the count in build output, because a machine
with many of them is usually a machine that wants splitting.

**`Step` is a value, and composes.** A cell's result -- outcome plus ordered
effects -- is a Writer around an Option with two empty cases, so it has a
lawful `map`, monadic chain and applicative `zip` (spec/cells.md 6). The empty
cases short-circuit because there is no target inside them to pass on, and
because a cell that stayed or ignored has decided; they stay distinct through
composition, for the reasons above. `Ignored` absorbs -- a composed decision
that is "not applicable" anywhere is not applicable as a whole -- because an
ignored step has no effects, and the alternative would build one that does.
The applicative is derived from the chain, so the two cannot disagree. This is
the one place the library offers combinators, and it is deliberately the
smallest set that lets a `HANDLE` cell be written from parts.

---

## 3. The matrix

The declaration is *data describing a table*, not code. The generator turns it
into dispatch. The developer never writes the dispatch and therefore never has
the opportunity to write `else`.

Conceptually:

```
             Start          Tick            Cancel
Idle      [  HANDLE,        IGNORE,         IGNORE                    ]
Running   [  IGNORE,        HANDLE,         GO(Idle, emit=[StopClock])]
Done      [  GO(Running),   IGNORE,         IGNORE                    ]
```

Rows are states. Columns are actions. Column order is declared once, in the
`actions` list, and every row must match it positionally. This is deliberate:
positional rows are what make the declaration *look* like a matrix, which was
the original design goal. Named cells were considered and rejected — they read
as a config file, not a table, and they lose the visual scan that makes a hole
obvious to a human reviewer before the compiler ever runs.

### Row arity

A row with the wrong number of cells is a generator error, reported with the
expected header:

```
error[tabular-center::row-arity]: row `Running` has 2 cells, expected 3
  expected columns: Start, Tick, Cancel
  --> Timer.kt:14
```

---

## 4. Totality by required member

The generator emits, per machine:

1. **A cell surface** — one required member per `HANDLE` / `DELEGATE` /
   `UNREACHABLE` cell. (Static cells generate no member.)
2. **A dispatcher** — the `match` / `when` / `switch` over `(S, A)`, with no
   wildcard arm, calling into the cell surface.
3. **A table constant** — the matrix as inert data, for introspection (§10).

The developer implements the cell surface. Nothing else.

Because the generator owns the dispatcher, two properties follow that are
otherwise unavailable:

**Cells receive narrowed types.** The dispatcher has already matched, so it
already knows which variant it holds. It passes the concrete type down:

```
runningTick(state: Running, action: Tick) -> Step
```

Not `(S, A)` followed by a re-bind. No `is` check, no
`guard case .running(let n) = state else { preconditionFailure() }`, no
`if let`. At one or two cells this is a nicety; at forty it is the difference
between a usable library and an unusable one, and it is not writable by hand at
scale.

**Payload-carrying states cost nothing.** In a hand-written design, payloads
degrade or destroy exhaustiveness checking — Swift frequently demands a
`default:` on tuples of payload-carrying enums, which silently voids the whole
premise. Here, coverage comes from member counting, which is indifferent to
payloads. There is no "strict mode / rich mode" fork in this design; there is
one mode, and it supports payloads.

---

## 5. Color by prototype

The library never enumerates colors. It never has an `enum Color`, a
`colors = [...]` parameter, or a fixed list of supported effect systems. It
copies.

The developer declares **one prototype signature** named `handle`. The
generator reads its modifiers, attributes, receivers, and effect specifiers, and
stamps them verbatim onto every generated cell member and onto the dispatcher.

```kotlin
context(clock: Clock)
suspend fun handle(state: S, action: A): Step<S>
```

becomes

```kotlin
context(clock: Clock) abstract suspend fun idleStart(state: S.Idle, action: A.Start): Step<S>
context(clock: Clock) abstract suspend fun runningTick(state: S.Running, action: A.Tick): Step<S>
context(clock: Clock) suspend fun step(s: S, a: A): Step<S> = when (s) { /* … */ }
```

This handles colors we would never have thought to enumerate: `@Composable`,
extension and context receivers, `@RestrictsSuspension`, `unsafe`, `const`,
`extern "C"`, `@MainActor`, `throws`, `reasync` if it ever ships, and whatever
arrives in a compiler version published after this library stops being
maintained. The prototype is the extension point.

### What is captured, per language

| Language | Captured from the prototype |
|---|---|
| Rust | leading tokens before `fn`: `async`, `unsafe`, `const`, `extern "C"`; plus `where` clauses and generic params |
| Kotlin | `suspend`, annotations (`@Composable`, `@RestrictsSuspension`, custom plugin annotations), context parameters, extension receiver, visibility |
| Swift | effect specifiers `async` / `throws` / `async throws`, attributes `@MainActor`, `@Sendable`, isolation clauses |

> **Status (Rust).** `prototype async fn handle;` is implemented, as colored
> library traits rather than copied modifiers: Rust's cell surface is the
> library trait `Handle`, with no generated declaration for a color to land on,
> so an async machine requires `AsyncHandle` / `AsyncPerform` instead. That
> enumerates colors, which this section rejects in general; in Rust the list is
> the language's, since `async` is the only color a trait method can carry on
> stable. Any other prototype is `tabular-center::unsupported-color`. An async parent
> delegates to a child of either color by awaiting it -- `Step` is
> `IntoFuture` -- and a plain parent over an async child is refused by rustc.

> **Status.** The KSP processor captures `suspend`, annotations and the
> extension receiver. Visibility is taken from the annotated declaration rather
> than the prototype (the generated surface cannot be more visible than the
> types it names). Context parameters are not read: they need Kotlin 2.2+ and
> the toolchain is pinned to 2.1.20, so the `context(clock: Clock)` example
> above is the design, not yet something the processor produces (PLAN, 4c-old).

### The rule that has to be stated loudly

> **A color cannot be passed as a parameter. It must be on the cell's own
> declaration.**

Handing a `suspend () -> T` into an uncolored cell does not work — the cell
still cannot call it. This is exactly why the prototype drives code generation
rather than being a runtime argument. If this were solvable at runtime, the
library would not need a code generator at all.

### The cost, stated plainly

`step` is colored, so the driver is colored, so **one matrix yields one
color**. A machine that must exist as both blocking and suspending is declared
twice, with two generated names:

```kotlin
@Machine(name = "TimerMachine")         // prototype: fun handle(...)
@Machine(name = "TimerSuspendMachine")  // prototype: suspend fun handle(...)
```

This is a real regression from a scheme with a fixed color enum, where one
declaration could stamp out N variants. It is the price of open-ended colors,
and it is the right trade: fixed enums are wrong the moment the language ships
something new, and they were already wrong for context parameters.

### `@Composable` transitions

`@Composable` is accepted as a prototype color, and the generator emits a
warning when it is used for *transitions* specifically. The reason survives the
rejection of purity as a guarantee: the Compose runtime may skip, restart,
reorder, or discard a composition. A transition mutating context during
composition is a correctness bug against the runtime's contract, not a style
violation.

The supported use is **rendering cells** — a second, optional surface
(`S -> UI`) declared with its own prototype, where `@Composable` is exactly
right. See §9.

---

## 6. Payloads

Payload handling is where generated dispatch pays for itself. Five rules.

### R1 — The matrix is over variants; values branch inside cells

A row is `Running`, never `Running(since = 5)`. Guards, thresholds, and
value-dependent branching live in the cell body.

This is the invariant that keeps the table rectangular. It also means **adding
a field to a state's payload changes zero cells** — the matrix is stable under
payload evolution, which is the single biggest source of churn in hand-written
state machines.

### R2 — Cells receive narrowed types, never the union

Covered in §4. Restated here because it is a payload rule: the payload arrives
already destructured, typed, and non-optional.

### R3 — `GO` targets must be statically constructible

A `GO` cell is resolved entirely by the generator, so its target must be
buildable without developer code: either payload-free, or a literal.

Prefer **enforcement by construction** over checking, where the language allows
it. Rust's generated dispatcher binds its parameters under `__tabula_`-prefixed
names, so `ctx`, `state`, `action`, and `cells` are simply not in scope inside a
`GO!` expression; a target reaching for runtime data fails to resolve. This
cannot be circumvented and costs no implementation. Emit the explicit
`tabular-center::go-target` diagnostic only where construction cannot do the job.

```
GO(Idle)                          // ok — payload-free
GO(Running, since = 0)            // ok — literal
GO(Running)                       // error — `since: Long` cannot be derived
```

```
error[tabular-center::go-target]: cell (Done, Start) uses GO to `Running`,
  which requires `since: Long` that cannot be derived from a literal.
  Use HANDLE.
  --> Timer.kt:16
```

Without this rule, `GO` quietly becomes the lazy option and developers stuff
zero values into payloads to avoid writing a cell. The error text names the
remedy explicitly.

### R4 — Payload is state-local; Context is cross-state

| Data | Lives in |
|---|---|
| exists only while in this state | the state's payload |
| outlives transitions | Context, passed to `step` |

The generator emits a **hoist warning** when the same name-and-type pair appears
in three or more payloads:

```
warning[tabular-center::payload-hoist]: `retryCount: Int` appears in payloads of
  `Connecting`, `Backoff`, `Reconnecting`. Consider hoisting to Context.
```

Cheap to implement, and it heads off the most common way these machines rot.

### R5 — Nested sealed hierarchies do not auto-flatten

If `Running` is itself a sealed hierarchy, the row is `Running`: one row, one
cell per action. Opt in to flattening explicitly:

```
EXPAND(Running)   // generates one sub-row per direct subvariant of Running
```

Defaulting to flatten would let the matrix explode without the declaration
visibly growing, which is precisely the failure mode this library exists to
prevent. `EXPAND` is one level deep; nest it if you mean it.

> **Status.** Designed, specified (`spec/cells.md` section 3), and implemented
> in no language. Until it is, a nested sealed hierarchy is one row, which is
> the non-flattening default this rule asks for anyway.

---

## 7. Effects

Effects are **optional**. Their original justification was enforcing purity, and
we have dropped that claim. What remains is a real but narrower benefit: effects
that appear in the table are visible in the diagram export and testable without
running the side effect.

**Effects are declared like states and actions, and generated the same way:**

```
effects Effect { StartClock, StopClock { reason: u32 } }
```

This is not cosmetic. The generator can only emit one required member per
variant if it *knows* the variants, and naming a hand-written enum leaves it
with nothing to iterate. Everything below follows from that one decision.

An empty variant list (`effects Effect { }`) yields an uninhabited enum: a
machine with no effects, cells doing IO directly. A fully supported mode, not a
degraded one.

Machines that do declare effects get the same totality treatment, with its own
prototype:

```kotlin
context(clock: Clock)
suspend fun perform(effect: F): A?     // effect handler prototype
```

generates:

```kotlin
context(clock: Clock) abstract suspend fun startClock(effect: F.StartClock): A?
context(clock: Clock) abstract suspend fun stopClock(effect: F.StopClock): A?
```

One required member per effect variant, with narrowed payloads, returning an
optional follow-up action. **Add an effect variant and every handler stops
compiling.** No other library in this space offers total effect handling, and it
falls out of the same mechanism for free.

The follow-up action is returned as **data**. The driver enqueues it; a handler
is handed no way back into `step`, which is what makes re-entrancy impossible
rather than merely discouraged (§9).

---

## 8. Composition

Three named operations. "Composable" is too vague to design against.

| Operation | Relationship | Lens shape |
|---|---|---|
| **Nest** (product) | child state is a *field* of parent state | `get: P -> C`, `set: (P, C) -> P` |
| **Alternate** (sum) | child state *is* one case of parent state | `get: P -> C?`, `embed: C -> P` |
| **Translate** (relabel) | reuse a generic machine under a domain vocabulary | paired maps both directions |

All three are expressed with **closure pairs, not key paths**. Swift key paths
carry real runtime cost and Swift has no native case key paths; closure pairs
are faster, work identically in all three languages, and add no dependency.

### The `DELEGATE` cell

Composition enters the matrix as a cell kind, which means it is written out
explicitly, one cell at a time:

```
Retrying  => [ IGNORE, DELEGATE(Retry), GO(Idle) ]
```

Two rules the generator enforces:

**Coverage is never inherited silently.** The parent row still lists every
column. You can see at a glance which cells delegate. A parent does not get to
say "everything else goes to the child."

**Color flows one way.** A colorless child composes into a colored parent. A
colored child into a colorless parent is a build error — from the language, not
from tabular-center. Every generator puts the parent's color on the call into the
child, so rustc, kotlinc and swiftc each refuse it by construction, and
`tabular-center::color-mismatch` is reserved and emitted by nobody (decided September
2026; `spec/diagnostics.md` lists the three fixtures). The message a generator
would otherwise print:

```
error[tabular-center::color-mismatch]: machine `Timer` (prototype: `fun handle`)
  delegates to `Retry` (prototype: `suspend fun handle`).
  A suspending child cannot be driven from a non-suspending parent.
```

### Derived lenses

When a state's payload type *is* the child's state type, the lens is the payload
accessor and the generator derives it — no registration:

```kotlin
data class Retrying(val child: RetryS) : S
@Row(Retrying, [IGNORE, DELEGATE(Retry), GO(Idle)])
```

When shapes do not line up, register an explicit closure pair on the machine.

### The composition property

> Scoping a total child into a total parent yields a total parent, and the
> compiler proves it by the same mechanism as everything else: unimplemented
> required members.

Now verified in both languages, with a compile-fail fixture each. The mechanism
differs only in spelling:

| | carries the child's surface | a child hole reads as |
|---|---|---|
| Rust | `where C: child::Cells` | `the trait bound Impl: Handle<Retry, Waiting, Elapsed> is not satisfied` |
| Kotlin | `interface Cells : retry.Cells` | `class 'ChildHole' is not abstract and does not implement abstract member: fun waitingElapsed(...)` |

**Interfaces are Kotlin's trait bounds.** That is why the cell surface is an
interface rather than a set of abstract members on a class — a class can only
extend one parent, so abstract members would have capped composition at one
child.

This belongs at the top of the README. It is the actual differentiator over
every existing library surveyed.

---

## 9. Runtime: reentrancy, drivers, rendering

### Reentrancy is real and is handled by generation, not documentation

Colored cells mean events can arrive mid-transition. Rather than warn about it:

- `step` is **non-reentrant by contract** and documented as such.
- The generated driver holds a **mailbox** and enqueues rather than recursing.
- Effect-produced follow-up actions go through the same mailbox — they never
  re-enter `step` directly.
- Rust gets serialization free from `&mut self`; Kotlin and Swift get an
  explicit queue.

### Drivers

Drivers are thin and per-color. They are *generated*, because the prototype
determines their color too.

| Language | Generated driver |
|---|---|
| Rust | `Machine<C>` owning state + mailbox; `run` colored by prototype |
| Kotlin | plain `Driver` class; `SuspendDriver` takes `suspend () -> A` as source (no `kotlinx.coroutines` dependency) |
| Swift | `Store` (sync), `actor AsyncStore` (structured concurrency), `@MainActor ObservableStore` (conforms to `Observable` by hand; Darwin only) |

Kotlin's suspend driver depends on the `suspend` keyword only — a stdlib
feature — not on `kotlinx.coroutines`. Keeping the event source as
`suspend () -> A` rather than `Flow<A>` preserves the zero-runtime-dependency
rule.

### Rendering surface (optional)

A second, independent prototype for view derivation:

```kotlin
@Composable
fun render(state: S): Unit          // rendering prototype
```

One required member per state, narrowed payloads, `@Composable` where it
belongs. This is the supported home for Compose, SwiftUI, and any other
retained-mode UI, and it keeps `@Composable` out of the transition path.

SwiftUI's views are opaque, and a protocol requirement cannot return
`some View`, so Swift's renderers take SwiftUI's own shape -- the one `View`
uses for `body`: an associated type per state under `@ViewBuilder`, and a
generic `render` that returns `some View`, the builder turning its `switch`
into one view:

```swift
protocol TimerRenders {
    associatedtype IdleBody: View
    @ViewBuilder func renderIdle() -> IdleBody
    associatedtype RunningBody: View
    @ViewBuilder func renderRunning(_ state: Timer.Running) -> RunningBody
    // ...
}
```

The builder and the protocol are names to the generator, so the checks prove
this shape on Linux with a stand-in builder; SwiftUI is not there to use.

---

## 10. Introspection

Because the matrix exists as inert data (`TABLE`), these come free:

- **Mermaid / DOT export** — a pure function of `TABLE`, usable at
  build time or runtime. All three formats render from **one edge walk per
  language**, in row-major matrix order, so a machine draws the same way
  whichever format you ask for. That is not tidiness: the three renderers were
  independent once, and Rust's mermaid ordered its edges differently from
  Kotlin's and Swift's for as long as nobody looked. `IGNORE` and `UNREACHABLE`
  draw nothing; `HANDLE` and `DELEGATE` draw annotated self-loops rather than
  invented edges, because their target is not knowable at build time.
- **Reachability check** — generated test asserting every state is reachable
  from the initial state and every `HANDLE` cell is reachable. Emits a warning,
  not an error, since unreachable-by-construction cells are legitimate during
  refactors.
- **Coverage report** — counts by cell kind. A machine that is 90% `IGNORE`
  probably wants splitting; a machine with many `UNREACHABLE` cells probably has
  a modelling error. Surfaced in build output.
- **Matrix rendering** — `TABLE` rendered as an aligned grid, the
  conformance format's view of a machine (§12). Not committed as a golden:
  each implementation renders its own at check time and `renderings-agree`
  diffs them, and `table-diff` renders any machine's grid for review.

### Payload-free fast path

If every state and action in a machine is payload-free, the generator emits
`[[Cell; M]; N]` and dispatches by discriminant index rather than by match. This
keeps the Rust `no_std` path allocation-free and makes `TABLE` a true `const`.

---

## 11. Per-language design

### 11.0 A language-forced divergence: how cells are named

> **Update (Phases 4 and 6).** This divergence is wider than it first looked,
> and it runs in one direction: *Rust reaches for generics wherever
> `macro_rules!` cannot build an identifier; Kotlin names things.* It shows up
> twice — the cell surface below, and the `DELEGATE` cell (§8), where Rust's
> `Delegate<M, SV, AV, CM>` cannot be transcribed at all, because a Kotlin class
> may implement a generic interface at only **one** type argument. Kotlin emits
> one named member per delegate cell instead, which is the better form anyway.
> Expect the same shape of difference in Swift, and keep `spec/conformance`
> comparing behaviour rather than source.

**`macro_rules!` cannot concatenate identifiers.** There is no stable
`concat_idents!`, so the Rust macro cannot synthesize a member named
`idle_start` from the state `Idle` and the action `Start`.

Rust therefore expresses the cell surface as **trait bounds**:

```rust
impl Handle<Timer, Idle, Start> for MyTimer { /* ... */ }
```

A missing cell reads `the trait bound MyTimer: Handle<Timer, Idle, Start> is
not satisfied`, naming the exact hole. Kotlin and Swift keep **named members**,
because KSP and SwiftSyntax *can* build identifiers.

The rejected alternative was making the developer write the member name into
every `HANDLE` cell (`HANDLE(idle_start)`). That puts noise into the matrix —
the one artifact this library exists to keep readable — to buy uniformity
across languages that nobody reads side by side.

The guarantee is identical in both spellings. What this costs is that
`spec/conformance` must compare **behaviour**, never generated source.

### 11.1 Rust — `macro_rules!`, zero build dependencies

`macro_rules!` is part of the language. No `syn`, no `quote`, no proc-macro
crate, no build-graph impact. Rust is the only one of the three where the ideal
syntax is achievable for free, which is why it leads.

```rust
transition_matrix! {
    machine Timer;
    context Ctx;
    prototype async fn handle;

    states  { Idle, Running(u32), Done }
    actions { Start, Tick, Cancel }
    effects Fx;

    //            Start                       Tick        Cancel
    Idle    => [  HANDLE,                     IGNORE,     IGNORE                  ];
    Running => [  IGNORE,                     HANDLE,     GO!(Idle, Fx::Stop)     ];
    Done    => [  GO!(Running(0), Fx::Start), IGNORE,     IGNORE                  ];
}
```

Expands to:

```rust
pub trait TimerCells {
    async fn idle_start(&mut self, s: Idle, a: Start) -> Step<State, Fx>;
    async fn running_tick(&mut self, s: Running, a: Tick) -> Step<State, Fx>;
}

pub async fn step<C: TimerCells>(c: &mut C, s: State, a: Action) -> Step<State, Fx> {
    match (s, a) {
        (State::Idle,      Action::Start)  => c.idle_start(Idle, Start).await,
        (State::Idle,      Action::Tick)   => Step::ignored(),
        (State::Idle,      Action::Cancel) => Step::ignored(),
        (State::Running(n), Action::Start) => Step::ignored(),
        (State::Running(n), Action::Tick)  => c.running_tick(Running(n), Tick).await,
        (State::Running(n), Action::Cancel)=> Step::go(State::Idle, [Fx::Stop]),
        (State::Done,      Action::Start)  => Step::go(State::Running(0), [Fx::Start]),
        (State::Done,      Action::Tick)   => Step::ignored(),
        (State::Done,      Action::Cancel) => Step::ignored(),
    }
    // no wildcard arm
}

pub const TIMER_TABLE: [[Cell; 3]; 3] = [ /* … */ ];
```

**Two independent guarantees stack.** The macro's repetition pattern rejects
wrong row arity; and the expansion contains no wildcard arm, so a missing *row*
is caught by `rustc`'s own exhaustiveness checker rather than by our macro. The
second is free and more trustworthy than anything we could write.

Color was designed as a `$($color:tt)*` capture splatted onto each generated
`fn`. *As built it is not splatted* -- the cell surface is the library trait
`Handle`, with no generated declaration for a color to land on -- so
`prototype async fn handle;` selects `AsyncHandle` / `AsyncPerform` and gates
the `.await` at each call into a cell. See §5's Rust status note. Likewise the
`pub trait TimerCells` in the expansion above is the design's shape; the
built surface is one `Handle` bound per cell (§11.0).

AFIT is not `dyn`-compatible; irrelevant, since we monomorphize. A boxed variant
sits behind a `dyn` feature flag.

**Two `macro_rules!` hazards, recorded because neither is obvious from the
error message.**

*Nesting depth.* `macro_rules!` cannot iterate two repetitions of different
depth in lockstep. The action list is at depth 0 and each row's cells at depth
2, so rows are munched one at a time (`__tabula_arms!`) to flatten both to
depth 0 before generating a row's inner match.

*Hygiene.* An identifier minted inside a helper macro is a **different**
identifier from one minted in the caller, even spelled the same. Binding names
are threaded as `bind=[...]` ident arguments so they keep their syntax context.
The resulting error — `cannot find value __tabula_state in this scope`, pointing
at the macro invocation — does not suggest the cause.

**Diagnostics must win the race against incidental errors.** A missing row also
produces an array-length mismatch on `TABLE`, and in Rust type errors abort
before const evaluation, so a `const` assertion never gets to speak. The
missing-row check is a structural lockstep muncher emitting `compile_error!`
during expansion. Expect the same shape of problem in every language: the
useful diagnostic has to be emitted *earlier* than the incidental one.

`no_std` shape: at most one effect per step, or `[Option<F>; K]` with const
generic `K`. Alloc-free, ROM-resident.

Escape hatch: the macro expands to exactly what a competent human would write.
That is checked, not asserted: `rust-asm-identical` compiles the Timer both
ways -- `transition_matrix!` and the hand-written `tests/reference_timer.rs` --
and requires their optimised dispatch code to be identical instruction for
instruction (`tools/asm-diff`; PLAN, Phase 10).

**How the macro is built** (`src/matrix.rs`), for whoever changes it:

- **Color is one token**, `Plain` or `Async`, threaded through every rule and
  taken apart only where it matters. A captured path cannot be used as a
  trait bound, and a type-level color selector would turn rustc's "`T:
  Handle<..>` is not satisfied" into a message about the selector -- so
  `HANDLE` has one rule per color.
- **Rows are munched, not repeated**: the action list and a row's cells sit
  at different repetition depths, and `macro_rules!` cannot iterate two
  independent repetitions in lockstep. Binding names are threaded as `ident`
  arguments so the helpers stay hygienic.
- **A run of four `IGNORE`s is consumed in one step** (and two, where a run is
  broken): a realistic 8x12 machine is 78% `IGNORE` and blew the default
  recursion limit when the muncher recursed once per cell.
- **Structural checks come first.** Row count against state count is checked
  during expansion, before type-checking: a missing row would otherwise
  surface as an array-length mismatch on `TABLE`, and a `const` assertion
  never runs once a type error aborts. `EMIT!()` with no effects must precede
  the general `EMIT` rule, which matches zero tokens and once swallowed it.
- **Narrowed variant types and `PAYLOADS` are emitted where the payload
  fields are bound**: by the time the rows are walked the field names are
  gone. `PAYLOADS` is a separate const, not a `TABLE` field -- the table is
  the matrix, this is metadata about the states, and adding it broke no
  existing `Table` literal.
- **Paths (spines)** are rewritten before the main walk: each path is paired
  into hops, every state and action checked as it goes, a lookup macro
  defined whose rules *are* the names, and the rows rewritten through it, so
  `@main` sees the spine as if written longhand. Back hops accumulate
  separately because they are not checked alike. `($)` hands a helper a
  literal `$`, which a macro cannot otherwise write in its output.
  `path-duplicate` is left to rustc ("defined multiple times"), as
  `unknown-child` is: both compare names the machine chose, so there is no
  declared list to generate a lookup from.
- **`GO!` cannot reach runtime data** -- the dispatcher's bindings are
  `__tabula_`-prefixed, so rule R3 holds by construction. **`DELEGATE!`** runs
  the child's `step` and folds the result back through the lens; in an async
  parent the child is awaited whatever its color (a plain child's `Step` is
  `IntoFuture`, ready at once). An action outside the child's alphabet is
  `Ignored`, not `Stay`: nothing was handled.
`cargo expand` is a supported auditing path, and `Step`, `Cell`, and the trait
are all usable directly without the macro.

### 11.2 Kotlin — KSP

**KSP cannot rewrite code; it only generates new files.** This is the load-
bearing constraint. "Hiding the `when`" therefore does not mean intercepting a
function the developer wrote — it means the `when` exists *only* in generated
code and the developer never writes a state machine function by hand.

Which is why the matrix lives in annotations: KSP reads declarations, not
function bodies.

```kotlin
@Machine(context = Ctx::class)
@Row(Idle::class,    [HANDLE, IGNORE, IGNORE])
@Row(Running::class, [IGNORE, HANDLE, GO(Idle::class, emit = [StopClock::class])])
@Row(Done::class,    [GO(Running::class, since = 0L, emit = [StartClock::class]), IGNORE, IGNORE])
interface Timer {
    sealed interface S {
        data object Idle : S
        data class  Running(val since: Long) : S
        data object Done : S
    }
    sealed interface A {
        data object Start : A
        data class  Tick(val now: Long) : A
        data object Cancel : A
    }
    sealed interface F {
        data object StartClock : F
        data class  StopClock(val reason: String) : F
    }

    // Prototype — modifiers here are copied to every cell.
    context(clock: Clock)
    suspend fun handle(state: S, action: A): Step<S, F>
}
```

Generated (the design's shape; *as built*, the surface is `interface Cells`
with `step`, `TABLE` and `PAYLOADS` at top level, because a class can extend
one parent and that would cap composition at one child -- §8, and PLAN 4c-old.
Context parameters are not read yet, §5):

```kotlin
abstract class TimerMachine {
    context(clock: Clock) abstract suspend fun idleStart(state: S.Idle, action: A.Start): Step<S, F>
    context(clock: Clock) abstract suspend fun runningTick(state: S.Running, action: A.Tick): Step<S, F>

    context(clock: Clock)
    suspend fun step(s: S, a: A): Step<S, F> = when (s) {
        is S.Idle    -> when (a) {
            is A.Start  -> idleStart(s, a)
            is A.Tick   -> Step.ignored()
            is A.Cancel -> Step.ignored()
        }
        is S.Running -> when (a) {
            is A.Start  -> Step.ignored()
            is A.Tick   -> runningTick(s, a)          // smart-cast to S.Running
            is A.Cancel -> Step.go(S.Idle, listOf(F.StopClock(/* … */)))
        }
        is S.Done    -> when (a) { /* … */ }
    }

    companion object { val TABLE: Array<Array<Cell>> = /* … */ }
}
```

Developer writes only:

```kotlin
class Timer : TimerMachine() {
    context(clock: Clock)
    override suspend fun idleStart(state: S.Idle, action: A.Start) =
        Step.go(S.Running(clock.now()), listOf(F.StartClock))
    // omit runningTick → does not compile
}
```

There is no `when` in the developer's file, so `else` is not a temptation — it
is not available. **Kotlin is no longer the weak leg of this design.** The
guarantee is as strong as Rust's, because both now rest on required-member
implementation rather than on matcher exhaustiveness.

Costs, honestly: KSP is a build dependency (not a runtime one; the generated
code and `tabular-center-core` have zero runtime deps). Incremental builds slow.
IDE resolution of generated symbols is flaky until first build. Nested
annotation matrices are wordy, and ktlint will fight the column alignment —
ship an `.editorconfig` disabling the relevant rules for matrix files
(`[*.tb.kt]`, `spec/matrix-files.md`).

Multiplatform: `tabular-center-core` is a KMP module (`commonMain` only). The KSP
processor is JVM.

### 11.3 Swift — macro

Swift needs a macro for the same reason as Kotlin: without one there is no way
to both hide the `switch` and validate arity.

SwiftSyntax is a **build-time** dependency and does not link into the binary.
The zero-dependency rule is about runtime; this satisfies it. The alternative —
no macro — means hand-written `switch` with `default:` reachable, which forfeits
the guarantee. Take the deal.

```swift
@Machine(context: Ctx.self)
enum Timer {
    enum S { case idle, running(since: Int), done }
    enum A { case start, tick(now: Int), cancel }
    enum F { case startClock, stopClock(reason: String) }

    // Prototype: effect specifiers and attributes are copied to every cell.
    @MainActor static func handle(_ s: S, _ a: A) async throws -> Step<S, F> { .prototype }

    static let matrix: Matrix = [
        //          .start                        .tick     .cancel
        .idle:    [ .handle,                      .ignore,  .ignore                          ],
        .running: [ .ignore,                      .handle,  .go(.idle, [.stopClock("user")]) ],
        .done:    [ .go(.running(since: 0), [.startClock]), .ignore, .ignore                 ],
    ]
}
```

> **Status.** The declaration above is the original design. The settled
> surface is `tabular-center-swift/macros/SURFACE.md` -- one `@Row` per state
> holding an aligned array literal, not a dictionary -- and it is executed:
> `MachineSyntax` parses it on every run. The `@Machine` macro itself waits on
> a SwiftPM that ships `CompilerPluginSupport` (§13); until then
> `TabularCenterCodegen` emits the protocol and `switch` below from a
> `MachineDesc`, and `swift-codegen` compiles the result.

The macro synthesizes a payload-free `Tag` enum for table indexing, validates
the literal's shape at expansion time, and emits:

```swift
protocol TimerCells {
    @MainActor mutating func idleStart(_ s: Timer.Idle, _ a: Timer.Start) async throws -> Step<Timer.S, Timer.F>
    @MainActor mutating func runningTick(_ s: Timer.Running, _ a: Timer.Tick) async throws -> Step<Timer.S, Timer.F>
}
```

plus the exhaustive `switch (state, action)` with payload binding, so
`runningTick` receives its `since: Int` already unwrapped.

Swift's color axes — `async`, `throws`, `@MainActor`, `@Sendable`, isolation —
are all just tokens the macro splices, which is exactly the prototype scheme.

---

## 12. Repository layout

```
tabular-center/
├── flake.nix                    # composes the three language flakes; adds the
├── flake.lock                   #   cross-language checks. One lock for all.
├── nix/
│   ├── context.nix              # combines the language flakes' toolchains
│   ├── shells.nix               # the combined devShell (per-language: re-exported)
│   ├── checks.nix               # the cross-language checks — each calls tools/verify
│   ├── apps.nix                 # nix run .#verify, .#conformance, .#docs
│   └── publish.nix              # release + publish, allowed to touch the network
├── doc/                         # the Pages site: build output, not committed; written by
│                                 #   tools/docs from spec/ and code samples, never by hand
├── justfile                     # thin aliases over tools/verify
├── VERSION                      # single source of truth; every manifest derives
├── ARCHITECTURE.md              # this file
├── PLAN.md
├── README.md  CONTRIBUTING.md  RELEASING.md
│
├── spec/
│   ├── cells.md                 # normative semantics of the six cell kinds
│   ├── diagnostics.md           # normative error codes + message text
│   ├── diagnostics-coverage.md  # which implementation emits which code; checked
│   ├── happy-paths.md           # `@Path` spines: design + status
│   ├── matrix-files.md          # the `*.tb.*` convention
│   ├── tabular-center-fmt.md    # the formatter's contract (tool: tabular-center-fmt/)
│   └── conformance/
│       ├── README.md            # the .tbl and .trace formats
│       ├── <name>.tbl           # ── 11 shared fixtures: timer, toggle, retry,
│       │                         #   nested-delegate, effects-never, dead-column,
│       │                         #   ignore-heavy, unreachable-heavy,
│       │                         #   no-static-entry, no-static-exit,
│       │                         #   payload-hoist ──
│       └── traces/<name>.trace  # (state, action) → expected (state, effects)
│                                 #   .grid/.mmd/.lint/.cov are NOT here: each
│                                 #   implementation renders its own at check
│                                 #   time and `renderings-agree` diffs them
│
├── tabular-center-rust/         # a flake: `nix flake check ./tabular-center-rust`
│   ├── flake.nix  flake.lock    # pins copied from the root's; the root `follows`
│   ├── nix/                     # context (toolchain, vendored example crates),
│   │                             #   checks, shells, apps (.#table-diff)
│   ├── tools/verify             # the Rust steps
│   ├── tools/compile-fail       # diagnostic fixtures; bash, not trybuild
│   ├── Cargo.toml               # workspace
│   ├── tabular-center/          # core + macro_rules! (single crate, no deps)
│   │   ├── src/{lib,step,cell,table,matrix,machine,delegate,driver,hop}.rs
│   │   ├── src/{export,lint}.rs     # alloc-gated
│   │   └── tests/
│   │       ├── reference_timer.rs   # hand-written; the macro's specification
│   │       ├── timer_matrix.rs      # same machine via the macro; parity tests
│   │       ├── scale.rs             # the measured 8×12 machine
│   │       └── compile_fail/        # one fixture per diagnostic
│   ├── tabular-center-conformance/  # runs spec/conformance; hosts bin/table-diff
│   │                             #   (whose renderer is in the lib, so it is
│   │                             #   testable)
│   └── examples/                # its own cargo workspace, outside the one above:
│                                 #   01-04 on the MSRV, 05-iced its own package,
│                                 #   lock and rust-toolchain.toml (stable)
│
├── tabular-center-kotlin/       # a flake; built by kotlinc directly — no Gradle
│   ├── flake.nix  flake.lock
│   ├── nix/                     # context (pinned kotlinc, JDK), checks, shells,
│   │                             #   apps (.#gradle-lock), and the Maven set for
│   │                             #   KSP: gradle-lock.json + gradle-repo.nix
│   ├── tools/verify             # the Kotlin steps
│   ├── tools/gradle-lock        # writes nix/gradle-lock.json (network)
│   ├── core/center/tabula/         # Step, Cell, Table, Export, Lint, Driver
│   ├── annotations/center/tabula/  # @Machine, @Row, @Path, cell markers
│   ├── testing/center/tabula/testing/
│   ├── codegen/                 # MachineDesc -> String, + support/ and compile_fail/
│   ├── ksp/                     # JVM processor — Gradle, offline via nix/gradle-lock.json
│   ├── test/                    # reference machine + harness
│   ├── conformance/
│   ├── compile_fail/
│   └── examples/                # 01-05 by kotlinc; 06-generated and 07-compose
│                                 #   by Gradle (KSP), offline from nix/gradle-lock.json
│
├── tabular-center-swift/         # a flake
│   ├── flake.nix  flake.lock    # the only flake with `nixpkgs-swift`
│   ├── nix/                     # context (the Swift toolchain and its runtime
│   │                             #   path), checks, shells, apps (.#swift-lock),
│   │                             #   swift-lock.json + swift-deps.nix (swift-syntax
│   │                             #   offline), swiftpm-plugin-support.nix
│   ├── tools/verify             # the Swift steps
│   ├── tools/swift-lock         # writes nix/swift-lock.json (network)
│   ├── tools/swift-probe        # toolchain triage for the Linux Swift path
│   ├── Package.swift
│   ├── Sources/TabularCenter/              # core: Step, Cell, Table, Export, Lint,
│   │                                       #   Driver, AsyncDriver, Store, AsyncStore
│   ├── Sources/TabularCenterTesting/       # the .tbl fixture harness, a separate product
│   ├── Sources/TabularCenterCodegen/       # the emitter; no SwiftSyntax, so it builds offline
│   ├── Sources/TabularCenterCodegenCheck/  # emits, then compiles against codegen-support/
│   ├── Sources/TabularCenterCheck/         # reference machine + harness (no XCTest available)
│   ├── Sources/TabularCenterConformance/
│   ├── codegen-support/         # what the emitted source is compiled against:
│   │                             #   types, complete impls, and refusals
│   ├── compile_fail/
│   ├── macros/                  # separate package: the only one linking
│   │                             #   swift-syntax. MachineSyntax + fixtures/;
│   │                             #   the .macro target waits in pending/
│   └── examples/                # separate package, `.package(path: "..")`
│
├── tabular-center-fmt/          # aligns `.tb.` matrices; the format's, not a
│                                 #   language's. Rust, no deps, its own flake
│                                 #   (spec/tabular-center-fmt.md)
└── tools/
    ├── verify                   # the single definition of green: runs the
    │                             #   cross-language steps, hands the rest to
    │                             #   tabular-center-*/tools/verify by name
    ├── deps                     # dependencies.toml: sync it into every manifest, check none drifted
    ├── upstream                 # newer upstream versions; --update applies them (network)
    ├── no-comments              # the Cleanness rule (§15), over the file types migrated
    └── docs                     # writes doc/, the Pages site: build output, deployed
                                  #   by .github/workflows/pages.yml; `tools/verify
                                  #   docs` checks every sample and anchor resolves
```

Three things about this layout are decisions rather than accidents.

**`tools/verify` is the only definition of green.** `nix flake check` runs its
steps in a sandbox and CI runs the flake, so all three paths execute the same
commands. A new check goes in `tools/verify`, never directly into the workflow
-- in the root script if it reads more than one implementation, and in the
owning language's `tabular-center-<lang>/tools/verify` otherwise. The root
script finds a language's steps by asking its script (`--list`), so a step is
declared in one place and `./tools/verify <step>` reaches every one of them.

**Each implementation is a flake of its own.** A language directory carries
its toolchain, its checks and its locks, so it can be checked, entered and
changed without the other two in the closure. The root flake composes the
three, merges their checks under the names they always had, and adds only what
no single language can check -- `renderings-agree` above all, which takes the
three toolchains from the language flakes' `legacyPackages.<system>.toolchain`
rather than naming them again. `spec/` stays at the root because all three
read it -- it is the contract they are held to -- and it is the only thing
outside its own directory a language needs. The language flakes reach it
through `self.sourceInfo`, which is the whole checkout for a flake found in a
git subdirectory and for a relative `path:` input (Nix 2.26 or later), and
each language check is handed only its own directory, `spec/` and
`.editorconfig`: a step that reached into another language would fail, so the
independence is checked rather than claimed.

**The Kotlin library has no build system.** `kotlinc` is driven directly, and
that is not a workaround to be tidied up later: compiling each artifact against
only its declared classpath is what enforces the zero-runtime-dependency rule
by construction rather than by a dependency report. Gradle exists only where
KSP needs it — `tabular-center-kotlin/ksp` and `tabular-center-kotlin/examples/06-generated` —
and resolves offline from `tabular-center-kotlin/nix/gradle-lock.json`. The
Kotlin flake pins `kotlinc` to the same 2.1.20 those builds name, so a nixpkgs
bump cannot move the compiler whose messages the compile-fail fixtures match.

**Examples sit outside every workspace**, though inside their language's
directory: each set is its own cargo workspace, its own `kotlinc` or Gradle
build, its own SwiftPM package. They depend on the library by path, the way a
user would. That is the only place the public API is exercised from
outside, and it is where `Driver::run` was found not to compile for any
realistic caller.

### Why a shared `spec/`

The three implementations will drift unless something forces them not to. The
conformance format describes a machine declaratively; each language's harness
generates a machine from it and replays the trace files. A semantic difference
between Rust and Kotlin becomes a red CI check rather than a bug report two
years later.

The diagnostics spec is normative for the same reason: `tabular-center::row-arity`
should produce recognizably the same message in all three.

---

## 13. `flake.nix`

Five flakes: one per implementation, each pinning its own toolchain, one for
the `.tb.` formatter (`tabular-center-fmt/`), and the root, which composes
them. The root provides the per-language dev shells (the
language flakes' own, re-exported) and a combined one, and its `nix flake check`
runs every implementation's suite plus the cross-language checks.

```
nix develop                            # everything
nix develop .#rust                     # rustc + cargo + clippy + rust-analyzer
nix develop .#kotlin                   # JDK 21 + kotlinc 2.1.20 (pinned) + Gradle + ktlint
nix develop .#swift                    # Swift 5.10 (Linux and Darwin; checks run on both)
nix flake check                        # all three + the cross-language checks
nix flake check ./tabular-center-rust  # one language alone (from a git checkout)
nix run .#conformance                  # cross-language conformance runner
```

The language flakes are relative `path:` inputs of the root, and every input
they share with it -- `nixpkgs`, `flake-utils`, `rust-overlay`,
`nixpkgs-swift` -- `follows` the root's, so the composed flake has one of each
and one `flake.lock` pins them. Each language flake also has a `flake.lock` of
its own, for being checked alone; it holds the same revisions as the root's,
and a bump is made in all five together.

**Swift is checked on Linux, not merely available there.** That was not always
true and the reasons it was not are worth keeping: the then-pinned nixpkgs 25.05
shipped Swift 5.8, below the 5.9 macros require, and its SwiftPM is sensitive to
how the C toolchain is supplied — adding `stdenv.cc` to satisfy the setup-hook
changes swiftc's default target triple and breaks the stdlib lookup.

**Swift therefore comes from a second flake input**, `nixpkgs-swift`, pinned to
`nixos-unstable`. One input for all three toolchains would have meant dragging
Rust and Kotlin — which are working and pinned deliberately — onto unstable to
solve a problem neither of them has. The second input lifts the 5.8 ceiling
that `TabularCenterMacros` would have hit anyway.

`swiftChecked` is now simply `swiftAvailable`: every Swift check runs wherever
a Swift toolchain exists, Linux included. The Darwin-only gate was correct while
the corelibs packaging was untangled and became stale the moment it was — the
kind of temporary exemption that outlives its reason unless someone goes back
for it.

**One thing still does not run here, and it is not a choice.**

`tabular-center-swift/macros` cannot declare a `.macro` target with nixpkgs' SwiftPM, which
ships no `CompilerPluginSupport`; `tabular-center-swift/nix/swiftpm-plugin-support.nix` and the
`swift-macro-support` probe track how far that has been pushed. It reports
`skip` with its reason rather than passing quietly.

`tabular-center-kotlin/examples/06-generated` used to be the second item here. It is not any
more: Gradle resolves from `tabular-center-kotlin/nix/gradle-repo.nix`, a
directory nix assembles from `tabular-center-kotlin/nix/gradle-lock.json` with
one `fetchurl` per artifact, so the annotation processor runs in the sandbox
(`kotlin-ksp`, `kotlin-ksp-compile-fail`, `kotlin-ksp-incremental`). Without
nix, `tools/verify` builds it online against the real repositories.

Every `flake.nix` is a table of contents. Toolchains, shells, checks, apps,
and publication live in the `nix/` beside it, because a flake that grows past a
screen stops being read and starts being copied.

---

## 14. Non-goals and known costs

Stated up front so they are not discovered as surprises.

**N×M explosion.** Six states and eight actions is 48 cells. The static cell
kinds keep most of them one word long, but the count is real. This is the
reason builder DSLs won the market, and it is the cost of the guarantee.

*Measured, on a genuine 8×12 order-lifecycle machine (`tabular-center-rust/tabular-center/tests/scale.rs`):*

| | |
|---|---|
| cells | 96 |
| `IGNORE` | 75 (78%) |
| `GO` | 12 |
| **members the developer writes** | **9** |

The 78% is the load-bearing number. If those 75 cells each needed a body, nobody
would write this; they need one word each. The declaration is 8 lines, one per
row, and stays column-aligned.

Two costs surfaced by the measurement, both recorded rather than smoothed over:

- **Machines past roughly 7×10 need `#![recursion_limit = "256"]`.** The Rust
  muncher recurses about once per cell against a default limit of 128.
  Consuming runs of `IGNORE` several at a time brought an 8×12 machine from
  ~192 to ~160, and the rest is irreducible without abandoning the muncher.
  rustc's own error names the fix, which is why this is documented instead of
  engineered around.
- **A realistic machine trips `tabular-center::ignore-heavy`.** At 78% it crosses the
  70% threshold, and the lint is arguably right: the shipping half shares
  almost no alphabet with the checkout half and would be a cleaner pair of
  composed machines. The threshold was left alone — moving it to silence a
  machine that really is two machines would be fitting the rule to the sample.

**Diff noise.** Adding one action means touching every row of every machine.
That is the feature working as designed, and it will still generate friction in
code review. The `table-diff` tool exists to make those diffs readable.

**One matrix, one color.** Consequence of prototype-driven codegen (§5). Two
colors means two declarations.

**Hierarchy is deliberately absent from v1.** An `INHERIT` cell deferring to a
superstate row is the obvious answer to N×M explosion, and it reintroduces a
place where coverage is satisfied by something other than explicit authorship.
It is deferred to v2, behind a design note, not because it is hard but because
shipping it early would compromise the one guarantee before that guarantee has
been proven in practice.

**No runtime validation, no reflection, no DSL builder.** If it is not knowable
at build time, it is not in this library.

**We do not claim purity.** Cells may do whatever the color permits. The
introspection features degrade accordingly (replay is only exact for machines
that happen to be pure), and the docs say so rather than pretending otherwise.

---

## 15. Cleanness

> **Code reads without comments, except where a reader needs orientation.**
> A file may open with a header explaining its high-level design and how to
> use it, and a type -- trait, struct, enum, class, interface, object,
> protocol, actor, type alias, or a `macro_rules!` macro -- may carry a
> comment explaining what it is for and how to use it. Everything else says
> what it does through its names, its structure and its messages.

Two places earn a comment because the code there cannot explain itself: the
top of a file, where a reader arrives without knowing what the file is *for*,
and a type, which is a contract other code is written against and whose
intended use is not visible in its definition. Everywhere else -- function
bodies, functions and methods, fields, statements, the end of a line -- a
comment is a second description of the code, maintained by hand and checked
by nothing, and this repository has found that kind of drift every time it
looked (`PLAN.md`'s audits are a list of them).

| What the comment said | Where it goes |
|---|---|
| what this file is, its high-level design, how to use it | the file's header |
| what a type is for, its contract, a usage example | the type's comment |
| why the design is this shape; a constraint a reader must know | `ARCHITECTURE.md` -- the section it belongs to, or §16 for build and release configuration |
| what was tried, what failed, what was found, what is still open | `PLAN.md` -- the phase or audit it belongs to |
| normative behaviour another implementation must match | `spec/` |
| what the next line does | nowhere: rename the thing until the line says it |

A header or a type comment is orientation and usage, not history: what was
tried and found belongs in `PLAN.md`, and a long rationale in the section of
this file it belongs to, with the header pointing there.

**What replaces a comment, in the code itself:** a name that says what a
function or value is *for*; a function extracted so its name can carry the
step; an error or log message that tells the reader what went wrong and what
to do -- those are strings, read at exactly the moment they matter, and stay.

**Doc comments follow the same rule.** On a type (`///` or KDoc on a struct,
trait, class, protocol, ...) they are the type's comment and stay; on a
function, method or field they go, and the type's comment or the file header
carries any usage the reader needs. Module docs (Rust `//!`) are the file's
header. So the Rust library does **not** set `#![warn(missing_docs)]`: rustc
offers no lint that requires docs on types but not on functions, and that one
lint, under `clippy -D warnings`, demanded exactly the comments this section
removes. Requiring a comment on every public type is a check of its own
(PLAN, "Cleanness").

**The scope.** `.rs`, `.kt`, `.kts`, `.swift`, `.nix`, `.yml`, `.toml`, shell
scripts, `.editorconfig`, `justfile`, `.gitignore`. Languages without types
(Nix, YAML, TOML, shell) have only the header. Markdown is not in scope (it is
where the explanation lives), nor are the conformance fixtures under
`spec/conformance/`, which are the contract's data.

**Exempt anywhere: comments a tool reads.** These are syntax for a program,
not prose for a person:

- a shebang, on line 1;
- compile-fail markers `//~ EXPECT:`, `//~ AT:`, `//~ BUILDS`, which the
  compile-fail steps parse;
- `// swift-format-ignore-file`, which `swift-format-config` requires on every
  `.tb.swift`, and `// swift-tools-version:` in a `Package.swift`;
- `# shellcheck disable=`, `source=`, `shell=`;
- the version annotation on an action pinned to a commit
  (`uses: owner/action@<40 hex> # v1.2.3`), which Dependabot reads to update
  the pin;
- in a `justfile`, the comment line directly above a recipe, which
  `just --list` shows as the recipe's description;
- the column-header line above a matrix (`//    Start    Tick    Cancel`):
  the table's labels, data rather than commentary, and aligned with the rows
  by `tabular-center-fmt` -- anywhere in a `.tb.*` file, and elsewhere when it
  sits directly above a matrix row (`Idle => [`), as in a test's
  `transition_matrix!`.

**Published code keeps its documentation.** For the published libraries'
sources (`documented_paths` in `tools/no-comments`; Rust's `src/` today),
every file needs a header and every public type, trait and macro a comment,
directly or through attribute or annotation lines (a multi-line `@Machine(...)`
included) -- what `#![warn(missing_docs)]` enforced that this rule keeps.
In Kotlin, public means not `private`, `internal` or `protected`, and the
published sources are `core` and `annotations`; in Swift, whose default is
`internal`, public means `public` or `open`, and the published source is
`Sources/TabularCenter`. A Swift `extension` counts as a type declaration --
it is how Swift spreads a type across files, the `.tb.swift` matrix included
-- and a `#if` line between a comment and its type does not separate them. Two exclusions, both of things that are not
API: items a macro generates (their names are metavariables, `pub enum $a`,
and the generating macro documents them) and macros named `__*`, the
convention for hidden helpers. Members' documentation lives in the type's
comment as a list -- `- \`go\`: Transition to \`next\`, emitting nothing.` --
so docs.rs still shows what every variant, field and method is for.

**Enforced.** `tools/no-comments` (root step and check
`no-comments`) holds each comment block until the next line of code, then
allows it if it is the file's header (nothing but comments and blank lines
before it) or if it attaches to a type declaration -- directly, or through
attribute and annotation lines (`#[derive]`, `@Target`, `@available`), with no
blank line between. Any other comment, and any comment after code on the same
line, is reported with its file and line. It checks every file type in the
scope above (`clean_patterns`, and `clean_files` for scripts and repository
files, which have no extension to match). The migration was staged one file
type at a time, each green on its own; its record is in `PLAN.md`,
"Cleanness".

---

## 16. Configuration, explained

What the build and release configuration does is in the files, and each
file's header says what it is for; the reasons behind each choice inside it
are here. Grouped by file, so a reader of one finds its reasons in one place.

### Cargo manifests and toolchains

- **The library has no dependencies -- none, not few.** The matrix macro is
  `macro_rules!`, part of the language: no proc-macro crate, no build-graph
  cost (§11.1). `tabular-center-conformance` has none either, not because it
  must but because a JSON crate there would be the repository's first
  dependency and the `.tbl` parser is sixty lines. `tabular-center-fmt` has
  none for the reason a formatter should not: every dependency is something
  else that can break the tool people run on source they care about.
- **The crate's README is its own.** crates.io receives the crate directory
  and nothing above it, so `readme` names `tabular-center/README.md`, not the
  monorepo's.
- **The benchmark is `harness = false`, `test = false`.** It has its own
  `main` and times with std alone, so it needs no harness and no
  dev-dependency; `test = false` keeps timing out of `cargo test` while
  `clippy --all-targets` still compiles it, and `asm-identical` builds it.
- **`tabular-center-conformance` sets `default-run`** to its own binary, which
  takes the package's name, beside `table-diff`.
- **The examples are a workspace of complete projects**, one per machine,
  each with its own manifest, dependency line and `tests/` -- an example is
  read as a template, and a real project does not keep its tests in a
  `mod tests` at the bottom of `lib.rs`. One workspace rather than four
  packages, for one `Cargo.lock` that `tools/verify version` checks against
  `VERSION`. Outside the library's workspace, so they depend on it by path as
  a user would; that is how the driver's borrow bug was found.
- **Each example covers a configuration corner.** `01-traffic-light` takes
  the library with `default-features = false` and is `#![no_std]`: `export`
  and `lint` need `alloc`, running a machine must not, and if the macro ever
  allocates this fails here rather than on someone's firmware. `02-timer`
  takes the defaults because it renders and lints its `TABLE`. `03-retry` is
  the only one with a binary, because a driver is a loop and a loop only ever
  unit-tested is a loop nobody has watched (`cargo run -p retry` prints a
  trace).
- **`05-iced` is not a workspace member, and has its own toolchain file.**
  The library's MSRV is 1.75 and the four members hold it: they depend on the
  library and nothing else. iced's tree needs edition 2024, which 1.75's
  cargo cannot parse (the first attempt failed on a vendored `getrandom`
  manifest), so the GUI example is its own package with its own lock, its
  own `rust-version` (the application's: 1.88 today, raised with iced's own floor by the upstream job, `rust-gui` in `dependencies.toml`) and a
  `rust-toolchain.toml` saying `stable`. rustup takes the *nearest* toolchain
  file walking up, and `tabular-center-rust/rust-toolchain.toml` pins 1.75,
  so without its own the example would build on the MSRV under rustup. Nix
  names current stable itself (`rustStable`) and never reads that file. It is
  also the first example with a third-party dependency, which is why the Rust
  flake vendors its `Cargo.lock`.
- **`rustfmt.toml` has no `ignore` for `*.tb.rs`.** `ignore` is nightly-only;
  on stable rustfmt prints a warning per file and formats regardless. The
  stable, silent, per-item exemption is `#[rustfmt::skip]` on the matrix
  (`spec/matrix-files.md`).
- **`tabular-center-fmt` is its own workspace at the root**: it belongs to
  the `.tb.` format rather than to a language, and ships on its own cadence,
  so a formatting change never forces a library version bump. Its contract is
  `spec/tabular-center-fmt.md`.

### GitHub workflows

- **`ci.yml` runs `nix flake check` and nothing else.** It used to duplicate
  the flake's command list, which made three definitions of green -- the
  workflow, the flake, and what a developer typed -- and three lints escaped
  through the gaps. The flake's checks call `tools/verify <step>` and CI calls
  the flake, so all three run the same commands by construction, at the cost
  of a Nix install and coarser step names in the UI.
- **The lock-freshness steps are `nix run`, in the `check` job.**
  `gradle-lock.json` and `swift-lock.json` record what the *flake's*
  toolchain resolves, so only that toolchain can say whether they are
  current (another Gradle may want a different artifact set and go red on
  version skew, not staleness). `nix run` is not sandboxed: it has the
  flake's toolchain and a network, the only place both exist, which is also
  why the question is not a `nix flake check` (a check that reaches the
  network is not a check).
- **`check-darwin` runs the whole flake on macOS** because macro plugins and
  SwiftPM are toolchain-version sensitive and the Darwin toolchain is the
  primary Swift one. It is ungated: an earlier `if: hashFiles(...)` was
  rejected by GitHub in a job-level `if` and invalidated the whole file.
- **`publish.yml`: one registry per job, each holding only its own
  credentials** -- what `nix run .#publish -- --execute` does by hand, after
  `nix run .#release` and `git push --follow-tags`. In the order it matters:
  crates.io uses trusted publishing (GitHub's OIDC identity, `id-token:
  write`, exchanged for a token revoked when the job ends; crates.io's entry
  names this repository, workflow file and the `crates-io` environment, and
  refuses a run differing in any); Maven Central has no OIDC, so its user
  token and signing subkey live only in the `maven-central` environment,
  which should require a reviewer and allow only `v*` tags; every action is
  pinned to a commit, so a moved tag cannot change code holding credentials;
  checkout never keeps its token in `.git/config`; no shared Nix cache, since
  a poisoned cache is a way into a release; and `verify` reruns the checks on
  the tagged commit, holding nothing, because a tag can be pushed on a commit
  CI never saw. The Central credentials are a *user token* pair, not the
  portal login; `SIGNING_KEY_ID` is not secret, so it is an environment
  variable rather than a secret (RELEASING.md, step 4). A manual run resolves
  a tag first -- the dispatched tag, or the one `VERSION` names, which must
  exist -- so it publishes a release, never a branch's current state. Each
  registry job is gated by a *repository* variable (`CRATES_IO_ENABLED`,
  `MAVEN_CENTRAL_ENABLED`), so a tag pushed before a registry is configured
  publishes nothing there. Repository, not environment: a job-level `if:` is
  evaluated before the job enters its environment, where an environment's
  variables do not yet exist (RELEASING.md, "Turning a registry on").
- **`swift-mirror.yml` publishes Swift through a mirror**,
  `tabula-center/tabular-center-swift`, because SwiftPM resolves a repository
  with `Package.swift` at its root. On a release tag it `git subtree split`s
  `tabular-center-swift/` with its history and pushes it, tagged with the
  bare version SwiftPM wants (`0.1.0`, not `v0.1.0`); the split is
  deterministic, so each release fast-forwards the mirror's `main`.
  `swift-standalone` checks on every push that the directory builds alone.
  The one secret, `SWIFT_MIRROR_TOKEN`, is a fine-grained token with
  `contents: write` on the mirror only, in the `swift-mirror` environment so
  its protection rules gate the push. Checkout runs with
  `persist-credentials: false` because git would otherwise send the
  workflow's own token for every github.com URL, ahead of the mirror token,
  and the push would be refused as `github-actions[bot]`'s.
- **`upstream.yml` runs daily** (an off-the-hour minute; top-of-hour cron is
  delayed or dropped under load) and on demand: a matrix over the groups,
  each running `nix run .#upstream -- --group G --update` and, when the tree
  changed, committing to `upstream/G` and opening or updating that one pull
  request; a `report` job keeps one issue, "Upstream: versions needing a
  decision", for what needs a person. It pushes with `UPSTREAM_TOKEN`, a
  fine-grained personal access token in the `upstream` environment, because a
  pull request opened with the workflow's `GITHUB_TOKEN` triggers no
  workflows and would carry no checks. A branch is pushed only when its tree
  changed, so an update nobody has merged yet does not rerun CI every
  morning. Nothing is merged by the job; a red check on an update PR is the
  job working (a kotlinc release can reword a guarantee fixture's message).
- **`pages.yml` deploys the site** that `tools/docs` generates, rendered by
  GitHub's Jekyll action (`jekyll-theme-primer`, per `doc/_config.yml`).
  `doc/` is build output and the site, so `doc/index.md` is the front page.
  It needs one setting, once -- Settings -> Pages -> Source: GitHub Actions --
  and `deploy-pages` fails loudly if it is wrong rather than letting Pages
  render README.md, which is how an earlier `pages.yml` failed. The custom
  domain is set on the same page.

### Upstream versions: `dependencies.toml`

- **Every pinned upstream version is written once**, in `dependencies.toml`,
  with its policy (`auto`: the daily job may propose a newer one; `manual`: it
  only reports one -- the Rust MSRV, the JVM target and the Swift tools
  versions are promises to users) and whether it reaches users. Before it,
  the Kotlin compiler version was typed in seven places and KSP's in four.
- **`tools/deps` owns where each version is written**: a table of sites, each
  a file and the context around the version on one line. `sync` writes
  manifests; `check` (the `deps-consistent` step) reads every site and fails
  on any disagreement, on a site whose context no longer matches (the file
  changed shape, so the table must change with it), on a dependency with no
  site, and on a broken coupling (a prefixed KSP version must be
  `<kotlin>-...` -- KSP 2.3 and later are versioned apart from Kotlin, so a
  standalone version has no coupling to check; swift-syntax's major follows
  the Swift tools version, 5.9 being 509). Compose's minimum Kotlin Gradle
  Plugin is in no metadata, so `tools/upstream` learns it from Gradle: when a
  Compose release is refused with "Minimal supported Kotlin Gradle Plugin
  version is X", the update keeps the old Compose and says why. Sites are per file,
  never a global search: `05-iced` has its own `rust-version`, the
  application's, which is not the library's MSRV.
- **Locks are checked, never written.** `Package.resolved` and the iced
  `Cargo.lock` are a resolver's output, so `check` asks only that they agree
  (the lock on the declared release line); regenerating them -- and every
  `flake.lock`, `gradle-lock.json` and `swift-lock.json` -- needs the network
  and is the upstream job's work. So is the sha256 beside `kotlinVersion` in
  `tabular-center-kotlin/nix/context.nix`: a Kotlin bump through `sync` alone
  leaves the pinned compiler's hash stale, and the Kotlin checks say so.

### Nix: shared shape

- **Five flakes, one lock's worth of pins.** The root composes the three
  language flakes and the formatter's as relative `path:` inputs (Nix 2.26 or
  later; older versions lock such an input as a separate copy of the
  subdirectory, and the language flakes need the whole checkout), and every
  input they share `follows` the root's, so the composed flake has one
  nixpkgs, one rust-overlay and one nixpkgs-swift. The root is a table of
  contents: cross-language checks, the combined shell, release and
  publication live in `nix/`, each toolchain in its own flake. Checks merge
  without collision (a language's carry its prefix, the root's are the
  cross-language step names); the languages' `verify` and `default` apps are
  not merged, because at the root `verify` means every step.
- **Every check is `tools/verify <step>`.** That script is the only
  definition of green, so the flake, CI and a developer at a terminal run the
  same commands. Three lint escapes reached CI while the flake kept its own
  list; a duplicated list is how that happens.
- **A check is given exactly what it reads.** A language check gets its own
  directory, `spec/` (the one input all three share by design) and
  `.editorconfig` -- Kotlin also `VERSION`, which every Kotlin build reads --
  each copied with `builtins.path` so each is hashed by its own contents,
  laid out as in the repository because `tools/verify` names paths from the
  root. Leaving the other languages out makes "independent" a checked
  property: a step reaching into one fails rather than quietly working.
  Hashing separately makes it cheap: editing Kotlin rebuilds no Rust check.
  (They once copied `self.sourceInfo`, the whole checkout, so every commit
  rebuilt every check.) `../../spec` reaches above the flake, which works
  exactly when the flake's source is the whole checkout -- checked from git
  or composed by the root -- so `self.sourceInfo` is asked first and any
  other way in gets a sentence instead of "access to absolute path is
  forbidden". The formatter reads nothing outside its directory and copies
  only that.
- **`patchShebangs` on every script.** The scripts start
  `#!/usr/bin/env bash` and the build sandbox has no `/usr/bin/env`: on CI's
  strict sandbox the first step died "bad interpreter" while a local Nix with
  a relaxed sandbox passed. Every script a check runs by path is pointed at
  the store's bash, so no check depends on the host.
- **Offline is stated, not detected.** The sandbox has no network; a step
  that needs one must skip, so the check builder sets a variable
  `tools/verify` reads, unset everywhere else (a developer without Nix, who
  has the network, still gets the online path). Cargo runs `--offline
  --locked` with a writable `HOME` it would otherwise lack.
- **Absence is loud.** A check that is missing from the attribute set cannot
  report that it is missing, and `nix flake check` prints a tidy green
  summary over it -- how `lib.optionalAttrs` on `pathExists ../kotlin/src` hid
  six checks for months (PLAN 0c). So the KSP checks exist without their lock
  and fail naming the command that fixes it, and a platform with no Swift gets
  a `swift-unavailable` check that passes and says so (red there would mean
  the flake can never pass on that platform, whatever anyone does).
- **Checks and apps are different things.** A check is hermetic and offline;
  an app may touch the network, the git index and a registry token. The
  commands that reach the network are these, and only these: `gradle-lock`
  and `swift-lock`, each writing a committed lock that a derivation consumes
  as ordinary `fetchurl`s; `upstream`, which asks upstreams for newer versions
  and, with `--update`, runs `tools/deps sync` and those two; and `release`
  and `publish`, which reach the registries. None is a derivation, since a
  check that reaches the network is not a check. Every app starts by changing to the repository root: they all
  assumed it, and `nix run .#docs` from a subdirectory failed on
  `./tools/docs: No such file` -- the bug was in all four apps at the time.
- **Apps pin what the host would otherwise choose.** An app runs on the host,
  so it inherits the host's `JAVA_HOME` -- GitHub's Ubuntu image sets
  Temurin 17 -- and Gradle on 17 failed to load a KSP processor compiled by
  the pinned 21 ("class file version 65.0"); the Gradle apps set the pinned
  JDK. `writeShellApplication` prepends its inputs to `PATH` and falls back
  to the host's, which on macOS is BSD `find` and `sed`, so apps that edit
  files list the GNU tools. The root apps run the Swift setup (runtime
  library path, `NIX_CC`) the Swift checks run.
- **The docs preview.** Jekyll is only in the `docs` app: it is the one
  consumer, and a shell would put Ruby on every Rust developer's path. The
  app regenerates `doc/` before serving -- a preview of something the
  repository does not contain is worse than none -- and renders without
  `jekyll-theme-primer`, a Pages built-in absent from nixpkgs' Jekyll, by
  overriding the config rather than editing the generated one: a content
  preview, not a pixel copy of the site.
- **`nix fmt` is not a check:** a formatter bump should not fail CI on files
  nobody touched.

### Nix: Rust

- **The GUI check alone carries the GUI's system libraries.** winit and wgpu
  find fontconfig, xkbcommon, X11 and wayland through pkg-config; vendoring
  crates cannot supply them, and putting them in the common inputs would put
  an X11 stack behind `cargo test` for a library with nothing to draw. Linux
  only: on macOS iced draws through Metal and AppKit from the default SDK,
  and nixpkgs refuses even to *evaluate* `wayland` for Darwin -- a refusal
  that once took every Darwin check down. The X11 packages are named
  `new or old` (`libx11` or `xorg.libX11`) so the pin can move either way.
- **Vendored crates come straight from the committed `Cargo.lock`**
  (`importCargoLock`), so there is nothing to generate or keep in step. The
  vendor configuration is written for every check, not "the ones that need
  it": that list was wrong the first time (clippy resolves the examples
  workspace too, and failed on `iced` while the examples check passed). The
  GUI example's lock and toolchain (current stable) are separate, and null
  until its lock exists, because `importCargoLock` on a missing file fails at
  evaluation and would take the whole flake down.
- `rust-matrix-stable` is separate from `rust-fmt`: `cargo fmt --check` asks
  whether the tree matches rustfmt; the matrices need rustfmt to have no
  opinion about them at all, which it does not today (macro bodies are left
  alone). `package` builds the crate from the archive crates.io would receive.

### Nix: Kotlin

- **kotlinc is pinned and owned** (2.1.20, matching both Gradle builds, the
  KSP pair and the README). It was `pkgs.kotlin`, and moving nixpkgs for
  Swift moved the Kotlin compiler with it. That matters because four
  fixtures assert on kotlinc's own message text, which spec/diagnostics.md
  says must not be normalised: the fixtures should move when we move the
  compiler, on purpose. Owned rather than overridden, since an override
  depends on nixpkgs' installPhase; the distribution is shell scripts and
  jars and wrapping it is five lines. Bump the version and hash together,
  with the Gradle builds.
- **The JDK, and only the JDK.** `JAVA_HOME` is nixpkgs' declared home, not
  the package root (on Darwin it is `.../Contents/Home`, and a wrong one sends
  Gradle looking for a JVM itself). Gradle's auto-detection is switched off
  in `GRADLE_USER_HOME`'s `gradle.properties`, which outranks the project's:
  on a macOS runner, whose sandbox is not sealed the way Linux's is, it found
  the runner's JDK 17 and failed on the processor 21 compiled. The store path
  exists only there, so nothing committed names one.
- **Gradle's cache lives with the Kotlin it serves**, anchored to the
  checkout; it was `./.gradle-home`, relative to wherever `nix develop` was
  typed.
- **The offline Maven repository is assembled from the lock**, one
  `fetchurl` per artifact. It replaced a fixed-output derivation that ran
  Gradle in the sandbox and hashed its cache, wrong twice over: networking
  from the JVM inside a build turns a missing route, missing DNS and an
  unread CA bundle into one indistinguishable error, and a Gradle cache does
  not hash reproducibly. Lock entries carry the Maven layout path, so nothing
  parses coordinates (a rule with exceptions -- classifiers, packaging,
  plugin markers); files are `install -D`'d, not symlinked, because Gradle
  writes lock and `.part` files beside what it reads and a read-only symlink
  farm fails three layers down; checksum sidecars are omitted because Gradle
  never asks for them from a path repository. The core of gradle2nix, owned.
- `kotlin-ksp` is its own check because its inputs are not only source: a
  failure there is a stale lock or a broken processor, and inside the
  examples step it would read as an example being broken.

### Nix: Swift

- **The `nixpkgs-swift` input is on its way out.** It exists because nixos-25.05
  shipped Swift 5.8, below the 5.9 macros need; delete it once a Darwin run
  confirms `swift-macros` passes on `nixpkgs` alone.
- **What nixpkgs' Swift needs, learned one failed round at a time.** Its
  setup hook requires `NIX_CC`, supplied as a plain variable: adding
  `stdenv.cc` instead puts gcc on the path, swiftc takes its target from gcc
  (`x86_64-pc-linux-gnu`) while its stdlib is built for
  `x86_64-unknown-linux-gnu`, and "could not find module '_Concurrency'" is
  really a triple mismatch. Every Swift part comes from one nixpkgs, since
  two generations disagree about the host triple ("glibc not found" was the
  cause, not noise). The corelibs are separate derivations from the `swift`
  wrapper, so the runtime path is built from them, by Nix, rather than from
  `swift` or from `swiftc -print-target-info`, which reports module paths
  and not where `libdispatch.so` is. `swift-unwrapped` contributes its
  libraries only: its `bin` shadowed the wrapper's swiftc and reintroduced
  the triple mismatch. The compile inputs are one named list used twice,
  because the augmented SwiftPM needs them and is itself part of the full
  set. The setup, `NIX_CC` included, is exported to apps too: run on the
  host without it, `swift-lock --check` died before printing a byte.
  **Response files are off for Swift** (`NIX_CC_USE_RESPONSE_FILE=0`, in the
  setup, the check builder, the shell and the root's `env`): nixpkgs' Swift
  wrapper otherwise passes its arguments as `@<(printf ...)` wherever the C
  compiler is clang, so on Darwin the Swift driver -- a Foundation program --
  re-opens `/dev/fd/63` by path after the pipe behind it is gone, and fails
  with "The file '63' couldn't be opened ... Bad file descriptor". Linux's
  default is already off, which is why only `check-darwin` saw it.
- **The Swift checks run on Linux** too, since that packaging was untangled;
  Darwin remains the primary toolchain (§13). Only Swift shells set
  `LD_LIBRARY_PATH`, a blunt instrument. The Swift shell opens at the root,
  where there is no `Package.swift` and three below it, so it says which
  rather than choosing. `swift-lock` runs inside the dev shell, not as a bare
  app, because Swift depends on what setup hooks export: run bare, swiftc
  answered `-print-target-info` and SwiftPM still got an empty answer.
- **The offline swift-syntax checkout set** is what SwiftPM needs to believe
  it has resolved: `.build/checkouts/<name>/` and a `workspace-state.json`;
  without the state file it re-resolves and fails offline, which looks like
  the checkouts being ignored. `fetchurl`, not `fetchzip`: the generator
  records `sha256sum` of the tarball, `fetchzip` hashes the unpacked tree,
  and the two disagree by construction -- taking the `got:` value would pin a
  NAR hash beside a tarball hash and leave the lock forever "stale". The
  checkout directory is named after the repository (a mismatch silently
  re-resolves), GitHub's archive wrapper directory is stripped, and the
  state file's version (6, what SwiftPM 5.9-5.10 writes) is pinned, because
  one the toolchain does not recognise is discarded silently. The core of
  swiftpm2nix, owned. `swift-deps` is buildable alone so those two values can
  be inspected in one command.
- **`swiftpm-plugin-support`: nixpkgs' SwiftPM with `CompilerPluginSupport`.**
  An `overrideAttrs`, because a copy cannot work: the manifest API path is
  baked into the `swift-package` binary at build time, so a copy inherits
  the original's and is never consulted (four rounds went to copies).
  `PackageDescription` is rebuilt with a private module interface, because
  `CompilerPluginSupport` imports it through SPI that a public interface
  strips. Both modules are compiled separately and linked into the one
  library the manifest loader names, `libPackageDescription`: a separate
  library is not found, and modern `ld` will not resolve through
  `DT_NEEDED` (`--no-copy-dt-needed-entries`). The work is in `postFixup`,
  because the derivation's custom `installPhase` never runs `postInstall`;
  the source root is found rather than guessed; exported symbols are read
  with `nm -D` on ELF and `nm -gU` on Mach-O, which has no dynamic table.
  The build fails unless the module and its symbols are present -- five
  earlier attempts reported success while broken -- and the symbol check
  goes through a file, never `nm | grep -q`, because under `pipefail` an
  early-exiting grep SIGPIPEs nm and turns a found symbol into a failure.
  Build it through the flake: against an ambient `<nixpkgs>` it picks a
  different Swift with no cached build.

### Nix: release and publication

- **`release` prepares and `publish` ships**, because their failures differ:
  a bad release is a corrected commit, a bad publish is a version burned
  forever on crates.io. So the destructive step is opt-in (a dry run unless
  `--execute`) and the safe one is the default.
- `release` checks the tag is free before the long check, not after; edits
  only tracked files and on failure restores them with `git checkout -- .`,
  never `git clean`, which would delete a developer's untracked work; derives
  every manifest from `VERSION` (Kotlin reads `VERSION` itself); refreshes
  each `Cargo.lock` the bump stales -- editing the GUI example's single path
  entry rather than `cargo update`, which would re-resolve iced offline from
  whatever the host cached; and runs `nix flake check`, not the host's
  `tools/verify`, as the definition of green (a host run once failed
  `rust-gui` offline on a crate missing from `~/.cargo`). Releasing the
  version the tree already carries commits nothing and tags `HEAD`.
- `publish --only rust|kotlin|swift` publishes one ecosystem, so each CI job
  holds one registry's credentials. Rust is one crate (`macro_rules!` ships
  in the library that declares it). Kotlin is five artifacts in one Central
  bundle, validated and published as a unit through the Portal API; past
  validation the release is Central's to finish, so `PUBLISHING` ends the
  wait as `PUBLISHED` does, and `FAILED` prints Central's reasons. Swift has
  no registry: the pushed tag triggers the mirror workflow.

### Scripts and repository files

- **`tools/docs` includes, never pastes.** Every sample is cut from the tree
  at generation time by file and regex range (awk EREs passed through the
  environment, because `-v` runs escape processing and would turn `\{` into
  `{`); a range that stops matching fails the generator and `tools/verify
  docs`, so a page cannot show a machine that no longer builds. Pages are
  written from quoted heredocs only, since markdown's backticks would run as
  commands in an unquoted one. Heading anchors are injected as `<a id>`
  rather than derived, because Jekyll and GitHub derive them differently and
  across versions, and these anchors sit inside error messages; codes without
  a section of their own get an anchor in an index at the end, only where one
  is missing (duplicate ids are invalid and the first would win).
  `DOCS_BASE` is the one place the site's URL lives, because every
  implementation's messages link under it. Generation starts from an empty
  `doc/`, so a page the generator stopped writing cannot linger. The
  `doc/` history -- a workflow that Pages ignored, then committed output
  served from the branch, then a workflow again with its one setting
  documented and a deploy that fails rather than falling back -- is in PLAN.
- **Every script that sorts sets `LC_ALL=C`.** Output that is committed or
  compared must order the same on every machine, and `sort` follows the
  locale: `en_US.UTF-8` ignores punctuation, `C` compares bytes. A lock
  written on a desktop put `annotation/1.9.1/` before `annotation-jvm/`; CI
  called it stale.
- **The lock generators share one shape.** `gradle-lock` and `swift-lock`
  are the only commands that reach the network; each writes a committed lock
  of one URL and one hash per artifact, which a derivation fetches with
  Nix's own downloader. Neither is a fixed-output derivation running the
  package manager in the sandbox: that asks a program with its own network
  stack, TLS trust and cache layout to be reproducible, and reports every
  failure as one resolution error (five patches went to Gradle's one
  sentence), and a Gradle cache does not hash reproducibly anyway. The
  hash is taken from the bytes downloaded, so a wrong URL cannot record a
  right hash: that is what makes a lock checkable rather than plausible.
  - `gradle-lock` resolves every Gradle build under `examples/` --
    discovered, not listed, since a hardcoded path once left the Compose
    example out while reporting success -- in a fresh `GRADLE_USER_HOME`
    (a warm cache records a superset nobody can reproduce), into one cache
    whose union is the lock. URLs are recovered from the cache layout,
    `files-2.1/<group>/<name>/<version>/<sha1>/<file>`, which is a Maven
    coordinate and so a repository path, tried against each declared
    repository in Gradle's order until one serves matching bytes (a mirror
    serving different bytes under the same path is rejected). Per-platform
    Compose natives are resolved for every platform the checks run on
    (`resolveForLock`, `-PdesktopTarget`), because a lock holding one
    platform's fails the others. The Gradle version is recorded in the lock,
    since two versions can want different artifact sets; output is sorted
    for a stable diff; Gradle sees only the pinned JDK, as in the checks.
  - `swift-lock` needs no cache archaeology: `Package.resolved` pins a
    revision, and GitHub serves any revision as
    `<repo>/archive/<revision>.tar.gz`. It records the tarball's hash
    (computable anywhere with `sha256sum`), which is why `swift-deps.nix`
    uses `fetchurl`. It names the compiler for SwiftPM (`SWIFT_EXEC`)
    because SwiftPM discovers toolchains itself and `nix develop` only adds
    to the host's `PATH` -- on GitHub's image it found the image's own Swift
    and got an empty target-info answer -- and asks `swiftc` directly first,
    since SwiftPM reports a broken environment as "malformed json". It reads
    both `Package.resolved` layouts (`pins` in v2, `object.pins` in v1),
    whose version follows the toolchain.
- **`compile-fail` (Rust)** is a harness of its own rather than `trybuild`,
  which would be the crate's only dev-dependency. It links fixtures against
  the uplifted `target/debug/libtabular_center.rlib`, not the newest
  `deps/libtabular_center-*.rlib` by mtime (which picked stale builds
  irreproducibly) nor cargo's JSON `filenames` (emitted only on a rebuild,
  so empty on every no-op run). A fixture passes only if rustc's *exit
  status* says it refused the file: a fixture that compiled with a warning
  containing the expected text once read as ok.
- **The `verify` scripts share four mechanisms** (the formatter's is the
  smallest copy). *The ledger:* every step's output is teed into one file
  and every `skip` is reprinted before the verdict, because a skip is not an
  error, scrolls past a green run, and hid the whole Kotlin suite and the
  KSP example for months; `PIPESTATUS` keeps the step's status through the
  pipe, and the run still streams. A script called by the root leaves the
  ledger to the root, which has already seen every line. *The verdict* names
  the failed steps again, because `FAILED: <step>` scrolls away. *A missing
  directory* is reported as what it almost always is: `nix flake check` on a
  dirty tree includes modified tracked files and excludes untracked ones, so
  a patch applied with `git apply` and not yet added shows its edited scripts
  and none of its new directories. *Portability:* POSIX classes rather than
  `\s`, since BSD grep and sed ignore `\s` and the ledger would silently
  match nothing on macOS without Nix; `${a[@]+...}` for arrays, since an
  empty array under `set -u` is an error in macOS's bash 3.2.
- **`central-bundle`** stages the root build's four artifacts and the KSP
  processor into one Maven-layout directory and zips it, the bundle the
  Central Portal takes; `maven-metadata*.xml` is dropped, because it belongs
  to a repository and Central builds its own. The same script serves
  `nix run .#publish` and the `kotlin-publication` check, which proves the
  bundle would pass Central's rules on every push.
- **`.editorconfig`** exempts only `*.tb.kt` from ktlint's alignment and
  wrapping rules: a matrix is as wide as it is, its columns are the point,
  and `kotlin-matrix-stable` would fail on a rule that reflowed them. It
  once exempted every `.kt` file -- a wide exemption for a narrow problem
  (spec/matrix-files.md).
- **`.gitignore`**: Gradle's `.gradle/` patterns are unanchored, because
  Gradle writes one beside every build file and anchored patterns once let
  `ksp/.gradle/executionHistory` into a commit (a pattern does not untrack
  what is already tracked; that took `git rm -r --cached` once). The main
  Swift package's `Package.resolved` is ignored and the macro package's is
  not: the first pins nothing, the second pins swift-syntax and is
  `swift-lock`'s input. `.kotlin/` is Kotlin 2's per-project session data.
- **`justfile`** recipes are thin aliases for `tools/verify` and the apps;
  the comment above each recipe is its description in `just --list`, which
  is why those lines are exempt from §15.

### Rust tests, examples and the conformance harness

What their comments carried that a reader of the tree needs:

- **`tests/reference_timer.rs` is the macro's specification**, in five parts
  -- domain types, the narrowed variant structs, the cell surface (the
  `where` clause on `step`: one `Handle` bound per non-static cell; static
  cells resolve in the dispatcher and appear nowhere), the dispatcher (no
  wildcard arm, so a new state or action breaks the `match` -- a second
  guarantee on top of the bounds), and the effect surface (one `Perform`
  bound per effect variant). `tests/timer_matrix.rs` is the same machine
  through the macro, asserted to agree; `asm-identical` checks they compile
  to the same code.
- **`tests/scale.rs` retired a risk by measurement**: a realistic 8x12 order
  machine is 78% `IGNORE` -- the fact the design rests on -- and crosses the
  `ignore-heavy` threshold, fairly; it needs `#![recursion_limit = "256"]`
  (§14).
- **Composition** (`tests/composition.rs`, `examples/04-login`,
  `examples/05-iced`): one type implements parent and child cells, so the
  parent passes itself to the child's `step`; the lens is written once per
  (parent state, child), the prisms once per delegate cell; `embed` returns
  the full parent state because a child transition is often a parent
  transition; a composed child's effects are lifted and performed by the
  parent, which decides what they mean, and a prism may decline.
- **The driver takes one environment** for its two closures (cells and
  context together), because two closures cannot each borrow them mutably;
  `examples/03-retry` found that in the driver's signature.
- **`PAYLOADS` records the types as declared** (`u32`); the lint
  canonicalises (`int`) before rendering, so three implementations can agree
  on a `.lint` while each generator reports its own source truthfully.
- **The conformance harness** compares each generated `TABLE` with its
  fixture cell by cell -- several wrong tables give right answers on any one
  trace, so trace replay alone misses a mis-parsed cell kind -- and a
  negative test proves the comparison can fail. Fixtures are discovered, not
  listed, with a floor against a walk that finds nothing; the trace format is
  flat, so a child's state is addressed by prefixed fields
  (`child_attempt=1`); `.tbl` joins effects `GO(T, A, B)` and the rendered
  grid `GO(T, A+B)`, deliberately (spec/cells.md). Several fixtures exist for
  the `stay`/`ignored` distinction: a `HANDLE` cell that refuses is `stay`,
  an `IGNORE` cell never runs.
- **The benchmark** asserts parity first (same states, same effect counts),
  interleaves rounds across the three versions so drift lands on all of
  them, and keeps the work observable with `black_box`; `plain` returns
  `(State, Option<Effect>)` and is expected to be faster.

### The Rust library's internals

- **Lint thresholds are deliberately generous** (`IGNORE_HEAVY_PERCENT`,
  `UNREACHABLE_HEAVY_PERCENT`, `PAYLOAD_HOIST_STATES` = 3): a lint that fires
  on healthy machines is a lint people turn off. `dead-row` subsumes
  `no-static-exit`, so one problem is one warning. Reachability findings are
  reported only for a fully static matrix: a `HANDLE` target is unknowable at
  build time, and guessing would make the lint lie. Payload fields group by
  name *and* canonical type -- `count: u32` and `count: usize` are one idea,
  `count: u32` and `count: String` are two -- and canonicalisation
  (spec/diagnostics.md) lets three implementations agree byte for byte.
  `Payloads` lives in `table`, not `lint`: declared in `lint` it made every
  machine built without `alloc` fail to compile.
- **One edge walk feeds every renderer**, so a machine renders in the same
  order in Mermaid, DOT and the grid, and a new format cannot invent its own
  -- Mermaid once emitted every `GO` edge before every self-loop while Kotlin
  and Swift interleaved them. Dynamic cells are self-loops annotated with
  what will run, never a guessed edge. The grid counts the machine name in
  the first column's width and right-trims every line.
- **The coverage report imports the lint's thresholds** rather than repeating
  them: the two are views of one matrix and drifted while the report had no
  golden (it warned on a single deliberate `UNREACHABLE`, the case the spec
  says must stay silent).
- **`TABLE` labels are bare variant names** -- `GO!(Running { since: 0 })` is
  `Running` -- computed in `const` context, since `TABLE` is a `const`.
- **The driver applies the outcome before performing effects**, so a handler
  that enqueues an action sees the post-transition state; follow-ups are
  queued at the back, never recursed into, strictly FIFO; re-entering `run`
  is reported (`Reentered`) so that it is loud if the design's guarantee ever
  breaks.
- **`DEFAULT_EFFECT_CAPACITY` is 2**, deliberately small: a cell wanting more
  is usually a cell that wants splitting, and the ceiling makes that
  visible. Overflow is a programming error (capacity is a compile-time
  property), so `push` panics and `try_push` exists where that is not true.

### Kotlin generation and processing

- **The emitter reproduces hand-written code.** `test/ReferenceTimer.kt`
  (with its dispatcher, which exists only there: a developer never writes a
  `when`, so `else` is not a temptation, it is not available) and
  `test/Composition.kt` fix the shape; `codegen/Emit.kt` must produce it, and
  `kotlin-codegen` proves the output compiles, is satisfiable, still refuses
  an incomplete implementation, and is deterministic. Nothing generated is
  committed.
- **Validation lives in `buildDesc`, not in the processor.** Every
  declaration diagnostic fires in `codegen`, where `Tests.kt` has a case for
  each; the processor only extracts a `RawMachine` and adds a source position,
  so a diagnostic's text is identical through KSP and through the tests. Row
  tagging happens in one place, the loop that knows the row. Extraction is
  the one step nothing else checks, so KSP's output is compared with twins
  stated by hand (`codegen/Main.kt`), not with a second extraction.
- **Prototype modifiers are copied verbatim**, never enumerated: a `suspend`
  prototype gives suspending members, a receiver prototype makes every member
  a member extension (calling one needs both receivers), and
  `@Composable` on the transition prototype is a warning
  (`composable-transition`), not a refusal -- colors are copied, never
  judged. Annotations are copied qualified, since the generated file imports
  only `center.tabula`. Visibility comes from the annotated declaration, not
  the prototype, because the generated surface names the machine's own types.
- **Names**: a cell member is `idleStart` (KSP can build identifiers, which
  Rust's macro cannot -- hence its trait bounds, §11.0); two things given one
  name are `member-collision`, refused even though Kotlin would accept them
  as overloads. Lens members are per child, the action prism per cell; a child
  is reached through its package and named through its alias. Effects with
  arguments are emitted as references (`Halt(reason = "cancelled")`), while
  `TABLE` records only the name.
- **Spines** (spec/happy-paths.md) are validated before anything derives from
  them -- a default computed from an invalid spine is worse than none: shape
  first (states and actions alternate), each hop through *that* cell, a path
  must end, walking back is not leaving. A `HANDLE` named by a hop becomes a
  `GO`; an explicit cell always wins; a machine with no path is untouched.
- **Additive features emit nothing when absent**: the rendering surface and
  the narrowed surface are both optional, and a machine without them
  generates exactly what it did before they existed.
- **The processor throws on an annotation shape it does not recognise**,
  where `filterIsInstance` once dropped it silently; a payload type it cannot
  resolve degrades only `payload-hoist`.

### Swift packaging and generation

- **Three packages.** The library's (`tabular-center-swift`) has no
  dependencies at all, and its `TabularCenter` product links nothing but the
  standard library -- not Foundation: a published library should not put
  Foundation on a consumer's link line to trim a string. The examples are a
  separate package that depends on the library by path, the only place the
  public API is exercised from outside; its path dependency is identified by
  directory name, which is why the library directory is not called `swift`.
  The macro package is separate because it is the only target linking
  swift-syntax, a remote package, while the rest builds with no network.
  `TabularCenterCodegen` is a product, not just a target, because SwiftPM lets
  one package reach only another's products.
- **Checks are executables, not test targets**: nixpkgs' Swift ships no
  XCTest. **No `platforms:` clause**: a deployment target there is a floor for
  every consumer, so `ObservableStore`'s macOS 14 requirement lives on that
  type, as `@available`.
- **`ObservableStore` is gated on `os(macOS) || os(iOS) || ...`, not on a
  module**, after two weaker guards each answered an adjacent question:
  `#if canImport(Observation)` is true on the pinned Linux toolchain while
  `@Observable` still fails to resolve, and removing the macro compiled and
  linked a binary that died on `libswiftObservation.so: undefined symbol`. The
  type exists to be watched by SwiftUI, and SwiftUI exists only on Apple
  platforms, so the guard asks that directly.
- **The Swift emitter** follows Kotlin's (validation in `buildDesc`, names
  like `idleStart`, lens per child and prism per cell, effect references
  verbatim with only names in `TABLE`). Swift-specific: what it cannot
  produce correctly it refuses as `#error` at the top of the generated file;
  a colored call is two statements so `try await` appears once; payload
  bindings must not shadow the dispatcher's own parameter names; and
  `rethrows` needs a throwing parameter, so a hop with no alternatives omits
  it. The mailbox is fixed-capacity: an unbounded one only moves the failure
  somewhere harder to see.

### The checks, step by step

The four `verify` scripts are the definition of green (§13): the root owns
the steps that read more than one implementation and hands every other step,
by name, to the language script that declares it in `--list`. Each runs from
the repository root. What each step guards, and the reason it is built the
way it is when that is not obvious:

**Root.**
- `version`: `VERSION` is the single source of truth, and every derived copy
  is checked -- including all three `Cargo.lock`s, which record the crate's
  version through path dependencies (the GUI example's was once missed),
  because a stale lock fails as a `--locked` error naming the lock, not the
  bump. `docs`: `doc/` can be generated faithfully (§16, Scripts).
- `renderings-agree`: `.tbl` and `.trace` are the contract, authored by
  hand; `.grid`, `.mmd`, `.lint`, `.cov` are output. They were committed until
  September 2026, Rust's blessed and the others compared against them, which
  made one implementation the expectation for the others. Now each renders
  into its own directory (`<lang>-render`: exit 0 with files, or exit 0 with
  a `skip` line and none) and the directories are diffed pairwise against
  the first present. Fewer than two implementations is a failure: one agreeing
  with itself is not a comparison. It also checks the fixtures table of
  `spec/diagnostics-coverage.md` against the lints just rendered.
- `no-bless`: no command in a `verify` script or `nix/` mentions a bless flag
  or variable -- a definition of green that can rewrite what it compares
  against passes by construction. Not hypothetical: `swift-codegen` once took
  one. `no-generated`: no emitted source and no rendering is committed; what
  emitted code must satisfy is checked from source instead (it compiles, a
  complete implementation satisfies it, an incomplete one is refused,
  emission is deterministic, KSP extracts what its hand-stated twins say).
  `fixtures-complete`: every fixture has a table and a trace.
- `diagnostics-coverage`: every code each implementation emits matches
  `spec/diagnostics-coverage.md` in both directions -- emitted but unlisted,
  and listed but not emitted, since an implementation quietly *losing* a
  diagnostic is the case that matters. Quoted matches only (an unquoted
  `tabular_center::lint::report` is a module path). The table must cover
  `spec/diagnostics.md` exactly. Text only, so it runs where no toolchain
  does. `diagnostics-tested`: every runtime lint is tripped by a listed
  conformance fixture and every declaration code is named by a compile-fail
  fixture's `//~ EXPECT:`; a code emitted by nobody (`-`) must stay unfixtured.
- `matrix-covered`: each formatter-stability check scans roots it names, so a
  matrix outside all of them is unchecked *silently* -- `06-generated`'s sat
  outside `kotlin-matrix-stable` while both checks were green. So this
  enumerates every `.tb.` file and asks which scan reaches it. `tb-aligned`:
  every matrix is exactly what `tabular-center-fmt --check` would leave, and
  a file the formatter cannot read fails too; the fix is `nix run .#tb-fmt`.
- `licenses`, `no-comments`: §15 and Phase 0 of PLAN.

**Rust.**
- `fmt` and `clippy` cover both cargo workspaces (the examples sit outside
  the main one, and trailing whitespace once reached a patch `cargo fmt
  --check` had passed). Where clippy is not installable, rustc's own lints run
  over `--all-targets` (an unused import in a test passes `cargo build`) and
  the run says loudly that clippy-only lints were not checked
  (`module_inception` once escaped that way).
- `no-std` builds the library without features for a bare-metal target, and
  falls back only when that target is genuinely missing (it once fell back on
  any failure, reporting a stale lock as "target unavailable"). It cannot
  check what the macro *emits*, so `examples` builds `01-traffic-light` alone
  with no features -- the macro once emitted a path gated on `alloc` for every
  machine, and only a consumer could notice. The examples are a separate
  cargo invocation, as a user's crate would be; `01` is built alone because
  cargo unifies features across a workspace; `03-retry` is run.
- `compile-fail`, `conformance` (with a smoke run of `table-diff`, whose
  argument handling nothing else executes), `rust-gui` (the GUI example on its
  own toolchain), `package` (the crate from its crates.io archive, offline,
  `--allow-dirty` because the sandbox has no git), `asm-identical` (§11.1).
- `rust-matrix-stable`: rustfmt leaves matrices alone because it bails on a
  macro body that is not a Rust expression. That is an implementation detail
  the tree depends on in every `.tb.rs`; a rustfmt that formatted macro
  bodies would collapse every matrix and `fmt` would then demand the collapsed
  form. So it is asserted: format a copy of both workspaces, compare the rows.
  `tests/compile_fail/` is excluded, since no cargo target contains those
  files and comparing them would pass because nothing happened.

**Kotlin.**
- `kotlin` compiles each published artifact against only its declared
  dependencies -- `core` with an empty classpath, which is the
  zero-runtime-dependency rule enforced by construction; a classpath rather
  than a merged directory, since each module's `META-INF/main.kotlin_module`
  would clobber the others'. `kotlin-examples` compiles each example alone and
  its tests against its output, and `01` against `core` alone, so the minimum
  a machine needs is checked; the suspending driver builds against `core`
  alone, which proves it needs no kotlinx.coroutines. A note, not a failure, when the
  kotlinc on PATH is not the pinned one, because the guarantee fixtures match
  kotlinc's own wording.
- `kotlin-ksp` runs the processor (06-generated cannot fall back to kotlinc:
  without KSP there is no `Cells` to implement) against the offline
  repository, warns when the Gradle in use differs from the lock's, and checks
  extraction against hand-stated twins, since a table read wrongly still
  compiles. Never `--offline`: Gradle's offline mode means "dependency cache
  only" and refuses a `file://` repository as external. Generated output is
  found by name, since KSP's directory has moved between versions.
  `kotlin-ksp-incremental` edits `Types.kt` -- not the annotated file -- in a copy of
  the whole Kotlin tree (relative paths reach `../harness` and `../../core`),
  and requires the regenerated `PAYLOADS` to change; output is kept, and `e:`
  lines shown first, because Gradle's summary hides the cause.
- `kotlin-ksp-compile-fail` turns `TabularCenterError` into a failed
  compilation through `KSPLogger.error`, the step `codegen/Tests.kt` cannot
  reach. Exactly one `//~ EXPECT:` per fixture, across its files; `//~ AT:`
  asserts the underlined line (a message without a node prints no position);
  `//~ BUILDS` marks a warning fixture that must succeed and still print its
  diagnostic, positioned; KSP's position has no column, and the first line
  that yields one wins over Gradle's summary.
- `kotlin-codegen` emits into scratch, then requires the output to compile, a
  complete implementation to satisfy it and an incomplete one to be refused;
  the status checked is kotlinc's, not the filtering grep's. `kotlin-compose`
  runs the headless machine checks, not just `build`. `kotlin-publication`
  builds the Central bundle signed with a key made for the run and shaped
  like the release key (certify-only primary, ed25519 signing subkey,
  subkey-only export), in a short-pathed home because gpg-agent's socket path
  is limited to about 104 bytes. Every Gradle run goes through one wrapper
  that confines Gradle to the pinned JDK.
- `kotlin-matrix-stable` runs ktlint's formatter over a copy with the
  `.editorconfig` -- the exemption is what is being tested -- and compares the
  matrix rows only; ktlint's opinions about the rest are not adopted. Every
  `.tb.kt` counts, a file with no matrix lines fails, and a scan that matches
  nothing fails.

**Swift.**
- `swift` builds and runs the checks with `swift run` (nixpkgs ships no
  XCTest), in release (debug info failed on the toolchain's glibc warning;
  macOS signs debug executables with `/usr/bin/codesign`, absent from a Nix
  build's PATH), with a writable `HOME` and SwiftPM's per-user directories
  pointed somewhere writable. It reports the swiftc in use, its version, and
  whether the runtime library is reachable before running anything, and names
  a triple mismatch as such.
- `swift-compile-fail` typechecks fixtures against the built module, outside
  any target. `swift-codegen` validates, emits to scratch, then compiles every
  machine in one module with complete implementations and requires incomplete
  or miscolored ones to be refused. `swift-examples` runs each example
  separately and names the failures again last, with their final lines,
  because a failed check shows only the last 25 lines.
- `swift-macro-support` probes with a four-line package whether this SwiftPM
  can declare a `.macro` target, distinguishing a missing feature, a broken
  augmented derivation, swiftc built without macros, and a probe that failed
  for an unrelated reason. `swift-macros` builds against the offline
  checkouts and runs `TabularCenterMacroSyntaxCheck` (building is not
  checking), matching our own compile errors before network patterns, because
  SwiftPM's cache probe prints `fatal: unable to access` on every run;
  reaching the network with a locked set is a failure.
- `swift-matrix-stable` runs swift-format over a copy of each `.tb.swift`,
  after a liveness probe proving the formatter rewrites something, and
  requires each file back unchanged. `swift-format-config` holds with no
  toolchain: every `.tb.swift` carries `// swift-format-ignore-file` (the
  whole of swift-format's exemption mechanism), and any config names
  `.tb.swift`. `swift-standalone` builds this directory alone, as the mirror
  holds it.
