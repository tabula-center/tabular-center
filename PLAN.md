# tabula — Implementation Plan

Companion to `ARCHITECTURE.md`. Ordered by risk retirement, not by convenience.

---

## Sequencing rationale

Three principles drive the order below.

**Rust first, because it is the cheapest place to be wrong.** `macro_rules!`
has no build-graph cost and the edit-compile loop is seconds. The hardest
unsolved problem in this design is *table syntax that reads like a table and
still parses* — get that wrong and everything downstream inherits it. Rust is
where you can throw away five syntaxes in an afternoon.

**Kotlin second, not Swift.** Kotlin is where the design changed most: the
guarantee moved from `when`-exhaustiveness (weak, `else`-defeatable) to
required-member implementation (strong). That conversion is the central claim of
the whole redesign and it is unproven. Prove it before writing a third
implementation on top of it.

**The conformance spec is written before the second implementation, not after.**
Retrofitting a cross-language spec onto two divergent implementations is a
rewrite. Written between impl 1 and impl 2, it costs a week.

---

## Status

| Phase | State |
|---|---|
| 0 Foundations | **done** |
| 1 Rust core, no macro | **done** |
| 2 `transition_matrix!` | **done** |
| 3 The spec | **done** |
| 4 Kotlin core + KSP | **M2 PASSED**; core done, processor next |
| 5 Swift | **core compiles**; checks converted off XCTest, awaiting a run |
| 6 Composition | **done (Rust and Kotlin)** |
| 7 Effects surface | **done (Rust half)** |
| 8 Introspection & tooling | **done (Rust half)** |
| 9 Runtime / drivers | **done (Rust half)** |

68 tests, 7 compile-fail fixtures, 4 conformance fixtures (28 trace steps),
4 golden matrix snapshots.

### Phase 7: the grammar change, made

`effect Effect;` became `effects Effect { StartClock, StopClock { reason: u32 } }`.
The generator now owns the effect enum, exactly as it owns states and actions,
and everything else followed from that:

- Narrowed effect variant structs, so a handler's payload arrives destructured.
- `Handlers`, one `Perform` bound per variant, plus a `perform` dispatcher.
- `GO!(Idle, StopClock { reason: 0 })` — effects convert through `From`, so the
  bare variant name works and `Effect::StopClock` still does.
- Effect names in `TABLE` normalise to the bare variant, so grids read
  `GO(Idle, StopClock)` rather than carrying a struct literal.

Breaking for every machine, which is why it was held back to its own patch.

### M2: passed

The gate the whole plan hung on. Kotlin 2.1.20 turned out to be reachable
after all — the compiler ships as a GitHub release, and only *Gradle* needs
Maven. Three properties verified, each with a fixture in
`kotlin/compile_fail/`:

1. Omitting a cell fails to compile, with an error that names the cell and
   shows its narrowed argument types. Arguably better than Rust's trait-bound
   error.
2. Adding a state breaks the generated dispatcher — the same free second
   guarantee rustc gives the macro.
3. `else` is not available: the developer's file contains no `when` at all.

Point 3 is the load-bearing one. KSP cannot rewrite code, only generate new
files, so the only way to own the dispatch is to be its sole author — which is
why the matrix lives in annotations. That constraint converts what was
Kotlin's weakest guarantee into one as strong as Rust's.

**Go.** The design is sound in both languages.
Findings from each phase are recorded in its commit message and folded back
into `ARCHITECTURE.md`.

---

## Phase 0 — Foundations

**Exit criterion:** `nix develop` works on Linux and macOS; empty test suites
green in CI for all three languages.

- [x] `flake.nix`: nixpkgs pin, `rust-overlay`, JDK 21, Swift 6
- [x] Per-language dev shells (`.#rust`, `.#kotlin`, `.#swift`) + combined default
- [x] `nix flake check` wired to all three (empty suites for now)
- [x] Repo skeleton per ARCHITECTURE §12
- [x] CI matrix: Linux (Rust, Kotlin), macOS (all three); Swift-on-Linux marked
      `continue-on-error`
- [x] `CONTRIBUTING.md`, license, `.editorconfig` (incl. ktlint alignment
      exemptions for annotated declarations)

**Risk:** Swift toolchain on Linux via nixpkgs is the known-flaky piece. Do not
let it block Phase 0 — pin it, mark it best-effort, move on.

**Outcome:** done. Swift jobs in CI are gated on `hashFiles('swift/Package.swift')`
so they no-op until Phase 5 rather than sitting red.

---

## Phase 1 — Rust core, no macro

**Exit criterion:** a Timer machine written by hand, with a hand-written
`match`, passes its tests. No macro exists yet.

This phase deliberately produces the code the macro will later generate. It
defines the target.

- [x] `Step<S, F>`: `go`, `stay`, `ignored`; `Debug`, `PartialEq`
- [x] `Cell` enum (six kinds) as inert data
- [x] Effect collection shape: `[Option<F>; K]` const-generic, `no_std`-clean
- [x] `#![no_std]` + `alloc` feature gate; verify with a thumbv7 build
- [x] Hand-written Timer: cell trait + dispatcher + `TABLE` const
- [x] Tests: every cell, plus a trace-replay harness

**Deliverable that matters:** the hand-written dispatcher is the macro's
specification. It lives at `rust/tabula/tests/reference_timer.rs` — a test
rather than an example, so `cargo test` keeps it honest — and must keep
building forever.

**Outcome:** done, with one API correction found by Phase 2 (see below):
`Cell::Handle` carries no member name, and `UNREACHABLE` generates no member.
Phase 1 got both wrong, which is precisely what Phase 1 exists to surface
cheaply.

---

## Phase 2 — Rust `transition_matrix!`

**Exit criterion:** the Phase 1 machine, re-expressed as a matrix, produces
byte-equivalent behaviour and its `cargo expand` output is reviewably close to
the hand-written version.

- [x] Grammar: `machine` / `context` / `prototype` / `states` / `actions` /
      `effects` / rows
- [x] Row parsing with positional cells; `$($color:tt)*` capture from prototype
- [x] Static cell kinds: `IGNORE`, `GO!`, `EMIT`
- [x] `HANDLE` → trait method emission with **narrowed argument types**
- [x] `UNREACHABLE` → trap, counted in build output
- [x] Dispatcher emission with **no wildcard arm** (so `rustc` catches missing rows)
- [x] Row-arity validation with a readable error
- [x] `TABLE` const emission
- [x] Payload-free fast path: `[[Cell; M]; N]` + index dispatch
- [x] Color splatting: `async` / `unsafe` / `const` / `extern`, with `$(.await)?`
      at call sites
- [x] Compile-fail suite: every diagnostic has a fixture. **Not `trybuild`** —
      it would be the crate's only dev-dependency. `tools/compile-fail` is 40
      lines of bash driving `rustc` directly and reading a `//~ EXPECT:` line
      from each fixture.

**Highest-risk task in the project:** `macro_rules!` error messages are
notoriously bad when a pattern fails to match. Budget real time for structuring
the macro so arity and unknown-identifier failures produce a comprehensible
message rather than "no rules expected this token." If it cannot be made
tolerable, the fallback is a `compile_error!`-emitting shim arm — decide this
by end of Phase 2, not later.

**Outcome:** resolved, and the fallback was the answer. Every muncher ends in a
catch-all arm emitting `compile_error!` with row and column named. All six
diagnostics verified by fixture. The three findings that cost the most time —
ident concatenation, repetition nesting depth, and macro hygiene — are written
up in the Phase 2 commit and in ARCHITECTURE section 11.0/11.1.

**Do not** start Kotlin until `cargo expand` output has been read end-to-end by
someone who did not write the macro.

---

## Phase 3 — The spec

**Exit criterion:** `spec/` is complete enough that a second implementation
could be written from it without reading the Rust source.

- [ ] `spec/cells.md` — normative semantics of all six cell kinds, including
      the `IGNORE` vs `stay([])` distinction and `UNREACHABLE` trap behaviour
- [x] `spec/diagnostics.md` — error codes and message text, normative across
      languages. Now includes `tabula::missing-row` / `tabula::extra-row`
      (not anticipated) and records that the *missing-implementation* error is
      deliberately **not ours**: it comes from the language compiler, reads
      differently in each, and must not be intercepted or normalized.

- [x] Fixtures: `timer` (payload states, HANDLE, GO with effects),
      `toggle` (payload-free, and the only coverage for EMIT and UNREACHABLE)
- [ ] Fixtures deferred to their own phases: `nested-delegate` (6),
      `effects-never` (7), `payload-hoist` (8)
- [ ] Trace format: `(state, action) → (state, effects)` sequences
- [x] Rust harness passing all fixtures, plus `table-diff`. Verified against
      three classes of deliberately introduced drift: a wrong cell kind, a
      `stay`/`ignored` confusion, and a wrong effect. **Table checking is not
      redundant with trace replay** — several wrong tables produce right
      answers on any one trace, so the generated `TABLE` is compared cell by
      cell as well.
- [x] A fixture with no adapter reports as **skipped**, never as passed.
      Phases 4 and 5 begin with everything skipped and that has to be visible.

---

### Decisions recorded in Phase 3

- **Effect names compare by last path segment.** Rust holds
  `Effect::StopClock` because the macro stringifies the expression it was
  given; Kotlin will hold `F.StopClock`. Qualification is spelling, not
  behaviour.
- **Generated source is never compared.** Rust names cells by trait bound,
  Kotlin and Swift by identifier. Comparing source would encode a
  `macro_rules!` limitation as a cross-language requirement.
- **Diagnostic text is normative only for codes tabula authors.** The
  missing-implementation error belongs to each language's own compiler.

## Phase 4 — Kotlin core + KSP

**Exit criterion:** the Timer example compiles; deleting one `override` fails
the build with a comprehensible message; the developer's source file contains no
`when`.

**4a. Core (KMP, commonMain, zero runtime deps)**
- [ ] `Step<S, F>`, `Cell`
- [ ] Blocking driver + mailbox
- [ ] Suspend driver taking `suspend () -> A` (stdlib `suspend` only, **no**
      `kotlinx.coroutines` dependency — verify with a dependency report check in CI)

**4b. Annotations**
- [ ] `@Machine`, `@Row`, cell markers (`HANDLE`, `IGNORE`, `GO`, `EMIT`,
      `DELEGATE`, `UNREACHABLE`, `EXPAND`)
- [ ] Nested-annotation shape that survives Kotlin's array-of-annotation limits
      — **spike this first**, it is the main unknown in Kotlin

**4c. Code generator** — split so the risky half can be verified without KSP

- [x] `codegen/`: a pure `MachineDesc -> String` emitter. No KSP, no compiler
      plugin, so it is testable here.
- [x] Golden emitted source, `--bless` to accept.
- [x] **The emitted source is compiled**, then a complete implementation and an
      incomplete one are compiled against it. A golden diff alone proves only
      determinism; this proves the output still enforces the guarantee.
- [x] `codegen/Raw.kt`: validation and **every declaration diagnostic**, with
      14 test cases. Moved out of the processor precisely so it could be
      tested; a `RawMachine` round-trips to the same source as the goldens.
- [x] The KSP adapter, ~200 lines of extraction. **Unverified** — it is the
      only file in the repository that has never been run. `ksp/README.md`
      lists four honest guesses at what will need fixing first.
- [ ] One run against Maven to confirm or correct it.

The split is worth keeping after KSP lands. A generator whose logic can only be
exercised through a compiler plugin is a generator nobody refactors.

**4c-old. KSP processor** *(the shape it must emit is fixed by
`kotlin/test/ReferenceTimer.kt` and `codegen/golden/`)*
- [x] Core (`Step`, `Cell`, `Table`, `Export`, `Lint`, `Driver`,
      `SuspendDriver`, annotations), compiled by `kotlinc` with no build system
- [x] Hand-written reference machine — KSP's specification, the exact
      counterpart of `reference_timer.rs`
- [x] `@Row` annotation shape validated with `KClass` cells. **The fallback
      (an external `.tabula` file read from resources) is not needed.**
- [x] Zero runtime dependencies, enforced by construction: with no build system
      there is no classpath but the stdlib. `SuspendDriver` needs only the
      `suspend` keyword, proven by driving it with `kotlin.coroutines`
      intrinsics in `test/RunSuspend.kt`.
- [ ] Resolve sealed hierarchies to ordered variant lists
- [ ] Read the `handle` prototype: `suspend`, annotations, context parameters,
      extension receiver, visibility
- [ ] Emit abstract class: cell members with copied modifiers + narrowed types
- [ ] Emit nested `when` dispatcher, **no `else`**, relying on smart casts
- [ ] Emit `TABLE` companion
- [ ] Diagnostics per `spec/diagnostics.md`, via `KSPLogger.error` with node
      positions
- [ ] Incremental-processing correctness (dependency tracking on sealed
      hierarchies — a change to `S` must reprocess dependent machines)

**4d. Conformance**
- [x] Kotlin harness green on `timer` and `toggle`; `retry` and
      `nested-delegate` report as **skipped**, not passed. Verified to catch
      both table drift and behavioural drift.
- [x] The golden `.grid` files are now genuinely shared: Rust writes them,
      Kotlin reads and never blesses. Two renderers agreeing byte for byte
      covers padding, trimming, and the text of all six cell kinds — the
      details that rot silently.

**Known friction to absorb, not fight:** slower incremental builds; IDE symbol
resolution flaky before first build; ktlint fighting column alignment; wordy
annotation matrices. Document each in the Kotlin README.

**Decision point:** if `@Row` nested annotations prove unworkable, the fallback
is a separate `.tabula` matrix file read by KSP from resources. Evaluate at the
end of 4b — do not carry both.

---

## Phase 5 — Swift core + macro

**Exit criterion:** parity with Kotlin on the conformance suite.

- [ ] `Step`, `Cell`; `Store`, `actor AsyncStore`, `@MainActor @Observable ObservableStore`
- [ ] `@Machine` attached macro (SwiftSyntax, **build-time only** — assert with
      a linked-binary check in CI)
- [ ] Synthesize payload-free `Tag` enums for table indexing
- [ ] Validate `matrix` literal shape at expansion; row-arity diagnostics at
      correct source positions
- [ ] Prototype capture: `async`, `throws`, `@MainActor`, `@Sendable`, isolation
- [ ] Emit protocol requirements with narrowed types
- [ ] Emit exhaustive `switch (state, action)` with payload binding, **no `default:`**
- [ ] Conformance harness green

**Risk:** macro diagnostics at accurate source locations inside a dictionary
literal are fiddly. Accept row-level rather than cell-level positions in v1 if
needed; note it in `spec/diagnostics.md`.

---

## Phase 6 — Composition

**Exit criterion:** `nested-delegate` fixture green in all three languages;
color-mismatch is a build error in all three.

- [x] Nest / Alternate / Translate — **not three APIs.** They are the five
      methods of one `Delegate` trait: `child_state` + `embed` are the lens
      (nest/alternate), `to_child` is the action prism, `lift` relabels
      effects, `child_ctx` plumbs context. Nest and alternate collapsed into
      one because a `DELEGATE` cell lives on a *row*, and the row already is
      the parent state case — the distinction only mattered when composition
      was an operator over whole machines.
- [x] `DELEGATE!(child_module)` cell in the Rust generator
- [x] `delegate_lens!` helper for the common shape (payload field holds the
      child state, parent context contains the child's). `to_child` and `lift`
      stay hand-written: those two encode real decisions, and deriving them
      would mean guessing.
- [x] Parent rows still list every column — asserted in `composition.rs`
- [x] **The composition property, proven:** `compile_fail/child_hole_breaks_parent.rs`
      removes a cell from the *child* and the error appears at a call to the
      *parent's* `step`. This is what `DELEGATE` buys over `HANDLE` — a
      hand-written `HANDLE` body is free to ignore the child, so no bound
      propagates and the hole goes unnoticed.
- [x] `nested-delegate` and `retry` conformance fixtures. The child is
      conformant **on its own**: being composed does not change it, and a child
      that only works inside its parent is not a reusable machine.
- [x] One-way color flow — enforced **by construction** in Rust: a colored
      child inside a colorless parent emits `.await` in a non-`async` `fn`,
      which rustc rejects. No check to write and nothing to circumvent. Kotlin
      and Swift will need the explicit `tabula::color-mismatch` diagnostic.
- [x] Kotlin half. `interface Cells : retry.Cells` — interfaces are Kotlin's
      trait bounds — with `compile_fail/child_hole_breaks_parent.kt` proving the
      property.
- [x] All four conformance fixtures now pass in **both** languages, with
      matching lint output. Nothing is skipped.
- [ ] Swift half

---

## Phase 7 — Effects surface

- [x] Effects are generated, like states and actions. **This was the whole
      blocker**: the generator can only emit one required member per variant if
      it knows the variants, and naming a hand-written enum left it nothing to
      iterate.
- [x] `effects Effect { }` — an uninhabited enum, a machine with no effects.
      Supported, not degraded.
- [x] One required member per effect variant, narrowed payloads, returning an
      optional follow-up action
- [x] Follow-up actions route through the mailbox, never re-entering `step`
      (Phase 9a's driver; `effects.rs` tests the two halves meeting)
- [x] `compile_fail/missing_perform_impl.rs`: adding an effect breaks every
      handler's build

---

## Phase 8 — Introspection & tooling

- [x] Mermaid, DOT, and aligned-grid export from `TABLE` (Rust)
- [x] `lint` module: six findings, all warnings. Two rules learned writing it —
      a lint that fires on healthy machines gets turned off, and two warnings
      for one problem is noise. See `spec/diagnostics.md`.
- [x] Coverage report by cell kind
- [x] Golden matrix snapshots (`<name>.grid`, `--bless` to accept). A PR that
      changes behaviour now shows a **table** diff, which is the artifact worth
      reviewing.
- [ ] PlantUML export
- [x] Payload-hoist warning, in both languages. The field list is emitted as a
      separate `PAYLOADS` const rather than added to `Table`: the table is the
      matrix, this is metadata about the states, and keeping them apart meant
      adding it broke no existing `Table` literal.

Ship export early if you want adopters. It is the most demoable feature and
falls out of `TABLE` almost for free.

---

## Phase 9a — Driver and mailbox

- [x] `Driver<S, A, Q>`: fixed-capacity mailbox, `no_std`, no allocator
- [x] **`step` is never re-entered** — `run` refuses to run inside itself
- [x] **Follow-up actions are queued, never recursed.** An effect handler
      returns an action as *data*; it is handed no way back into `step`.
- [x] Outcome applied before effects are performed, so a handler that enqueues
      an action sees the post-transition state. The reverse order would make
      `go(X).emit(E)` mean "perform E while still in the old state", which is
      not what a cell author means.
- [x] Overflow names its capacity rather than growing. An unbounded mailbox
      just moves the failure somewhere harder to see.

The handler is a closure, not a trait: `step` needs the cell object and the
context, which the caller already has. That keeps `Driver` free of the
machine's four type parameters and, more importantly, keeps it **colorless** —
an `async` caller writes an `async` loop around `pump` rather than asking this
type to be generic over an effect system it cannot abstract over.

## Phase 9b — Rendering surface (optional, gated)

- [ ] Second prototype for view derivation (`S -> UI`)
- [ ] One required member per state, narrowed payloads
- [ ] Kotlin: `@Composable` rendering cells
- [ ] Swift: SwiftUI `@ViewBuilder` cells
- [ ] Warning when `@Composable` appears on a *transition* prototype (Compose
      runtime may skip / restart / discard — a real correctness hazard, not style)

---

## Phase 10 — Release

- [ ] README leading with the composition property and the one guarantee
- [ ] Migration guide: from Tinder StateMachine, KStateMachine, Spring
      Statemachine, TCA
- [ ] Publish: crates.io, Maven Central, Swift Package Index
- [ ] Semantic-versioning policy — specifically, what counts as a breaking
      change to *generated* code
- [ ] Benchmarks vs. hand-written dispatch (the honest claim is "identical after
      monomorphization"; verify it)

---

### Findings from the examples

Writing the four worked examples immediately found an API bug that none of the
unit tests could:

- **`Driver::run` did not compile for any realistic caller.** Both closures
  captured the cell object and the context, which is `cannot borrow as mutable
  more than once`. Every driver test had passed because none of them needed
  `perform` to touch the same state as `step`. Both closures now take `&mut Env`.
- **Kotlin has no such problem**, so its driver keeps the simpler capturing
  form. A difference in the *API* rather than the semantics, and the right call
  is to let each language have the shape that works there.

That is the argument for examples over more unit tests: a unit test exercises
the API the way its author already imagined it.

## Cross-cutting, every phase

- [x] **One definition of green.** `tools/verify` is it; `nix flake check` runs
      its steps in a sandbox and CI runs the flake. Any new check goes in
      `tools/verify`, never directly in the workflow.

      This was learned the hard way. Three lints reached CI because the
      workflow, the flake, and the local loop each checked slightly different
      things — most recently an unused import in a *test* file, which
      `cargo build` never compiles, so it passed locally and failed clippy in
      CI. `--all-targets` is load-bearing.
- [ ] Any behavioural change lands in `spec/conformance` before any implementation
- [ ] Every diagnostic gets a UI test (`trybuild` / KSP compile-testing /
      swift-macro-testing)
- [ ] Docs updated in the same PR
- [ ] All three implementations green before merge to `main`

---

## Milestones

| M | Content | Meaning |
|---|---|---|
| **M0** | Phases 0–2 | Rust works. Design is validated in its friendliest language. |
| **M1** | Phase 3 | Spec exists. Divergence becomes a CI failure. |
| **M2** | Phase 4 | **PASSED.** Kotlin's guarantee is as strong as Rust's. |
| **M3** | Phase 5 | Three languages at parity. |
| **M4** | Phases 6–7 | Composition and effects. The library is now differentiated. |
| **M5** | Phases 8–10 | Tooling, docs, published. |

**M2 is the milestone that decides whether this project is worth finishing.**
If required-member enforcement does not deliver a clean developer experience in
Kotlin — if annotation matrices are too ugly, if KSP incrementality is too
broken, if the generated abstract class is awkward to implement — that is the
signal to stop and reconsider, not to push on to Swift. Everything before M2 is
comparatively cheap; everything after it assumes M2 held.

---

## Top risks

| Risk | Phase | Mitigation |
|---|---|---|
| ~~`macro_rules!` diagnostics are unusable~~ | 2 | **Retired.** `compile_error!` catch-all arms; 6/6 fixtures pass. |
| ~~Kotlin nested annotations can't express the matrix~~ | 4b | **Retired.** `@Row(S.Idle::class, [CellSpec(...)])` compiles with `KClass` cells. No fallback needed. |
| KSP incremental processing misses sealed-hierarchy changes | 4c | Explicit dependency tracking + a regression test that edits `S` |
| Swift macro diagnostics land on wrong source lines | 5 | Accept row-level positions in v1, document in spec |
| Three implementations drift | 3+ | Conformance suite gates merges. Phase 2 proved this must compare **behaviour**, not generated source: Rust names cells by trait bound, Kotlin and Swift by identifier. |
| ~~N×M cell count makes real machines unpleasant~~ | any | **Measured** on a genuine 8×12 order machine: 96 cells, 78% `IGNORE`, **9 members to write**. Two costs found and recorded — a raised `recursion_limit` past ~7×10, and `ignore-heavy` firing on a machine that arguably is two machines. See `rust/tabula/tests/scale.rs`. |

---

### Findings from Phase 6

- **`Cells` and `Marker` are reserved names** in a machine's module. The
  generator emits both so a parent can reach a child's bound bundle and marker
  type by path, since it cannot build the identifiers. Machines already needed
  their own module (narrowed structs collide otherwise); this makes it a hard
  requirement rather than a convention.
- **Narrowed structs must not derive `Default`.** It imposed `Default` on
  every payload type, and a state whose payload is a child machine's state
  rarely has one. Found by the composition test failing to compile.
- **`embed` returns the full parent state**, not the narrowed variant, because
  a child reaching its terminal state is usually the parent's cue to leave.
- **`to_child` returning `None` reports `Ignored`, not `Stay`.** A parent
  action the child's alphabet does not contain was not handled, and the
  distinction is load-bearing for the reachability linter.
- **The trace format's `from` needed payload fields**, symmetric with `go`.
  It silently dropped them, which started a composition trace in the wrong
  child state and produced a passing-looking wrong answer.

### Findings from Phase 6's Kotlin half

- **A Kotlin class may implement a generic interface at only one type
  argument.** `Cells : Delegate<A.Run>, Delegate<A.Tick>` is
  `type parameter 'AV' has inconsistent values`. Rust's `Delegate<M, SV, AV, CM>`
  therefore cannot be transcribed; Kotlin emits one named member per delegate
  cell. That is the better form regardless — Rust only reaches for a generic
  trait because `macro_rules!` cannot concatenate identifiers.
- **The cell surface had to become an interface**, not abstract members on a
  class. A class extends one parent, so abstract members would have capped
  composition at a single child. `abstract class Machine : Cells` remains as a
  convenience wrapper.
- **The four lens members are per child, not per cell.** A second delegate cell
  to the same child reuses `childState`, `embed`, `lift`, and `childCtx`; only
  the action prism is per cell.

### The Swift toolchain, so far

Three rounds of nixpkgs packaging, each revealing the next missing piece:

1. `NIX_CC: unbound variable` — the setup-hook needs it.
2. `could not find module '_Concurrency'` — caused by *fixing* the first with
   `stdenv.cc`, which changed swiftc's default target triple. Reads like a
   missing module; is a triple mismatch.
3. `toolchain is invalid: could not find ar` — SwiftPM needs `binutils`.

None of it was our code. Round five reached — and passed — a compile of the
library; the remaining work was replacing XCTest, which nixpkgs' Swift does not
ship, with the same dependency-free harness the Kotlin side uses.
Swift now comes from its own flake input on `nixos-unstable`, which also lifts
the 5.8 ceiling that `TabulaMacros` would have hit anyway.

If the toolchain keeps failing, gate the *check* to Darwin and leave
`nix develop .#swift` for anyone with a working one. `nix flake check` should
not fail on a packaging problem in a dependency we do not control.

### Cross-language convergence

Findings now flow both ways, which is the return on implementing twice:

- **Rust -> Kotlin:** the normalisation-order bug in the conformance harness
  (strip the payload before splitting the path). Kotlin's `toString` produces
  the same shape and would have hit it identically.
- **Kotlin -> Rust:** the delegate lens is per *child*, not per cell. Rust's
  five-method `Delegate` duplicated four bodies for every extra delegate cell
  to the same child; it is now `Lens` (per child) plus `Delegate` (per cell,
  one method). Verified the new `Lens` bound is load-bearing: removing the impl
  fails with `the trait bound Impl: Lens<Job, Retrying, Retry> is not satisfied`.

### Findings from Phase 7

- **Normalisation order matters.** The conformance harness reduces an effect
  rendering to its bare variant name, and `{:?}` on a generated newtype enum
  produces `StopClock(StopClock { reason: 0 })`. Splitting on the path
  separator first yields ` 0 }`, because the payload contains a colon. The
  payload must be stripped before the path is split.
- **Metavariable collision.** `$ef` already meant "an effect expression" inside
  `GO!`; threading the effect *type* under the same name silently changed what
  the arms matched. Renamed to `$et`. `macro_rules!` gives no warning for this.
- **Effects convert through `From`**, so `GO!(Idle, StopClock)` and
  `GO!(Idle, Effect::StopClock)` both compile. The blanket `impl<T> From<T> for T`
  makes the qualified spelling keep working for free.

## Explicitly deferred

- **Hierarchy / `INHERIT` cells.** The obvious answer to N×M explosion, and it
  reintroduces coverage satisfied by something other than explicit authorship.
  v2, after the core guarantee has been proven in production use.
- **Parallel regions / orthogonal states.** Out of scope entirely.
- **Multi-color generation from one declaration.** Ruled out by prototype-driven
  codegen; two colors means two declarations.
- **Runtime matrix construction.** Contradicts the premise.
- **`dyn`-compatible Rust traits by default.** Behind a feature flag only;
  AFIT is not `dyn`-safe and we monomorphize anyway.
