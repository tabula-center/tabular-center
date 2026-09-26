# tabula — Architecture

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
| 1. Matrix well-formedness | tabula generator | missing cell, duplicate cell, bad row arity, unknown state/action, unconstructible `GO` target, illegal delegation |
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
error[tabula::row-arity]: row `Running` has 2 cells, expected 3
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
> stable. Any other prototype is `tabula::unsupported-color`. An async parent
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
`tabula::go-target` diagnostic only where construction cannot do the job.

```
GO(Idle)                          // ok — payload-free
GO(Running, since = 0)            // ok — literal
GO(Running)                       // error — `since: Long` cannot be derived
```

```
error[tabula::go-target]: cell (Done, Start) uses GO to `Running`,
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
warning[tabula::payload-hoist]: `retryCount: Int` appears in payloads of
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
from tabula. Every generator puts the parent's color on the call into the
child, so rustc, kotlinc and swiftc each refuse it by construction, and
`tabula::color-mismatch` is reserved and emitted by nobody (decided September
2026; `spec/diagnostics.md` lists the three fixtures). The message a generator
would otherwise print:

```
error[tabula::color-mismatch]: machine `Timer` (prototype: `fun handle`)
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
- **Golden matrix snapshot** — `TABLE` serialized to the conformance format
  (§12), diffable in review. A PR that changes machine behaviour shows the table
  diff, not just the code diff.

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

Color is a `$($color:tt)*` capture splatted onto each generated `fn`, with
`$(.await)?` at call sites gated on the same capture. *Design, not yet
implementation: see §5's Rust status note.*

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

Generated:

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
code and `tabula-core` have zero runtime deps). Incremental builds slow.
IDE resolution of generated symbols is flaky until first build. Nested
annotation matrices are wordy, and ktlint will fight the column alignment —
ship an `.editorconfig` disabling the relevant rules for annotated declarations.

Multiplatform: `tabula-core` is a KMP module (`commonMain` only). The KSP
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
│   ├── tabula-fmt.md            # the formatter's contract (tool not written)
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
│   ├── tabula/                  # core + macro_rules! (single crate, no deps)
│   │   ├── src/{lib,step,cell,table,matrix,machine,delegate,driver}.rs
│   │   ├── src/{export,lint}.rs     # alloc-gated
│   │   └── tests/
│   │       ├── reference_timer.rs   # hand-written; the macro's specification
│   │       ├── timer_matrix.rs      # same machine via the macro; parity tests
│   │       ├── scale.rs             # the measured 8×12 machine
│   │       └── compile_fail/        # one fixture per diagnostic
│   └── tabula-conformance/      # runs spec/conformance; hosts bin/table-diff
│                                 #   (whose renderer is in the lib, so it is
│                                 #   testable)
│
├── tabular-center-kotlin/       # a flake; built by kotlinc directly — no Gradle
│   ├── flake.nix  flake.lock
│   ├── nix/                     # context (pinned kotlinc, JDK), checks, shells,
│   │                             #   apps (.#gradle-lock), and the Maven set for
│   │                             #   KSP: gradle-lock.json + gradle-repo.nix
│   ├── tools/verify             # the Kotlin steps
│   ├── tools/gradle-lock        # writes nix/gradle-lock.json (network)
│   ├── core/dev/tabula/         # Step, Cell, Table, Export, Lint, Driver
│   ├── annotations/dev/tabula/  # @Machine, @Row, @Path, cell markers
│   ├── testing/dev/tabula/testing/
│   ├── codegen/                 # MachineDesc -> String, + support/ and compile_fail/
│   ├── ksp/                     # JVM processor — Gradle, offline via nix/gradle-lock.json
│   ├── test/                    # reference machine + harness
│   ├── conformance/
│   └── compile_fail/
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
│   ├── Sources/Tabula/          # core: Step, Cell, Table, Export, Lint,
│   │                             #   Driver, AsyncDriver, Store, AsyncStore
│   ├── Sources/TabulaTesting/   # the .tbl fixture harness, a separate product
│   ├── Sources/TabulaCodegen/   # the emitter; no SwiftSyntax, so it builds offline
│   ├── Sources/TabulaCodegenCheck/  # emits, then compiles against codegen-support/
│   ├── Sources/TabulaCheck/     # reference machine + harness (no XCTest available)
│   ├── Sources/TabulaConformance/
│   ├── codegen-support/         # what the emitted source is compiled against:
│   │                             #   types, complete impls, and refusals
│   ├── compile_fail/
│   └── macros/                  # separate package: the only one linking
│                                 #   swift-syntax. MachineSyntax + fixtures/;
│                                 #   the .macro target waits in pending/
│
├── examples/                    # outside every workspace, on purpose: the only
│   ├── rust/                    #   place the public API is used from outside
│   ├── kotlin/
│   └── swift-examples/
│
└── tools/
    ├── verify                   # the single definition of green: runs the
    │                             #   cross-language steps, hands the rest to
    │                             #   tabular-center-*/tools/verify by name
    └── docs                     # renders the Pages site; not committed
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
rather than naming them again. `spec/` and `examples/` stay at the root because
all three read them; the language flakes reach them through `self.sourceInfo`,
which is the whole checkout for a flake found in a git subdirectory and for a
relative `path:` input (Nix 2.26 or later).

**The Kotlin library has no build system.** `kotlinc` is driven directly, and
that is not a workaround to be tidied up later: compiling each artifact against
only its declared classpath is what enforces the zero-runtime-dependency rule
by construction rather than by a dependency report. Gradle exists only where
KSP needs it — `tabular-center-kotlin/ksp` and `examples/kotlin/06-generated` —
and resolves offline from `tabular-center-kotlin/nix/gradle-lock.json`. The
Kotlin flake pins `kotlinc` to the same 2.1.20 those builds name, so a nixpkgs
bump cannot move the compiler whose messages the compile-fail fixtures match.

**Examples sit outside every workspace.** They depend on the library by path,
the way a user would. That is the only place the public API is exercised from
outside, and it is where `Driver::run` was found not to compile for any
realistic caller.

### Why a shared `spec/`

The three implementations will drift unless something forces them not to. The
conformance format describes a machine declaratively; each language's harness
generates a machine from it and replays the trace files. A semantic difference
between Rust and Kotlin becomes a red CI check rather than a bug report two
years later.

The diagnostics spec is normative for the same reason: `tabula::row-arity`
should produce recognizably the same message in all three.

---

## 13. `flake.nix`

Four flakes: one per implementation, each pinning its own toolchain, and the
root, which composes them. The root provides the per-language dev shells (the
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
and a bump is made in all four together.

**Swift is checked on Linux, not merely available there.** That was not always
true and the reasons it was not are worth keeping: the then-pinned nixpkgs 25.05
shipped Swift 5.8, below the 5.9 macros require, and its SwiftPM is sensitive to
how the C toolchain is supplied — adding `stdenv.cc` to satisfy the setup-hook
changes swiftc's default target triple and breaks the stdlib lookup.

**Swift therefore comes from a second flake input**, `nixpkgs-swift`, pinned to
`nixos-unstable`. One input for all three toolchains would have meant dragging
Rust and Kotlin — which are working and pinned deliberately — onto unstable to
solve a problem neither of them has. The second input lifts the 5.8 ceiling
that `TabulaMacros` would have hit anyway.

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

`examples/kotlin/06-generated` used to be the second item here. It is not any
more: Gradle resolves from `tabular-center-kotlin/nix/gradle-repo.nix`, a
directory nix assembles from `tabular-center-kotlin/nix/gradle-lock.json` with
one `fetchurl` per artifact, so the annotation processor runs in the sandbox
(`kotlin-ksp`, `kotlin-ksp-compile-fail`, `kotlin-ksp-incremental`). `check-no-nix` still
builds it online, which is the no-nix claim tested rather than asserted.

Every `flake.nix` is a table of contents. Toolchains, shells, checks, apps,
and publication live in the `nix/` beside it, because a flake that grows past a
screen stops being read and starts being copied.

---

## 14. Non-goals and known costs

Stated up front so they are not discovered as surprises.

**N×M explosion.** Six states and eight actions is 48 cells. The static cell
kinds keep most of them one word long, but the count is real. This is the
reason builder DSLs won the market, and it is the cost of the guarantee.

*Measured, on a genuine 8×12 order-lifecycle machine (`tabular-center-rust/tabula/tests/scale.rs`):*

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
- **A realistic machine trips `tabula::ignore-heavy`.** At 78% it crosses the
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
