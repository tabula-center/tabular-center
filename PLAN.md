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
| 4 Kotlin core + KSP | **M2 PASSED**; core, codegen, conformance done. KSP adapter written, never run |
| 5 Swift | core, reference, compile-fail, testing, conformance, examples, **codegen**; macros to come |
| 6 Composition | **done (all three)** |
| 7 Effects surface | **done (Rust half)** |
| 8 Introspection & tooling | **done (Rust half)** |
| 9 Runtime / drivers | **done (Rust half)** |

95 Rust tests; 18 compile-fail fixtures (9 Rust, 4 Kotlin, 1 Kotlin-codegen,
4 Swift); 5 conformance fixtures (34 trace steps); 5 golden `.grid`, 5 `.lint`,
5 `.puml` and 5 `.cov` snapshots.

These counts are checked against the tree, not remembered. Regenerate with:

```
grep -rho '#\[test\]' rust/ | wc -l
ls rust/tabula/tests/compile_fail/*.rs | grep -vc _prelude
grep -h '=>' spec/conformance/traces/*.trace | wc -l
```

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

## Open decisions

Three items are blocked on a choice rather than on work. Each is written out
here because the reasoning lives in commit messages otherwise, and a decision
nobody can find gets remade badly.

### 1. `payload-hoist` — decided: canonicalise type names

**Chosen.** `spec/diagnostics.md` now carries a normative type vocabulary
(`int`, `float`, `bool`, `string`, `char`), and each implementation maps its own
spellings onto it. Unrecognised names pass through unchanged, which is the rule
for user types and lets the table grow without a migration.

The decision it beat was dropping the type from the message, which was cheaper
and would have lost the distinction the lint exists to draw: it compares name
*and* type precisely so `count: u32` and `count: String` are two ideas sharing
a word.

Canonicalisation happens **before the comparison**, not only before the
message. Rust grouping `u32` separately from `usize` while Kotlin groups `Int`
with `Long` would produce different findings from the same machine — which is
the problem, not a detail of the fix. A side effect worth naming: `u32` and
`usize` in three states now fire as one finding where before they were two
groups of two and neither reached the threshold. That is the lint being right,
since its suggestion is *this field belongs to the machine rather than to any
one state* and that holds at every width.

- [x] Vocabulary in `spec/diagnostics.md`
- [x] `canonical_type` / `canonicalType` in all three lints, with tests. Kotlin
      had **no** `payload-hoist` tests at all before this — Rust and Swift had
      three each — which is how a lint ends up agreeing by coincidence.
- [ ] The `payload-hoist` fixture itself, now unblocked

### 2. The Swift tools-version floor — decided: 5.9

**Chosen.** `Package.swift` declares `swift-tools-version: 5.9`, raised once
rather than twice: `@Observable` and macros both need it, so `ObservableStore`
and `TabulaMacros` were one decision. The pinned toolchain is 5.10.1, so the
manifest sits below it rather than at it.

**No `platforms:` clause**, which is the half worth keeping. A deployment
target in the manifest is a floor for every consumer; someone using `Store` on
an older OS should not pay for a type they never import. `ObservableStore`
carries `@available(macOS 14, iOS 17, …)` instead, and sits behind
`#if canImport(Observation)` so a toolchain without that module yields a
package missing one type rather than one that does not build — the Linux path
is best-effort for exactly this class of reason.

**Darwin only, and written without `@Observable`.** Two weaker guards were
tried first, and each failed one stage later than the last:

1. `#if canImport(Observation)` — the module is present on the pinned Linux
   toolchain and `@Observable` still fails to resolve. A module says nothing
   about whether macro plugins load.
2. Dropping the macro for a hand-written `ObservationRegistrar` — compiles,
   links, and the binary dies on startup with
   `libswiftObservation.so: undefined symbol`. Present, importable, broken.

The guard the type actually wants is `os(macOS) || os(iOS) || …`, which is not
a concession: `ObservableStore` exists to be watched by SwiftUI, and a Linux
build has nothing to observe it with. The hand-written registrar is kept
anyway — a library asking the toolchain to load macro plugins is asking for
something it does not need.

The lesson is one this repository keeps relearning in new costumes: a guard
that answers a question *adjacent* to the one being asked reports green until
the moment it matters. `canImport` for a macro is the same mistake as
empty-stderr for an exit status.

- [x] `swift-tools-version: 5.9`
- [x] `@MainActor` `ObservableStore`, with checks — conforming to
      `Observable` by hand rather than via the macro, which the Linux
      toolchain lacks
- [ ] `TabulaMacros` — the floor is no longer what blocks it; the swift-syntax
      packaging question in the backlog is

### 3. Examples are projects, not modules — in progress

Each example is becoming a complete project: own manifest, own dependency line
on tabula, tests in their own directory rather than a `mod tests` at the bottom
of the implementation. An example is read as a template, and a template that
puts its tests where a real project would not is teaching the wrong thing.

The reason it is worth the churn is **configuration coverage**. Four modules in
one crate share one set of features, one edition, one shape. Four projects do
not, so the set can be graded from simple to awkward and each corner gets an
owner.

- [x] Rust: a workspace of four member crates. **It found a real bug on its
      first build**, which is the argument for the whole restructure: the macro
      emitted `PAYLOADS: &$crate::lint::Payloads` for every machine while
      `lint` is gated on `alloc`, so *no machine had ever compiled with
      `--no-default-features`*. The library's own `no-std` check builds
      `-p tabula` without features and compiles no machine, so it could not see
      it. A graded set of example projects is how a library gets a consumer for
      each of its configurations.
- [x] Rust: four member crates. `traffic-light` is `#![no_std]`
      on tabula with `default-features = false`; `timer` takes the defaults and
      uses export and lint; `retry` adds a **binary**, so the driver is watched
      and not only asserted on; `login` holds two machines. `tools/verify`
      builds `traffic-light` alone as well as with the workspace, because cargo
      unifies features across the members it builds and the `no_std` claim is
      otherwise never tested.
- [x] Kotlin: four projects, each `kotlinc`-compiled on its own, tests compiled
      against the example's output rather than alongside it, and each run. The
      configuration axis is the **classpath**: `01-traffic-light` builds against
      `core` alone. A suspend-driver example is still missing — `03-retry` uses
      the blocking driver — and that is the next Kotlin gap rather than part of
      the restructure.
- [x] Swift: one executable target per example, each with its own dependency
      line, each built and run separately. **Weaker than the other two on
      purpose**: the checks live beside the implementation rather than in a
      separate module, because the example types are not `public` and making
      them so would be a sweep across every example for the harness's benefit
      rather than a reader's. Worth revisiting if the examples ever become a
      published package.
- [x] Swift `ObservableCounter`: the `ObservableStore` example, and the only
      one in the set that can report **skip**. Its machine is portable and
      checked everywhere; only the store is gated. A check that passes where a
      feature is absent claims the feature works, and one that fails there
      claims the build is broken — saying `skip` out loud is the honest third
      option, and the same call `tools/verify` makes for a missing toolchain.
- [x] Kotlin `05-suspend`: a machine whose `step` suspends, driven by
      `SuspendDriver`. Built against `core` **alone**, which demonstrates the
      zero-runtime-dependency rule instead of asserting it — if the suspending
      driver needed `kotlinx.coroutines`, the example would not compile.
- [x] Swift `SpecCheck`: the only example that imports `TabulaTesting`. It
      parses a `.tbl` fixture written inline and diffs it against the machine's
      `TABLE`, in both directions — matching, and then with one cell changed,
      because a check that has never failed is a check nobody has tested. That
      product had shipped in the manifest without a single consumer outside the
      library.

### 4. The KSP adapter has never run

`kotlin/ksp/` is the only code in the repository that has never executed —
there is no Gradle, and KSP is a Maven artifact this environment cannot reach.
`kotlin/ksp/README.md` records what will break first, re-read against the code
rather than remembered. The headline: `getDeclaredFunctions` cannot compile as
written — the shim calls a KSP *extension* by fully-qualified name with the
receiver as an argument, which is not Kotlin. Expect the first failure there,
before anything runs at all. One of the four original predictions had already
been fixed and was removed.

`build.gradle.kts` got the same read: it declared the generator with
`implementation(files("../codegen"))`, which puts a path on the classpath as
*class* files while that directory holds sources, so every `import codegen.*`
would have failed. Now compiled as sources with the CLI, the golden-diff suite
and the compile-fail fixtures excluded.

One Maven run settles the rest. The generator itself is split out and tested
without KSP, so what is unverified is the adapter, not the logic.

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
- [x] `EMIT!()` rejected as `tabula::empty-emit`. Found by the audit, not by
      the conformance suite, which cannot find this class of bug: it compares
      behaviour, and no fixture writes a cell the spec forbids. Kotlin and
      Swift had rejected it since their generators were written; Rust expanded
      it to `Step::stay()`.
- [x] A compile-fail fixture passes only if the compiler *refused* it. All four
      loops used to infer that from empty stderr, which is a different
      question: a fixture compiling with a warning fell through to the message
      match, and a warning containing the expected text would have been
      reported green. Kotlin warns about unused parameters by default and the
      EXPECT lines name members, so the two were not far apart.
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

- [x] `spec/cells.md` — normative semantics of all six cell kinds, including
      the `IGNORE` vs `stay([])` distinction and `UNREACHABLE` trap behaviour.
      Written last, from three working implementations rather than from the
      design, which is why it can state the trap message and the two
      serialised effect-list spellings as normative facts instead of
      intentions. `EXPAND` is documented there as a *row* directive and
      explicitly not a cell kind — it never reaches `TABLE`.
- [x] `spec/diagnostics.md` — error codes and message text, normative across
      languages. Now includes `tabula::missing-row` / `tabula::extra-row`
      (not anticipated) and records that the *missing-implementation* error is
      deliberately **not ours**: it comes from the language compiler, reads
      differently in each, and must not be intercepted or normalized.

- [x] Fixtures: `timer` (payload states, HANDLE, GO with effects),
      `toggle` (payload-free, and the only coverage for EMIT and UNREACHABLE)
- [x] Fixture deferred to its own phase, and landed there: `nested-delegate`
      (Phase 6), with `retry` alongside it as the child in its own right
- [x] `effects-never` (Phase 7's fixture), green in all three languages. A
      machine with an uninhabited effect enum, which is interesting for what it
      removes: with no effect to name, `EMIT` cannot be written in it at all,
      because an empty one is `tabula::empty-emit`. It also pins the
      reachability gate — `Open` is reached only from a `HANDLE` cell, so the
      coverage report must stay silent about its missing static entry
- [ ] Fixture still outstanding: `payload-hoist`, and the reason is **not** the
      one recorded here before. Every implementation already has both the lint
      and a `Payloads` type; the adapters now supply them. The blocker is that
      the lint prints the field's *type*, which each language spells itself —
      `u32`, `Long`, `Int` for one field — so a shared byte-for-byte `.lint`
      golden is impossible. Picking a type the three spell alike does not work
      either: `String` is the only candidate, and generated state enums derive
      `Copy`, so a Rust machine cannot hold one. `spec/diagnostics.md` lists
      the three ways out and why none is obviously right
- [x] Trace format: `(state, action) → (state, effects)` sequences, specified
      in `spec/conformance/README.md` and parsed by all three harnesses
- [x] Rust harness passing all fixtures, plus `table-diff` — which was
      compiled by `clippy --all-targets` and executed by nothing until the
      audit went back through. Its `spec_grid` is a hand-copy of `to_grid`'s
      layout and lived in a binary, where no test can reach it; it is now in
      the library, asserted against the `.grid` goldens on every fixture, and
      smoke-run by `tools/verify`. It had also been rendering effect lists in
      the `.tbl` spelling, so a cell with two effects would have produced a
      grid that disagreed with the generated one in both text and column
      width, in the one tool whose entire output is that comparison. Verified against
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
- [x] `Step<S, F>`, `Cell`
- [x] Blocking driver + mailbox
- [x] Suspend driver taking `suspend () -> A` (stdlib `suspend` only, **no**
      `kotlinx.coroutines` dependency). Enforced by construction rather than by
      a dependency report: with no build system there is no classpath but the
      stdlib. The report check is wired up but gated on `has.kotlinGradle`, so
      it stays dormant until Gradle can resolve.
- [x] `SuspendDriver` exercised. It was not, until after Swift's `AsyncDriver`
      turned out to have the same gap — the blocking driver had checks from the
      day it was written and its twin had none. Both sides now assert the two
      colors report identical `Progress` for identical input, which is the
      property the duplication actually threatens.

**4b. Annotations**
- [x] `@Machine`, `@Row`, cell markers (`HANDLE`, `IGNORE`, `GO`, `EMIT`,
      `DELEGATE`, `UNREACHABLE`, `EXPAND`)
- [x] Nested-annotation shape that survives Kotlin's array-of-annotation limits.
      Spiked first, as planned, and it held: `@Row(S.Idle::class, [CellSpec(...)])`
      compiles with `KClass` cells. The `.tabula`-file fallback was not needed
      and is not carried.

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

**Exit criterion:** parity with Kotlin on the conformance suite. **Met** — all
four fixtures pass, with the same golden `.grid` and `.lint` files.

- [x] `Step`, `Cell`, `Table`, `Export`, `Lint`, `Driver`, testing harness
- [x] Reference machine and compile-fail suite, the counterparts of
      `reference_timer.rs` and `kotlin/compile_fail/`
- [x] `Sources/TabulaCodegen`: the same `MachineDesc -> String` split Kotlin
      took, with a golden diff and 13 declaration diagnostics. Split for the
      same reason and it paid the same way — the generator's logic is testable
      without the macro that does not exist yet.
- [x] `Store` and `actor AsyncStore`. A `Driver` takes its two closures on
      every call, which is right for a driver and wrong for a caller who has
      exactly one machine; a `Store` binds them once. `AsyncStore` is an actor
      rather than a lock, because serialized access to one piece of mutable
      state is exactly what an actor is
- [x] `@MainActor ObservableStore`. `Store` was what it wraps, and
      nothing in `Store` changed when it landed. Its `state` is a **mirror**
      rather than a computed forward to the driver: `@Observable` tracks stored
      properties, so a computed `{ store.state }` would be invisible to it and
      a SwiftUI view reading it would subscribe to nothing and never update.
      The copy is confined to this one type.
- [x] First coverage for `AsyncDriver`, which had none. Sixty lines of
      duplicated loop, documented in `swift/README.md`, run by nothing. The
      check asserts the two colors report identical `Progress` for identical
      input, since that is the property duplication threatens
- [ ] `@Machine` attached macro (SwiftSyntax, **build-time only** — assert with
      a linked-binary check in CI). Blocked on the swift-syntax packaging
      decision; see the backlog entry below.
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
- [x] Swift half. `protocol JobCells: RetryCells` — protocols are Swift's trait
      bounds — with `compile_fail/child_hole_breaks_parent.swift` proving the
      property and the `nested-delegate` fixture proving the behaviour.
      **All four conformance fixtures now pass in all three languages.**

---

## Phase 7 — Effects surface

- [x] Effects are generated, like states and actions. **This was the whole
      blocker**: the generator can only emit one required member per variant if
      it knows the variants, and naming a hand-written enum left it nothing to
      iterate.
- [x] `effects Effect { }` — an uninhabited enum, a machine with no effects.
      Supported, not degraded. Now also a shared fixture, `effects-never`, so
      the mode is exercised in all three languages rather than in one Rust
      unit test.
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
- [x] Coverage report by cell kind. Now in all three languages with a `.cov`
      golden. It was the last output rendered in one language and compared by
      nothing, and in that state it had drifted from the lint on two rules:
      warning on a single deliberate `UNREACHABLE`, and reporting reachability
      without the fully-static gate. Both thresholds now come from the lint's
      constants rather than from a copy of them.
- [x] Golden matrix snapshots (`<name>.grid`, `--bless` to accept). A PR that
      changes behaviour now shows a **table** diff, which is the artifact worth
      reviewing.
- [x] PlantUML export — and, getting there, **DOT and PlantUML in Kotlin and
      Swift**, which had only grid and mermaid. Export parity was broken in
      both directions and nothing said so.
- [x] All three diagram formats share one edge walk, per language. Writing the
      third renderer is what surfaced the finding below; three independent
      walks would have made it three ways to drift instead of one.
- [x] Payload-hoist warning, in both languages. The field list is emitted as a
      separate `PAYLOADS` const rather than added to `Table`: the table is the
      matrix, this is metadata about the states, and keeping them apart meant
      adding it broke no existing `Table` literal.

Ship export early if you want adopters. It is the most demoable feature and
falls out of `TABLE` almost for free.

### Findings from Phase 8's PlantUML patch

- **Mermaid output had already diverged, and no check could see it.** Rust
  emitted every `GO` edge and *then* every self-loop; Kotlin and Swift
  interleaved them in cell order. Same edge set, different line order, three
  implementations that are supposed to agree. `.grid` and `.lint` have golden
  files and the diagrams do not, so nothing compared them. Unified on
  row-major — the order the matrix is read in — before adding a third format
  on top of the disagreement.
- **The general lesson is about what conformance covers, not about mermaid.**
  Two gaps have now been found in two patches, and both sit in the same blind
  spot: `empty-emit` was behaviour no fixture exercises, this was output no
  golden compares. The suite is good at what it checks. The next question
  worth asking is what *else* is uncompared — the coverage report is the
  obvious remaining answer.
- **A golden `.puml` is the fix.** Landed: `<name>.puml` joins `<name>.grid`
  and `<name>.lint`, written by Rust and read by the other two. One diagram
  format is enough — all three come off the same walk, so pinning one pins the
  order.

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

### Findings from the audit pass

Thirteen patches, five real defects. Worth recording together, because they
were not five unrelated bugs — they were one blind spot found five times.

| Defect | What had no second opinion |
|---|---|
| Rust accepted `EMIT!()` while Kotlin and Swift rejected it | Behaviour no fixture exercises. The conformance suite compares behaviour, and no fixture writes a cell the spec forbids. |
| Rust's mermaid ordered edges differently from Kotlin's and Swift's | Output no golden compares. `.grid` and `.lint` had goldens; diagrams had none. |
| The coverage report warned on a single deliberate `UNREACHABLE`, and reported reachability without the fully-static gate | Output only one language produced. Its thresholds were a *copy* of the lint's rules rather than the lint's rules. |
| `AsyncDriver` (Swift) and `SuspendDriver` (Kotlin) were run by nothing | A hand-copied loop. In both languages the blocking driver was exercised from the day it was written and its colored twin was not. |
| `table-diff` rendered effect lists in the `.tbl` spelling while the grid it is compared against uses the `.grid` spelling | A hand-copied renderer living in a binary, where no test can reach it. |

And the harness that checks all of the above had the same shape of defect: all
four compile-fail loops decided whether a fixture had been rejected by asking
whether stderr was empty, which is a proxy for the exit status with nothing
comparing the proxy to the answer.

None of these was a wrong algorithm. Every one was something that existed in
one place and was compared against nothing. The suite is well built for what it
checks; the question that kept paying was **what is uncompared**, not what is
unchecked.

By that test the tree is now covered for renderers, reports, drivers, goldens
and the compile-fail harness. What remains deliberately uncompared is generated
*source* — Rust names cells by trait bound and the other two by identifier, so
there is nothing to compare, and the per-language compile-fail suites are the
substitute. Anyone hunting the next defect should start somewhere else.

## Backlog — `TabulaMacros`, and the swift-syntax problem

The Swift generator's logic is done and testable (`Sources/TabulaCodegen`,
13 diagnostics plus a golden diff). What is left is the macro that parses syntax
into a `RawMachine` — and one decision that has to come first.

**A Swift macro implementation must link swift-syntax, which is a remote
package, and `nix flake check` builds with no network.** Adding it naively takes
down every Swift check, not just the macro's. Options, in the order I would try
them:

1. **Vendor swift-syntax for the sandbox** (`swiftpm2nix` or a fetched fixed
   output). Correct, and the most work.
2. **Keep the macro in a separate SwiftPM package** that `nix flake check` does
   not build, verified only in the dev shell. Cheap, and honest so long as the
   skip is visible.
3. **Give up on the macro** and have users write the dispatcher by hand from
   `ReferenceTimer.swift`. Not absurd — the guarantee comes from the required
   members, not from who typed them — but it gives up the thing that makes the
   matrix readable.

Tools-version 5.9 is no longer part of this: the manifest was raised for
`ObservableStore`, so the only question left here is swift-syntax packaging.

## Backlog — `tabula-fmt`, a formatter for matrix files

**The problem.** A matrix is only readable while its columns line up, and every
language formatter wants to destroy that. We already work around it: the
`.editorconfig` disables three ktlint rules for annotated declarations, and the
Rust matrices survive only because rustfmt leaves macro invocation bodies alone
when it cannot parse them — which is luck, not a guarantee.

**The proposal.** Matrices move into `*.tb.rs`, `*.tb.kt`, `*.tb.swift`. The
language formatter is told to skip those; a separate tool, `tabula-fmt`, formats
them and only them, keeping the grid aligned. Written in Rust, published on its
own cadence — a formatting change should not force a library version bump, and a
formatter that ships with the library is a formatter nobody upgrades.

**What has to be true for it to work:**

- **The two formatters must never both own a file.** This is the classic
  formatter fight, and the extension convention exists to prevent it. The check
  should assert it rather than assume: running the language formatter on a
  `.tb.*` file must be a no-op, and `tabula-fmt` must refuse anything else.
  rustfmt has `ignore` in `rustfmt.toml`, ktlint reads `.editorconfig`, and
  swift-format takes an exclude list.
- **`tabula-fmt` must not touch the non-matrix parts of a file.** It should
  reformat inside the matrix declaration and leave every other byte identical,
  so it can be run on a file that also holds ordinary code. A formatter that
  rewrites what it does not understand is worse than none.
- **It must refuse what it cannot parse**, loudly, rather than emitting
  something plausible. Same rule as the generators.

**The known friction, in order:**

1. **Rust module resolution.** `mod timer;` looks for `timer.rs`, so a file
   named `timer.tb.rs` needs `#[path = "timer.tb.rs"] mod timer;`. That is a
   real cost imposed on every user, and it is the strongest argument against the
   naming scheme. Worth checking whether `#[rustfmt::skip]` on the invocation is
   enough on its own before accepting it.
2. **Kotlin and Swift are fine.** kotlinc compiles any `.kt`; SwiftPM compiles
   every `.swift` under `Sources`. Neither cares about the infix.
3. **IDE support.** Editors key syntax highlighting off the final extension, so
   `.tb.rs` should highlight as Rust — but format-on-save will run the wrong
   formatter unless configured, which is exactly the fight the convention is
   meant to avoid.
4. **Three grammars, one tool.** The matrix syntax differs per language
   (`GO!(..)` vs `CellSpec(Kind.GO, ..)` vs `.go(..)`), so `tabula-fmt` needs a
   parser per language even though the alignment logic is shared. Scope it to
   the matrix block only; anything more is a language formatter and that is not
   a project worth starting.

**Is the alignment actually at risk? Measured, not assumed:**

| | result |
|---|---|
| `rustfmt` on `timer_matrix.rs` | unchanged |
| `rustfmt` on `scale.rs` (8×12, 96 cells) | unchanged |

rustfmt leaves macro invocation bodies alone when it cannot parse them, and a
matrix is not parseable Rust. So **Rust is already safe, and guarded**:
`tools/verify fmt` runs `cargo fmt --check` over the whole tree, so if a future
rustfmt starts reformatting matrices, CI says so.

**Kotlin: measured too.** `tools/verify kotlin-matrix-stable` runs ktlint's
formatter over a copy of the tree and compares the matrix rows. Two findings:

- With the repo `.editorconfig`, the rows come back **byte-identical**. ktlint
  reformats plenty of ordinary Kotlin around them, and leaves the matrix alone.
- **Without it, ktlint collapses the alignment outright** — `no-multi-spaces`
  turns the aligned columns into single spaces. The exemptions are load-bearing,
  and nothing verified that until now. Deleting one turns the check red, which
  was confirmed by deleting one.

ktlint also reports `max-line-length` on the longer rows and cannot auto-correct
it. That is the *real* residual risk for Kotlin: not reformatting, but a
line-length rule failing a build. It is per-path configurable in
`.editorconfig`, which is an argument **for** the `.tb.*` naming — scoping
config by filename — and **against** writing a whole formatter.

**Swift: not yet measurable.** There is no matrix *declaration* syntax in Swift
until `TabulaMacros` lands — the reference machine writes its dispatcher by
hand, and the `Table(...)` literals are one row per line but not column-aligned.
A `swift-matrix-stable` check today would guard nothing. It becomes the right
thing to add in the same patch as the macro, and not before.

**So the first task is still not the formatter.** The evidence so far says the
danger is real but that per-path configuration handles it. Write `tabula-fmt`
only if a case turns up that configuration cannot fix — and note that `.tb.*`
would cost Rust users a `#[path]` attribute on every matrix module, which is the
largest single cost in the proposal and buys nothing for the language that is
already safe.

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
