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
| 4 Kotlin core + KSP | **blocked — see below** |
| 5 Swift | not started |
| 6 Composition | **done (Rust half)** |
| 7+ | not started |

54 tests, 7 compile-fail fixtures, 4 conformance fixtures (28 trace steps).

### Why Phase 6 landed before Phase 4

Phase 4 requires a Kotlin 2.x toolchain, KSP, and Gradle with Maven access.
None was available in the environment doing this work, and Kotlin 1.3 — the
only version obtainable — predates sealed interfaces, context parameters, and
KSP entirely. Shipping unverified Kotlin would be worse than shipping none:
the whole point of M2 is finding out whether required-member enforcement
*feels* right, and that cannot be assessed from source that has never
compiled.

Phase 6 was done instead because it was verifiable and because its vocabulary
is what Kotlin will copy — which is the plan's own stated reason for doing
Rust first. **M2 remains the stop-or-go gate and is still unproven.**
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

**4c. KSP processor**
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
- [ ] Kotlin harness green on all Phase 3 fixtures

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
- [ ] Kotlin and Swift halves (blocked on Phase 4)

---

## Phase 7 — Effects surface

- [ ] `effects Never` / `Nothing` mode, fully supported (not degraded)
- [ ] Effect-handler prototype → one required member per effect variant, with
      narrowed payloads, returning optional follow-up action
- [ ] Follow-up actions route through the mailbox, never re-entering `step`
- [ ] Test: adding an effect variant breaks every handler's build

---

## Phase 8 — Introspection & tooling

- [ ] Mermaid, DOT, PlantUML export from `TABLE` (all three)
- [ ] Reachability check → generated test, **warning not error**
- [ ] Coverage report by cell kind, surfaced in build output
- [ ] `tools/table-diff` — golden matrix snapshots, readable diffs in review
- [ ] Payload-hoist warning (same name+type in ≥3 payloads)

Ship export early if you want adopters. It is the most demoable feature and
falls out of `TABLE` almost for free.

---

## Phase 9 — Rendering surface (optional, gated)

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

## Cross-cutting, every phase

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
| **M2** | Phase 4 | **The critical proof.** Kotlin's guarantee is as strong as Rust's. |
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
| Kotlin nested annotations can't express the matrix | 4b | Spike first; fallback to external `.tabula` file read from resources |
| KSP incremental processing misses sealed-hierarchy changes | 4c | Explicit dependency tracking + a regression test that edits `S` |
| Swift macro diagnostics land on wrong source lines | 5 | Accept row-level positions in v1, document in spec |
| Three implementations drift | 3+ | Conformance suite gates merges. Phase 2 proved this must compare **behaviour**, not generated source: Rust names cells by trait bound, Kotlin and Swift by identifier. |
| N×M cell count makes real machines unpleasant | any | Static cell kinds keep most cells one word; measure on a genuine 8×12 machine before M4 |

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
