# tabular-center — Implementation Plan

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
| 4 Kotlin core + KSP | **done**; KSP adapter now runs — `tabular-center-kotlin/examples/06-generated` builds green |
| 5 Swift | core, reference, compile-fail, testing, conformance, examples, **codegen**, `MachineSyntax`; macro expansion to come |
| 6 Composition | **done (all three)** |
| 7 Effects surface | **done (all three)** |
| 8 Introspection & tooling | **done (all three)** |
| 9a Driver and mailbox | **done (all three)** |
| 9b Rendering surface | **done** (Kotlin and Swift emitters, KSP, `composable-transition`) |
| 10 Release | in progress: README, migration guide, versioning policy, benchmark done; published: Maven Central, crates.io, the Swift mirror (up to 0.2.0); Swift Package Index listing pending |

One exception to the table, found by the audit below: Rust had no prototype
colors. It has one now, `async`, composing in both directions the rule
allows (see the audit's Rust-colors items).

133 Rust tests; 65 compile-fail fixtures (18 Rust, 4 Kotlin, 5 Kotlin-codegen,
14 Kotlin-KSP, 4 Swift, 12 Swift macro-syntax, 8 Swift-codegen); 11
conformance fixtures (96 trace steps), every one with an adapter in all three
languages. Recounted in the October 2026 audit; the previous figures were a
release behind, and the first command below named a directory the rename had
moved. No golden
`.grid`, `.mmd`, `.lint` or `.cov` is committed any more: each harness renders
its own at check time and `renderings-agree` diffs them (see the audit below).
Every runtime lint is tripped by at least one fixture.

These counts are checked against the tree, not remembered. Regenerate with:

```
grep -rho '#\[test\]' tabular-center-rust/ | wc -l
ls tabular-center-rust/tabular-center/tests/compile_fail/*.rs | grep -vc _prelude
ls -d tabular-center-kotlin/ksp/compile-fail/fixtures/*/ | wc -l
ls -d tabular-center-swift/macros/fixtures/*/ | wc -l
ls tabular-center-kotlin/compile_fail/*.kt | wc -l
ls tabular-center-kotlin/codegen/compile_fail/*.kt | wc -l
ls tabular-center-swift/compile_fail/*.swift | wc -l
ls tabular-center-swift/codegen-support/compile_fail/*.swift | wc -l
grep -h '=>' spec/conformance/traces/*.trace | wc -l
ls spec/conformance/*.tbl | wc -l
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
`tabular-center-kotlin/compile_fail/`:

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

## Audit, September 2026: the tree against this file

Everything in the status block above was re-derived from the tree rather than
read from here: the counts, an adapter for every fixture in every language, and
Phases 7, 8 and 9a in Kotlin and Swift (`perform` in both generators, mermaid,
DOT, lint and coverage in both cores, both drivers non-reentrant with a fixed
mailbox). Those three phases had been "Rust half" in this file and in the
README for some time after they stopped being true -- a status that undersold
the tree, which is the harmless direction.

The other direction, in priority order:

- **Rust prototype colors do not exist.** Phase 2 ticked `prototype` in the
  grammar, a `$($color:tt)*` capture, and color splatting with `$(.await)?`;
  Phase 6 ticked one-way color flow as "enforced by construction in Rust".
  `transition_matrix!`'s entry arm has no `prototype` clause, `Handle` is a
  library trait with one uncolored `fn handle`, and the `DELEGATE` arm calls
  `$ch::step(..)` with no `.await` -- while its comment, `delegate.rs`'s module
  doc and `spec/cells.md` 2.5 all described the `.await` it would emit. The
  color-flow property held vacuously: nothing can be colored, so nothing can
  mismatch. Reopened below, with the design question it raises: colors are
  copied, never enumerated (ARCHITECTURE 5), but `Handle` is a *library* trait
  and has no declaration to copy them onto.
- **`kotlin-no-runtime-deps` could never exist.** It was gated on
  `tabular-center-kotlin/settings.gradle.kts`, which ARCHITECTURE 12 says the library will
  never have, ran `:tabula-core` from a Gradle build that does not exist, and
  bypassed `tools/verify`. A permanently absent check -- the shape 0c and 0d
  both warn about -- guarding a rule the `kotlin` step already enforces by
  compiling `tabula-core` against an empty classpath. Removed. `has.kotlinGradle`
  stays: `nix/publish.nix` gates Maven publication on it, which is a real
  future build rather than a check that cannot run.
- **Swift codegen does not produce compilable Swift for a realistic
  machine, and nothing notices.** `TabulaCodegen.emit` calls a `narrow(..)`
  defined nowhere where `ReferenceTimer.swift` binds payloads with
  `case let (.running(since), .tick(now))`; calls `delegateTo<Child>(..)`
  without emitting it; names effect payloads `F.StopClock`, which a Swift enum
  case is not; and writes no `try`/`await` at call sites for a colored
  prototype. `codegen-golden/` has never held a golden, so `swift-codegen`
  reports `skip timer` on every run, and unlike `kotlin-codegen` the emitted
  source is never compiled. `./tools/verify swift-codegen -- --bless` cannot
  work either: `run` passes the step no arguments, and `--bless` parses as a
  step name. Phase 5's "narrowed types" and "payload binding, no
  `default:`" boxes are therefore *emitter* work, and not blocked on the
  macro, which would only call `emit`.
- **Three boxes open for work in the tree:** the `payload-hoist` fixture
  (section 1), `matrix-covered` ("a check that every `.tb.` file is covered"),
  and a record-only paragraph in Phase 3 written as a checkbox.
- **Smaller overclaims.** The payload-free fast path's *index dispatch* was
  never written (`TABLE` is a `const` `[[Cell; M]; N]` for every machine, and
  dispatch is a `match` for every machine); `UNREACHABLE` is counted by
  `Table::coverage`, not "in build output", which stable `macro_rules!` cannot
  write to; Phase 0 said Swift 6 where the flake pins 5.10.1; ARCHITECTURE 9
  named a Kotlin `Machine` class that is `Driver` and an `@Observable`
  `ObservableStore` that conforms by hand.

- [x] Docs, comments and boxes corrected; the Gradle report check removed
- [x] Rust prototype colors, first increment: `prototype async fn handle;`.
      Decided as colored library traits -- `AsyncHandle` and `AsyncPerform`,
      twins of `Handle` and `Perform` -- because Rust's cell surface is a
      library trait with no declaration to copy a color onto, and a generated
      per-machine trait needs identifiers `macro_rules!` cannot build. That
      does enumerate colors, which ARCHITECTURE 5 rejects in general; in Rust
      the enumeration is the language's, not tabula's: `async` is the only
      color a trait method can carry on stable (`const` trait methods are
      unstable, `extern` does not apply). Any other prototype is
      `tabula::unsupported-color`. The color is threaded through every rule
      as one token and used in four places: `step`, `perform`, the per-cell
      bound, and the HANDLE call. `tests/async_prototype.rs` proves `step`
      really awaits its cells (a suspending cell makes it poll twice)
- [x] Rust colors, second increment: delegating to an async child. The
      parent's expansion cannot see the child's color, and no longer needs
      to: `Step` implements `IntoFuture` (ready at once), so an async parent
      awaits whatever the child's `step` returns -- a plain child's `Step`
      or an async child's future. A plain parent does not await, so an async
      child is a future where a `Step` is required: refused by rustc, by
      construction. Chosen over a per-child exported macro carrying the
      color, which would have broken delegation across crates.
      `tests/async_composition.rs` shows both allowed directions (one poll
      over a plain child, two over a suspending async one);
      `compile_fail/async_child_in_plain_parent.rs` the refused one. That
      unblocks the `color-mismatch` decision below: all three languages now
      enforce one-way color flow by construction
- [x] Swift emitter to the shape of `ReferenceTimer.swift`, first half:
      payload binding (`case let (.running(since), .tick(now))`, building
      the narrowed structs), effect payloads (one field passes its value, as
      the reference's `Reason`; several pass a labelled tuple), and color
      split by where Swift wants it -- attributes before `func`, `async` /
      `throws` after the parameters, `try await` at every call into a cell.
      What it cannot emit yet it refuses with `#error` at the top of the
      file: payload fields it was not given, and a GO/EMIT naming an effect
      that carries a payload
- [x] `swift-codegen` compiles the emitted source, as `kotlin-codegen` does:
      `codegen-support/` holds the types, a complete implementation per
      color, and three fixtures that must be refused -- a missing cell, a
      missing effect handler, and an uncolored caller of a colored `step`.
      Blessing is a direct call, `swift run tabula-codegen-check
      codegen-golden --bless`, as in Rust and Kotlin; `tools/verify` never
      blesses. (Briefly it did, through a `TABULA_BLESS` variable, after the
      advertised `-- --bless` turned out never to reach the step. Removed:
      the definition of green does not rewrite what it compares against.)
      A missing golden now fails, as in Kotlin, rather than skipping
- [x] Kotlin's composition output was never compiled either: nothing -- not
      the codegen check, not the KSP processor -- built a `ChildDesc`, so
      `Emit.kt`'s delegation, and the color flow this file credited it with,
      were read rather than verified. `kotlin-codegen` now emits and compiles
      a child, a parent in both colors, a hole in the child, and a colored
      child under a plain parent that must be refused
- [x] Kotlin reaches a child through `ChildDesc.packageName`, and names its
      members through the alias. It used the alias for both, so a child could
      only live in a root package spelled like its alias. The test children
      moved to `generated.retry`; `runChildPackageTest` pins the rule with a
      package whose last segment is NOT the alias, the one case the compile
      stage cannot tell apart
- [x] The KSP processor builds `ChildDesc`s, so DELEGATE is reachable through
      annotations. The surface needed no new annotation: `CellSpec.child`
      already took a `KClass`, and it names the child's annotated
      declaration -- `child = RetrySpec::class`. Everything else is read from
      that class with the helpers the processor already had: its package (the
      same one its generated code lands in), its machine name decapitalized
      for the alias, its `S` / `A` / `F` from `@Machine`, its `Ctx` from the
      `handle` prototype. So a parent declares one thing about its child.
      `Retry.tb.kt` and `Job.tb.kt` in the KSP example are the pair, compiled
      by `JobImpl` against the generated `Cells`, and both have `kspTwins`
      entries -- the same descriptions the codegen compile stage builds by
      hand, so the two front ends are diffed against one statement.
      `tabula::unknown-child` now also names the KSP case: a child must be
      compiled with its parent, since `@Machine` is `SOURCE`-retention
- [x] **Rendered conformance output is not committed either.** `.tbl` and
      `.trace` are authored and stay: they are the contract. `.grid`, `.mmd`,
      `.lint` and `.cov` were blessed by Rust and read by the other two, which
      made one implementation's output the expectation for the other two and
      meant re-blessing whenever any renderer changed a character. All 44 are
      gone. Each harness now writes its renderings with `--emit=<dir>`, and
      `renderings-agree` renders from every implementation present and diffs
      them -- failing, not passing, if fewer than two are present, since one
      implementation agreeing with itself asserts nothing. It is the only
      check that needs more than one toolchain, which is why it exists as a
      step rather than as three. Two consumers moved with it: the fixtures
      table in `spec/diagnostics-coverage.md` is now checked there, so
      `diagnostics-coverage` stays text-only; and the Rust test that compared
      `table-diff`'s renderer against the `.grid` goldens now compares it
      against `Adapter::grid` directly, which is what the goldens stood in
      for. What is lost: a lint or coverage change no longer shows as a diff
      in review, only as agreement or disagreement.
- [x] **Generated code is not committed** -- as source or as a golden. The
      emitted-source goldens (`tabular-center-kotlin/codegen/golden/`, `tabular-center-kotlin/ksp/golden/`,
      `tabular-center-swift/codegen-golden/`) are gone, and each guarantee they carried is
      checked from source instead. That the output is valid and enforces the
      guarantee: the compile stages of `kotlin-codegen` and `swift-codegen`,
      which were always the half that mattered. Determinism: each check emits
      twice. KSP extraction: `kspTwins` in `tabular-center-kotlin/codegen/Main.kt` states
      what each example machine must extract to, and `kotlin-ksp` diffs the
      twins' output against what KSP generated -- both produced at check
      time, both directions enumerated. `no-generated` fails on `*.golden`,
      `*Generated.kt` or `*.emitted.swift` in the tree. `spec/conformance/` is
      deliberately outside it: rendered data, the cross-language contract,
      not code any build consumes
- [x] `no-bless`: `tools/verify` fails if any command in it or in `nix/`
      mentions a bless flag or variable. Comments and printed advice are
      allowed. Proven against the commit that had `TABULA_BLESS`
- [x] Commit the first Swift goldens, blessed by running the emitter.
      Re-blessed when the second half changed every emitted file
- [x] Swift emitter, second half. Generated members live in
      `extension <Machine>` and every type is qualified by the machine's enum
      (`Timer.S`, `Timer.Running`), matching ARCHITECTURE 11.3's nesting; the
      cell protocol stays at file scope so a parent can refine it. Two
      machines now share a module, and `swift-codegen` compiles all seven in
      one on purpose. `.delegate(.retry)` reaches `Retry.step` through that
      namespace; `delegateTo<Child>` is emitted with the parent's color, as
      Kotlin's is; the prism is narrowed like a HANDLE cell and the lens takes
      the whole parent state, as in Kotlin. `codegen-support/` gains Retry,
      Job in both colors, and two refusals: a hole in the child's surface,
      and a colored child under an uncolored parent
- [x] Payload types nested in the machine's enum are qualified by
      `MachineSyntax`, the one place that can see the enum's members:
      `stopClock(reason: Reason)` reads as `Timer.Reason`. Every
      `IdentifierTypeSyntax` naming a nested type is qualified by byte
      offset, so `[Reason]`, `Reason?` and `Reason.Kind` work and
      `Swift.Int` or an already-qualified `Timer.Reason` are untouched.
      Chosen over nesting the protocol (SE-0404), which would have changed
      every machine's surface and every parent's `refines` clause for one
      bug. The macro check asserts the strings; `codegen-support` proves a
      qualified nested type resolves in the file-scope protocol
- [x] Effect arguments in GO/EMIT, in **Swift**. `RawCell.effects` holds the
      reference as written, arguments included, and `effectName` takes the
      part before `(` where only the name is wanted -- validation, and
      `TABLE`, which records WHICH effect a cell emits and not with what. The
      dispatcher emits the call verbatim, and the `#error` refusal is gone.
      A bug came with it: `.stopClock(reason: .cancelled)` parses as a CALL
      wrapping the member access, and `MachineSyntax` matched only the member
      access -- so every payload-carrying effect in a static cell vanished
      from the machine with no diagnostic at all. The macro check now asserts
      the arguments survive; `codegen-support`'s timer emits one from a GO
- [x] Effect arguments in GO/EMIT, in **Kotlin**, so all three have it. The
      surface change is an annotation, not a parallel array:
      `emits = [Emit(F.Chime::class, "volume = 3")]`, pairing the effect with
      its literal arguments so the two cannot drift apart -- an `emitArgs`
      array would be positional against `emit` and misalign in silence.
      `args` is a string for the reason `CellSpec.args` already is: an
      annotation cannot hold an expression, and a static cell only ever emits
      what is known at declaration time. `emit` stays for payload-free
      effects. As in Swift, the reference is carried whole and `effectName`
      takes the part before `(` for validation and `TABLE`. The `Gate`
      example's `Chime` now carries a volume and is emitted by a static cell,
      so KSP, the twin and the generated code are checked end to end

---

## Re-audit, September 2026: second pass

The first audit re-derived the status block. This one re-read the files that
describe the tree -- this plan, `ARCHITECTURE.md`, `README.md`, the flake, the
workflow and the `justfile` -- against what they describe, before the rename
below moves every path in them. Fixing drift first means the rename diff is
paths and nothing else.

- [x] The status counts: 106 Rust tests, not 105; and the "11 each of golden
      `.grid`, `.mmd`, `.lint`, `.cov`" line survived the patch that deleted
      all 44 of them
- [x] `nix run .#conformance` ran `./tools/verify swift` for Swift -- the whole
      Swift suite -- where Rust and Kotlin ran their conformance steps. Now
      `swift-conformance`
- [x] `just bless` passed `--bless` to a harness that stopped accepting it when
      the goldens went. Removed; nothing is blessed any more (`no-bless`)
- [x] `swift-unavailable` said six Swift checks were absent; there are eight
- [x] Stale toolchain history presented as current: `context.nix` said the
      pinned nixpkgs has Swift 5.8 (it is 26.05), and `ci.yml` said the Swift
      checks are absent on Linux (they run there)
- [x] `tools/verify`'s header omitted `rust-gui`, `renderings-agree` and
      `kotlin-compose`
- [x] ARCHITECTURE 12 listed five of eleven conformance fixtures and two of
      the Swift targets were missing; README's "exist in only one language"
      list omitted the Compose and iced examples
- [x] Phase 0 ticked a license and a `continue-on-error` Swift job. The job is
      gone for a good reason and the box now says so; the license files were
      never there, and that box is reopened

## Audit, October 2026: third pass

Re-read this file, `ARCHITECTURE.md`, the READMEs and the comments that make
claims about the tree, against the tree. Docs and comments only; no behaviour
changed. The drift had two sources: counts nobody re-ran, and the `doc/`
decision, which was reversed twice and left a sentence behind each time.

- [x] Status counts: 133 Rust tests (not 106) and 65 compile-fail fixtures
      (not 56). The first regeneration command named
      `tabular-center-rust/tabula/`, which the rename moved, so it could not
      have been re-run; it and the two other present-tense pointers to that
      path (Phase 1's deliverable, the Top-risks table) now name
      `tabular-center-rust/tabular-center/`
- [x] The status table said 9b was not started; every 9b box is ticked and
      the code is in the tree. 9b and 10 now have rows, here and in README
- [x] Phase 5's "Conformance harness green" was open with eleven Swift
      adapters registered. Ticked
- [x] `doc/` is build output, deployed by `pages.yml` and ignored by
      `.gitignore`. Six places still said it is committed and diffed for
      staleness: `.gitignore`'s own comments, `spec/diagnostics.md`,
      `tools/verify`, `nix/checks.nix`, ARCHITECTURE 12, and README's links
      into `doc/*.md`, which 404 on GitHub. The links now go to the site
- [x] ARCHITECTURE: 12 marked the formatter "tool not written" and omitted
      `hop.rs`; 13 counted four flakes where there are five; 10 described
      committed golden snapshots; 11.1 called Rust colors design-only; 11.2
      and 11.3 showed superseded surfaces with no note saying so
- [x] Swift READMEs said the macro is unwritten and blocked on swift-syntax:
      `MachineSyntax` exists, swift-syntax is vendored by `swift-lock`, and
      the blocker is `CompilerPluginSupport`. "All 13 diagnostics" is now
      fourteen, and is no longer written as a number that drifts
- [x] The Kotlin README described the emitted-source golden and Rust-written
      `.grid` goldens, both removed
- [x] Phase 0's outcome described the `hashFiles` gate that was removed for
      making `ci.yml` invalid; a paragraph belonging to the license box sat
      inside Phase 1; the formatter backlog still argued against writing the
      formatter. Annotated or moved, history kept
- [x] Three Phase 10 boxes were standing rules, not tasks, and could never be
      closed. Moved to a "Standing rules" list, so `grep '\- \[ \]'` lists
      only work
- [x] **Found by the first real release: `SIGNING_KEY_ID` in gpg's long form
      fails as `Could not read PGP secret key`.** Gradle's `PgpKeyId` accepts
      exactly `XXXXXXXX` or `0xXXXXXXXX` and matches on the low 32 bits;
      `0x` + 16 digits, which `gpg --keyid-format long` prints, throws inside
      the in-memory provider, which reports every exception as that one
      message. `kotlin-publication` passed because it always handed Gradle the
      8-digit form -- the one spelling that works -- so it tested the build
      and not the instructions. Now `publication.gradle.kts` accepts 8, 16 or
      40 hex digits, `0x` optional, reduces to the last 8, and names the
      `[S]` subkey when it refuses; the check passes the `0x` + 16 form a
      person copies from gpg; RELEASING.md says any spelling works and that
      it must be the subkey's ID, never the primary's
- [x] **Found by the first real release: an environment variable in a job's
      `if:` is never seen.** `maven-central` gained
      `if: ${{ vars.MAVEN_CENTRAL_ENABLED == 'true' }}`, like `crates-io`'s
      `CRATES_IO_ENABLED`, and set in the `maven-central` environment it
      skipped the job: GitHub evaluates a job-level `if:` before the job enters
      its environment, so `vars` there holds only repository and organization
      variables. Neither switch was documented. RELEASING.md now has "Turning
      a registry on" (both are repository variables, and why), each registry's
      setup list ends with its switch, and ARCHITECTURE 16 records the gate
- [x] `benches/dispatch.rs` ended by printing that `plain` is within noise of
      the other two. The recorded run says it is twice as fast, for the reason
      Phase 10 gives

---

## Found on Darwin: response files and the Swift driver

- [x] `check-darwin` failed `swift-codegen` with `The file "63" couldn't be
      opened ... NSFilePath=/dev/fd/63 ... Bad file descriptor`, in the
      first `swift run`, after SwiftPM began compiling. Nothing in the
      repository passes a `/dev/fd` path; nixpkgs' Swift wrapper does: it
      ends `exec "$prog" @<(printf "%q\n" ...)` when
      `NIX_CC_USE_RESPONSE_FILE` is on, and that defaults on wherever the C
      compiler is clang -- Darwin. The Swift driver re-opens the path
      through Foundation once the pipe is gone. Read from nixpkgs'
      `wrapper.sh` and `cc-wrapper/default.nix` before changing anything.
      Fixed by turning response files off for Swift in every place the
      toolchain is set up (ARCHITECTURE 16, "Nix: Swift"); command lines are
      far below macOS's argument limit. Expected green on `check-darwin`, not
      yet observed

---

## Upstream dependencies: a daily check, update PRs, and compatibility tables

Requested October 2026: a scheduled job that checks upstream versions every
day, opens a PR with the update and runs the checks on it; and tables, per
release of this library, of the dependency versions it was built and
verified with, so a user can match their project to a release.

**What there is to track today**, and where each version lives:

| Dependency | Pinned at | Reaches users? |
|---|---|---|
| Kotlin compiler `2.1.20` | six `build.gradle.kts` + `kotlinVersion` in `tabular-center-kotlin/nix/context.nix` | yes: the published jars are compiled with it |
| KSP `2.1.20-1.0.32` | four `build.gradle.kts` (plugin and `symbol-processing-api`) | yes: the processor artifact is built against it, and KSP 1 versions pair with one Kotlin |
| JVM target `21` | `jvmToolchain(21)` in two builds, `pkgs.jdk21` | yes: the jars are Java 21 bytecode, so a consumer needs JVM 21+ |
| Gradle `8.14.4` | `nix/gradle-lock.json` (from nixpkgs) | no: build only |
| Compose Multiplatform `1.8.0` | `examples/07-compose` | no: an example's |
| swift-syntax `509.1.1` | `macros/Package.swift` (`from: "509.0.0"`), `nix/swift-lock.json` | not yet: the macro package is not published |
| Swift tools `5.9` (examples `5.7`) | `Package.swift` | yes: the minimum toolchain |
| Rust MSRV `1.75`, edition 2021 | workspace `Cargo.toml`, `rust-toolchain.toml`, the nix pin | yes: policy, not a dependency |
| iced `0.14` | `examples/05-iced` | no: an example's |
| the GUI example's Rust floor, `1.88` | `examples/05-iced/Cargo.toml` (`rust-gui`) | no: follows iced's own `rust-version` |
| nixpkgs, rust-overlay, nixpkgs-swift | the five `flake.lock`s | no: build only, but they move rustc stable, Swift, ktlint, the JDK patch level |
| GitHub Actions, by commit | the workflows (`# vX` annotations) | no |

The library itself has no dependencies in Rust and only the standard library
in Kotlin and Swift; what a user must match is compilers, KSP and the JVM.

**Decisions** (U1, U2, U5 accepted as proposed; U3 and U4 decided otherwise):

- [x] U1. A single source of truth, `dependencies.toml` at the root: every
      tracked version once, each marked `user-facing` or `build`, and with
      an update policy -- `auto` (the job may propose it), `manual` (the job
      reports a newer version but proposes nothing: the Rust MSRV, the JVM
      target, the Swift tools version, which are promises to users, changed
      on purpose and announced), or `hold = "X"` (skip one version a
      maintainer rejected, so a closed PR is not reopened the next morning).
      Couplings are declared, not discovered: `ksp.follows = "kotlin"` (only
      a KSP whose prefix is the new Kotlin), `swift-syntax` major follows the
      Swift toolchain (509 is Swift 5.9). A root check `deps-consistent`
      requires every place a version is written to agree with the file --
      the same idea as `version` against `VERSION`, and the end of the Kotlin
      version being typed seven times
- [x] U2. One PR per group, updated in place: `nix-inputs`, `kotlin`
      (compiler, KSP, Compose together, since they couple), `gradle`, `swift`,
      `rust-examples`, `actions`. A group's failure does not block the others, and a
      group's PR is force-pushed rather than duplicated. Never auto-merged
- [x] U3. **Decided: a fine-grained personal access token**, scoped to this
      repository only, with Contents, Pull requests, **Workflows** and Issues write
      (GitHub refuses a push that changes `.github/workflows/` without the
      last, and U4 makes the job edit the pinned actions there), the shortest
      expiry offered, stored as `UPSTREAM_TOKEN` in the `upstream`
      environment, which allows only the default branch. Its expiry is a
      known failure: the job reports an authentication error by name, and
      RELEASING.md gains the renewal step. The reasoning that led here: the
      PR's checks must be the normal ones, and a PR opened with the
      workflow's `GITHUB_TOKEN` does **not** trigger other workflows -- GitHub's
      rule against recursive runs -- so `ci.yml` would never run on it, and
      the PR would sit with no checks at all. Recommended: a GitHub App
      installed on this repository only (`contents` and `pull-requests`
      write), its key in an `upstream` environment, a token minted per run
      by `actions/create-github-app-token`; then `ci.yml` runs on the PR on
      Linux and macOS exactly as on any other, and stays the one definition
      of green. Alternative: a fine-grained PAT (simpler, tied to a person)
- [x] U4. **Decided: no bot.** Everything is the custom job's, the pinned
      actions included: for each `uses: owner/action@<sha> # vX`, it asks
      GitHub for the action's newest release tag, resolves the tag to its
      commit, and rewrites both the SHA and the annotation -- a new `actions`
      group with its own PR. The annotation stays exempt from ARCHITECTURE 15
      because the job reads it, not because Dependabot would
- [x] U5. Where the compatibility tables live: data in
      `compatibility.toml` (one entry per released version, appended by
      `nix run .#release` from `dependencies.toml` as it tags), rendered by
      `tools/docs` into a site page, `https://tabula.center/compatibility`,
      linked from every README. Rendered, not committed as markdown: generated
      output is not committed (`no-generated`)

**Tasks, after U1-U5:**

- [x] `dependencies.toml` with today's versions and policies;
      `tools/deps sync` writes them into every manifest (as `release` writes
      `VERSION`), and root `deps-consistent` checks nothing drifted. Moves the
      seven Kotlin pins and four KSP pins to one line each.
      **Done** (expected green, not yet observed): nine dependencies, 34
      sites. Emulated against the tree, every site agrees; a dry run of
      `sync` with Kotlin and KSP bumped changes exactly the 11 lines that pin
      them and nothing else -- in particular not `05-iced`'s own
      `rust-version`. Locks (`Package.resolved`, the iced `Cargo.lock`) are
      checked, never written; regenerating them, the flake locks, and the
      kotlinc hash beside `kotlinVersion` is `tools/upstream`'s work, next.
      Not tracked: Gradle, which nixpkgs chooses and `gradle-lock.json`
      records, and the flake inputs, which their own locks pin
- [x] `tools/upstream` (an app, `nix run .#upstream [-- --group G]
      [--update]`): asks each upstream its newest version -- Maven Central's
      `maven-metadata.xml` for Kotlin, KSP and Compose, Gradle's
      `services.gradle.org/versions/current`, crates.io's API for iced,
      GitHub's tags for swift-syntax, `nix flake update` for the inputs --
      applies the policy and couplings, and with `--update` edits
      `dependencies.toml`, runs `tools/deps sync` and regenerates every lock
      the change stales (`gradle-lock`, `swift-lock`, the iced `Cargo.lock`,
      all five `flake.lock`s together, as ARCHITECTURE 13 requires). The
      third command allowed to reach the network; ARCHITECTURE 16 and the two
      lock generators' headers say "two" and change with it
- [x] `.github/workflows/upstream.yml`: `schedule` daily at an off-the-hour
      minute (top-of-hour cron is delayed or dropped under load), plus
      `workflow_dispatch`; a matrix over the groups; each runs
      `nix run .#upstream -- --group G --update`, and if the tree changed,
      commits to `upstream/G` and opens or updates its PR with the App token.
      The PR body: each version old -> new with its release-notes link,
      whether it is user-facing, and what a user-facing change means for the
      compatibility table. Every action pinned by commit, credentials only in
      the `upstream` environment, as in `publish.yml`
- [x] Reports without PRs: a `manual` dependency with a newer version, a
      Kotlin held back because no KSP pairs with it yet, a `hold` that has
      been passed -- one issue, updated in place, labelled `upstream`
- [x] The `actions` group in `tools/upstream`: newest release tag per pinned
      action through the GitHub API, tag resolved to a commit (annotated tags
      dereferenced to the commit they point at), SHA and `# vX` rewritten
      together; the same group covers every workflow file
- [x] **Slice 2 landed** (expected to work, **not yet observed**: it needs
      the token, the environment and a first run; RELEASING.md, "The upstream
      job"). `tools/upstream` queries Maven Central's metadata (Kotlin, KSP,
      Compose), `git ls-remote` (swift-syntax: the tags API caps at 100 in no
      useful order, and swift-syntax has hundreds), crates.io (iced) and the
      GitHub API (actions, and the `manual` report); with `--update` it edits
      `dependencies.toml`, syncs, and regenerates what the change stales --
      `gradle-lock.json` and the kotlinc hash (`nix store prefetch-file`),
      `Package.resolved` and `swift-lock.json`, the iced `Cargo.lock`, all five
      flake locks (subflakes first, the root last). Kotlin moves only with a
      KSP for it, else it is held and the note reaches the report issue.
      Emulated: the seven commit-pinned actions parse, `ci.yml`'s three
      unpinned ones become notes, `set_version` edits only its section, the
      hash rewrite changes exactly the line under the compiler's URL. The
      workflow pushes a branch only when its tree changed. The "only two
      network commands" claim, already untrue of `publish`, is now one list
      in ARCHITECTURE 16 that the scripts point to, instead of five counts
- [x] Found on the way: `tabular-center-swift/tools/swift-probe` is a shell
      script without a shebang (it is run as `bash swift-probe`), so stage 3's
      shebang survey missed it. One comment removed; it is in `no-comments`'
      list now
- [x] **First runs found two faults of mine, both fixed.** (1) The `kotlin`
      group held Kotlin at 2.1.20 for ever: its coupling looked for a KSP
      named `<kotlin>-...`, but KSP changed scheme at 2.3.0 -- the last
      prefixed release is `2.2.21-2.0.5`, later ones (`2.3.12` today) stand
      alone -- and Kotlin is at 2.4.20. With Kotlin held, Compose 1.12.1 was
      proposed, which needs the Kotlin Gradle Plugin 2.2 or newer, and
      `gradle-lock` failed. Now the newest standalone KSP is preferred (the
      prefixed scheme remains for the old world), Kotlin is never held for a
      KSP, `deps-consistent` checks the prefix only on a prefixed version,
      and a Compose release Gradle refuses for its minimum Kotlin is reverted
      with the reason in the PR instead of failing the group. (2) The
      `nix-inputs` group reached `gh pr view` and got `401 Bad credentials`
      after a successful fetch -- the signature of a fine-grained token still
      awaiting the organization's approval (it can read a public repository,
      nothing more), or one mistyped, expired or revoked. Both jobs now check
      the token first and say which of the three it is (RELEASING.md)
- [x] **The first `rust-examples` update was red, as designed**: iced 0.14
      moved the window title out of `iced::run`; `main.rs` now uses
      `iced::application(..).title(..).run()` (merged with the update). It
      also exposed a coupling: iced 0.14 needs Rust 1.88, while `05-iced`
      declared 1.85. The GUI example's floor is now `rust-gui` in
      `dependencies.toml`, a `deps-consistent` site, raised by the
      `rust-examples` group to each new iced release's `rust_version`
- [x] **Fixing a red update on its own branch would be undone the next
      morning**: the job rebuilt `upstream/<group>` from `main` and
      force-pushed whenever the tree differed, which a person's fix always
      makes it do. Now any commit on the branch (since `main`) by an author
      other than `upstream@tabula.center` makes the job leave the branch
      alone, with a notice, until its pull request is merged or closed
- [x] Expected red, recorded so it is not mistaken for a broken job (and in
      RELEASING.md, "A red update"; it happened, with iced 0.14): a
      kotlinc upgrade can reword the four messages the guarantee fixtures
      assert (spec/diagnostics.md forbids normalising them), and an iced
      minor is a breaking change pre-1.0. The PR stays red until a person
      moves the fixture or the example -- which is the point of running the
      checks on it
- [x] `compatibility.toml`, backfilled for every release so far from the
      tags (each tag's manifests are the record), and appended by `release`.
      **Done** (expected to work, not yet observed): `tools/compat add`
      (called by `release` before `nix flake check`), `backfill` (reads each
      `v*` tag through `tools/deps at REV`, the site table applied to a git
      revision), `check` (the `compatibility` step: shape only, since a record
      is history and `main` moves on). The page is `compatibility` on the
      site, linked from every page's navigation and the README. The file
      starts empty: the tags are in your repository, not in the tarball this
      was written from, so **run `tools/compat backfill` once and commit the
      result**; nothing was guessed. The "what was verified with" table holds
      the pinned inputs (nixpkgs revision, Gradle, the examples' versions)
      rather than tool versions read by running each toolchain, which would
      make recording a release depend on building every toolchain first.
      Originally specified:
      Two tables per language on the page: **what your project needs** --
      Rust: MSRV, edition, `no_std` (and that `export`/`lint` need `alloc`);
      Kotlin: the compiler the jars were built with, JVM 21+, the KSP version
      the processor pairs with; Swift: tools version, platforms -- and **what
      it was verified with**: rustc stable, kotlinc, Gradle, JDK, Swift,
      the nixpkgs revision, so a release can be reproduced. A check that the
      newest entry matches `dependencies.toml` whenever `VERSION` is a
      released version
- [x] The Gradle module metadata already carries `org.gradle.jvm.version=21`,
      so a Gradle consumer on an older JVM is refused at resolution with a
      clear message; the page says so, and that Maven consumers get no such
      guard -- the compatibility page's Kotlin section says both

---

## Backlog: the first upstream report

The `report` group's first issue (October 2026), verbatim in substance:

| dependency | current | upstream | reaches users |
|---|---|---|---|
| rust (MSRV) | 1.75 | stable is 1.99.0 | yes |
| swift-tools | 5.9 | Swift 6.4.0 is out | yes |
| jvm | 21 | not queried | yes |

and: swift-syntax 604.0.0 exists, beyond major 509, which needs swift-tools
raised. Each is `manual` -- a promise to users -- so the job reports and never
changes them. Decisions, not chores:

- [x] **Rust MSRV, 1.75 -> 1.94** (October 2026, on the owner's direction;
      ships in the next minor release, 0.3.0, since 0.2.0 is out). The rule,
      now in RELEASING.md: the newest stable at least six months old when
      raised, raised in a minor release and only for a reason. 1.94.0
      (2026-03-05) qualifies, and is in the pinned rust-overlay
      (2026-09-16), which 1.99.0 (2026-10-01) is not. All ten sites moved
      with it -- the workspace and four examples' `rust-version`, the
      formatter's, both `rust-toolchain.toml`s, the Nix pin -- and a raised
      toolchain floor is now a row in RELEASING.md's breaking-change table
      (minor). Nineteen releases of new lints, scanned for in advance since
      `clippy -D warnings` runs on the MSRV and no clippy runs where this was
      written: two `map_or(true, ..)` became `is_none_or` (unnecessary_map_or,
      1.84), and the two format calls inlinable in full became
      `{st:label_w$}` / `{state:row_label_w$}` (uninlined_format_args, warn
      by default since 1.88; mixed calls are not reported). No hits for the
      others looked for (doc_lazy_continuation, needless_lifetimes on impls,
      legacy numeric constants, unexpected cfgs). The first run named one the
      scan had not looked for: `redundant_guards`, which now treats
      `if effects.is_empty()` on a slice as a pattern (`effects: []`) --
      `to_grid`'s `Cell::Go` arm. The look-alike guards elsewhere test a
      `Vec`, a `BTreeMap` or a variable outside the pattern, which no
      pattern can express, so they are not reported.
      The next run found the compiler's own wording moved: rustc 1.94 reports
      a missing bound reached through a generated bundle by the bundle's name
      (`the trait bound `Impl: Handlers` is not satisfied`), where 1.75 named
      the leaf (`Impl: Perform<Timer, StopClock>`), with the leaf now in a
      label. Two compile-fail fixtures asserted the old headline:
      `missing_perform_impl.rs` (through `Handlers`) and, by elimination --
      the run's tail showed one failure of two, the other sorts before the
      first visible pass -- `child_hole_breaks_parent.rs` (a parent's step
      requiring its child's cells). Both now expect only the leaf bound,
      `Perform<Timer, StopClock>` and `Handle<Retry, Waiting, Elapsed>`: the
      fact each fixture exists to prove, a substring of both compilers'
      output, and in neither fixture's source, so rustc's echoed source lines
      cannot satisfy it. And the harness now prints rustc's whole output
      when a fixture fails, not three `error` lines, so a moved message is
      read once instead of guessed at.
      The prose that said "1.75" now names the MSRV without a number, and the
      Rust page takes it from `dependencies.toml`, so the next raise cannot
      leave it stale. Originally recorded: Raising it is a minor-version change in 0.x
      (RELEASING.md, "Versioning") and drops every user on an older
      toolchain; keeping it costs the library nothing today, since it has no
      dependencies and uses no newer language feature. Decide what would
      justify a raise (edition 2024 needs 1.85; a feature the macro wants),
      write that rule into RELEASING.md, and raise only when a rule fires.
      Stable's number alone is not a reason
- [ ] **Swift tools, 5.9, and swift-syntax 509.** Blocked first by the
      toolchain, not the decision: nixpkgs' Swift is 5.10.1 (Darwin's
      `check-darwin` log shows `swift-5.10.1-lib`), so `swift-tools-version:
      6.x` would not build here at all. Once nixpkgs ships Swift 6: tools 6.0
      turns on the Swift 6 language mode for the package (strict concurrency
      -- `Sendable` checking for every public type and the stores' actors),
      and swift-syntax's major follows the toolchain (6.4 is 604), so the
      macro package moves with it. Both change what users need; one 0.x minor
      release, together
- [x] **JVM target, 21 -- decided: no bump for now** (owner, October 2026).
      The question returns when there is a reason to require a newer LTS.
      - [x] **The report shows the newest LTS** (it said "not queried"): "newest
            LTS is 25 (newest release 27)". The newest GA release comes from
            OpenJDK's own tags (`jdk-NN-ga` in `openjdk/jdk`, read with `git
            ls-remote`, as swift-syntax's are), and the LTS is derived from the
            published two-year cadence since 17 -- 17, 21, 25, every fourth
            release. Adoptium's API and endoflife.date, which state LTS
            outright, could not be reached to confirm their formats, and a
            schema guessed is worse than a rule documented; if the cadence ever
            changes, this line of `tools/upstream` changes with it
      Originally: **JVM target, 21.** Reported as "not queried" because nothing in the
      job asks for the newest LTS. Raising the bytecode target cuts off every
      consumer on an older JVM (Gradle module metadata refuses them at
      resolution; Maven consumers get a class-file error). 21 is the current
      LTS line the jars need; the question is only when the next LTS is
      worth requiring. Teach `tools/upstream` to report the newest LTS (a
      source that publishes it, queried like the others) so the row says
      something
- [x] The report issue carried the pull requests' footer ("The checks on
      this pull request are the ordinary ones..."), which is wrong for an
      issue. It now says what the issue is for: these are never changed by
      the job, decide or leave them

---

## Step as a box: Functor, Applicative, Monad

Requested October 2026: the minimal functional toolkit -- `map`, `flatMap`,
an applicative `zip` -- on the values a machine produces, so a cell can be
written by composing small steps rather than by hand-assembling one.

**The box is `Step<S, F>`**, in all three languages: an outcome, `Go(S) |
Stay | Ignored`, and the ordered effects the cell emitted. Read as a type,
that is a Writer (the effects are the log) around an Option with two empty
cases. Half of the toolkit already exists and is lawful:

| | Rust | Kotlin | Swift |
|---|---|---|---|
| functor over the state | `map_state` | `mapState` | `mapState` |
| functor over the effects | `map_effect` | `mapEffects` | `mapEffects` |
| pure | `Step::go(s)` | `Step.go(s)` | `.go(s, effects: [])` |
| **monad** (`flatMap`) | -- | -- | -- |
| **applicative** (`zip`) | -- | -- | -- |

**Semantics, proposed** (normative once accepted, in `spec/cells.md`):

- `flatMap(f)`: on `Go(s)`, run `f(s)` and return its outcome, with this
  step's effects followed by `f`'s. On `Stay` or `Ignored`, return the step
  unchanged and never call `f` -- there is no state inside them to pass, and
  a cell that stayed or ignored has decided. The two empty cases stay
  distinct, as everywhere else (ARCHITECTURE 2).
- Laws, with effects compared in order: left identity
  `go(a).flatMap(f) == f(a)`; right identity `m.flatMap(go) == m`;
  associativity. All three hold under the rule above, because effect
  concatenation is associative and the short-circuit is the same at every
  level.
- `zip(other)` / `zipWith(other, g)`, the applicative, defined as the
  monad's derivation so the two can never disagree:
  `a.flatMap { x -> b.mapState { y -> g(x, y) } }`. Both `Go`: `Go(g(x,
  y))`, effects `a` then `b`. `a` not `Go`: `a`, and `b`'s effects are
  **dropped** -- `b` is a value already computed, but its result is never
  reached. `a` is `Go` and `b` is not: `b`'s outcome, effects `a` then `b`.
  The dropped effects are the cost of agreeing with `flatMap`; the
  alternative (keep both logs on a short-circuit) is a different, non-monadic
  applicative and is D2 below.
- What it is for, to be written as a happy path (`spec/happy-paths.md`): an
  entry action chained onto a transition (`go(Validating).flatMap(::enter)`),
  a guard that either moves or stays, and two orthogonal sub-decisions
  combined with `zipWith`.

**Decisions** (all three made, October 2026):

- [x] D1, names: **language-specific**, each language's own idiom for
      these operations, decided as:

      | | Rust | Kotlin | Swift |
      |---|---|---|---|
      | functor (state) | `map` | `map` | `map` |
      | monad | `and_then` | `flatMap` | `flatMap` |
      | applicative | `zip_with`, `zip` | `zip(other, transform)`, `zip(other)` | `zip(_:with:)`, `zip(_:)` |
      | fallible monad (Rust's capacity) | `try_and_then` | -- | -- |

      Rust follows `Option`/`Result` (`map`, `and_then`) and `Iterator`
      (`zip`); Kotlin follows its standard library, where `zip` takes an
      optional transform; Swift follows `Optional` (`map`, `flatMap`) and
      its argument-label convention. `map_state` / `mapState` stay as
      deprecated aliases until 1.0. What was recommended: the state functor is `map` in all three
      (`Option::map` / `Result::map` map the success value, and so does this),
      `map_state` / `mapState` kept as deprecated aliases until 1.0 under the
      versioning policy, since Maven Central already has 0.1.0. The monad is
      `and_then` in Rust (`Option`/`Result`'s name) and `flatMap` in Kotlin
      and Swift; the applicative `zip_with` / `zipWith`, plus `zip` returning
      a pair
- [x] D2 (accepted: drop the right-hand effects), the applicative on a short-circuit: drop the right-hand effects
      (lawful, agrees with `flatMap`; recommended) or keep both (a second
      applicative, surprising next to `flatMap`)
- [x] D3 (accepted: `emit` on an ignored step panics, `try_emit` returns it), Rust's `Ignored` with effects. `spec/cells.md` says an ignored
      step has no effects, and Kotlin's `Ignored` and Swift's `.ignored`
      cannot hold any, but Rust's `Step::ignored().emit(e)` builds one --
      nothing in the tree does, and nothing stops it. It must be settled
      first, because `flatMap`'s right identity is stated over steps the spec
      allows. Recommended: `emit` on an ignored step panics, like a capacity
      overflow (a programming error the type cannot rule out without
      splitting `Step`), with `try_emit` returning it as an error

- [x] **D4, found while writing the cases: what `and_then` returns when the
      continuation ignores.** `go(1)[a].and_then(|_| ignored)` would, read
      literally ("`f`'s outcome, with this step's effects followed by `f`'s"),
      be `Ignored` carrying `[a]` -- a step the spec forbids and D3 now
      refuses to build. **Implemented: `Ignored` absorbs** -- the result is
      `ignored` with no effects: a decision "not applicable" anywhere is not
      applicable as a whole. It is the only rule consistent with spec/cells.md
      and the laws (both identities and associativity checked over every
      outcome combination, by hand and by `tests/step_algebra.rs`), and it
      makes `zip` with an ignored right side ignored. **Decided by the owner:
      never panic; prefer a type that makes the absorption visible, unless
      that is costly or breaks the API -- then absorb.** Both typed designs
      were costed. A new outcome (`Absorbed`, carrying the dropped effects) is
      a new variant of `Outcome` / `Step` in all three languages: it breaks
      every exhaustive `match` / `when` / `switch` over them, including the
      dispatchers the macro and both generators emit and users' own handlers,
      and it is an outcome no matrix can declare, so the renderings, lints and
      conformance format would all have to learn it -- costly *and*
      breaking, even inside the 0.2.0 that is breaking anyway. An opt-in
      strict variant (`and_then_strict`, returning the would-be-dropped
      effects as an error) is additive, but leaves the default exactly as
      silent, so it does not meet the goal either. **So: absorb**, as
      implemented, specified in spec/cells.md 6 and documented on every
      language page
- [x] **The release that ships this is 0.2.0, not 0.1.6** (confirmed by the
      owner: `nix run .#release -- 0.2.0`). D3 changes
      behaviour -- `Step::ignored().emit(e)` used to run and now panics --
      and RELEASING.md's test ("does an unchanged implementation still
      behave the same?") says that is breaking; one `VERSION` for all three
      languages means 0.2.0 everywhere. The combinators themselves are
      additive

**Tasks, in order, after D1-D3:**

- [x] `spec/cells.md` 6: the combinators' definitions, effect order, D4's
      absorption, capacity, and the laws
- [x] ~~`spec/happy-paths.md`: the three uses above~~ -- **a mistake in this
      plan, caught before it was made:** "happy paths" is a named feature of
      this library (a machine's success spine, declared in the matrix), not a
      file of use cases, and composition examples there would have mixed two
      unrelated designs. The uses are on each language page instead, from
      compiled and asserted code
- [x] Shared cases, `spec/conformance/step-algebra.cases` (29 cases, every
      outcome combination for each operation, effects in every position; its
      format in `spec/conformance/README.md`): every combination
      of `Go`/`Stay`/`Ignored` with zero, one and two effects on each side,
      for `map`, `and_then`/`flatMap` and `zip_with`, with the expected step
      -- read by all three harnesses, so the definition is one file and three
      implementations cannot drift. Cross-language parity is the repository's
      first rule; laws only checked per language would not catch two
      languages lawful in different ways
- [x] **Rust** (expected green, not yet observed under `nix flake check`):
      D3 (`emit` panics on an ignored step, `try_emit` returns
      `EmitError::Ignored`/`Capacity`), `map`, `map_state` deprecated,
      `and_then`, `try_and_then`, `zip_with`, `zip`; usage in `Step`'s type
      comment (with a doctest), none on the functions, per ARCHITECTURE 15;
      `tests/step_algebra.rs` enumerates every step over a small domain
      against six continuations for the functor, monad and applicative laws,
      absorption, D3 and capacity; the conformance harness replays the cases
      and enforces their completeness. The macro is unchanged: its delegation
      arm re-emits a child's effects, an empty loop for an ignored child under
      the spec, and rewriting it with `map_effect` would force the child and
      parent onto one capacity `K`. Originally planned:
      `map`, `and_then`, `try_and_then`, `zip_with`, `zip` on `Step`
      and the corresponding `Outcome` methods; `no_std`, no allocation. The
      effects concatenate into the same capacity `K` -- const-generic
      arithmetic (`K1 + K2`) is not stable -- so overflow panics as `push`
      does, and `try_and_then` returns `CapacityError` instead. Law tests by
      exhaustive enumeration over small domains (no `proptest`: the library
      and its tests have no dependencies, ARCHITECTURE 16)
- [x] **Kotlin** (expected green, not yet observed): `map`, `flatMap`,
      `zip(other, transform)`, `zip(other)` as extensions on `Step`, keeping
      its variance (`Stay` and `Ignored` pass through as themselves);
      `mapState` deprecated with `ReplaceWith("map(f)")`; usage in `Step`'s
      KDoc. `test/StepAlgebra.kt` enumerates the same domain as Rust's for
      the functor, monad and applicative laws, absorption and the dropped
      effects, run by `test/Main.kt`. Not `inline`, as first planned: the
      operations are small and `inline` would freeze their bodies into every
      caller's bytecode, a binary-compatibility cost for nothing measured
- [x] **Swift** (expected green, not yet observed): `map(_:)`,
      `flatMap(_:)`, `zip(_:with:)`, all `rethrows`, and `zip(_:)`;
      `mapState` deprecated, `renamed: "map"`; usage in `Step`'s doc comment.
      `TabularCenterCheck/StepAlgebra.swift` holds the laws; `zip(_:)`'s pair
      is checked through `target` and `effects`, since tuples are not
      `Equatable`
- [x] The three conformance harnesses replay `step-algebra.cases` and each
      fails on a missing outcome combination itself, rather than through
      `fixtures-complete`, which knows only `.tbl` fixtures. Same parse,
      build, render-as-text and completeness logic in all three
- [x] Docs: each language page gains "Composing steps", its samples included
      by regex from a small demo -- a door that unlocks, chiming on entry,
      and two doors opened with `zip` -- that each language's test suite also
      asserts (`composing_a_cell`, `composingACell()`), so the page cannot
      show code that does not compile or does not do what it says; README
      gains a paragraph and the per-language names table (the "API table"
      this item named does not exist; the README has no API table to extend);
      ARCHITECTURE 2 says why `Step` is the box, why the empty cases
      short-circuit, and why `Ignored` absorbs
**Not in scope**, recorded so it is not mistaken for an omission (a note,
not a box -- it can never be closed): async
      combinators (`AsyncHandle` cells await before returning a `Step`, so a
      `Step` is already a value), traversals over effects, and a monad over
      `Ctx` -- shared state threaded by the machine, not by values

---

## Cleanness: comments out of source

Decided October 2026 (ARCHITECTURE 15): source and configuration read
without comments, except a file's header -- its high-level design and how to
use it -- and the comment on a type (trait, struct, enum, class, interface,
object, protocol, actor, type alias, `macro_rules!`) explaining it and its
usage. Why a file is the way it is otherwise lives in `ARCHITECTURE.md` and
here. About 10,500 comment lines across some 340 files when decided, so
staged like the rename -- one file type per patch, each green on its own --
with `tools/no-comments` enforcing exactly the types already migrated
(`clean_patterns`), so nothing migrated can regress while the rest waits.

Per stage, Stage 2's method -- read every comment, write the headers, move
the reasons, strip mechanically, prove the only non-comment change is the
intended one, and emulate `no-comments` over every file in scope before
enabling it: read every comment; keep or write the file's header and each
type's comment, as orientation and usage rather than history; move the rest
a reader needs (design and constraints to ARCHITECTURE, the section it
belongs to or 16 for build configuration; history and findings here;
normative behaviour to `spec/`);
rename where a name can say what the comment said; delete the rest; add the
type to `clean_patterns`. Two hazards to check each time: `tools/docs`
includes samples by regex anchors, and an anchor that matches a comment line
must move with it; and a comment some tool reads must stay, and be listed in
ARCHITECTURE 15's exemptions and `is_directive` if it is not already.

- [x] The rule, its exemptions, and `tools/no-comments` (root step and check
      `no-comments`): both comment syntaxes, string literals, Kotlin/Swift
      triple-quoted strings and shell heredocs skipped, so generated text and
      markdown headings written by a script are not comments. Written to
      the rule, as is everything since the decision (`tools/asm-diff`, the
      `licenses` step, the signing key-ID fix)
- [x] **The rule revised, on the owner's direction:** file headers and type
      comments stay. The first version allowed no prose comments at all,
      which took the orientation a reader needs on arriving at a file, and
      the usage guide a trait or protocol needs, out of the one place they
      are read. `tools/no-comments` now holds each comment block until the
      next code line and allows it as the header (nothing but comments and
      blank lines before it) or when it attaches to a type declaration,
      directly or through attribute/annotation lines; every other block, and
      every trailing comment, is reported
- [x] **Stage 1: `*.toml`, `*.yml`, `*.yaml`** -- 18 files, 186 lines removed. The
      rationale is ARCHITECTURE 16, "Cargo manifests and toolchains" and
      "GitHub workflows". Every file parses to the same data as before
      (checked by loading both versions); only the pinned actions' `# vX`
      annotations remain, which Dependabot reads. Under the revised rule the
      seven files that opened with a header (`publish.yml`,
      `swift-mirror.yml`, `pages.yml`, the examples workspace, `05-iced`'s
      manifest and toolchain file, `tabular-center-fmt`'s manifest) have it
      back, verbatim; mid-file comments stay out, their reasons in 16
- [x] **Stage 2: `*.nix`** -- 28 files, 985 lines removed. Every file opens
      with a header saying what it is and how to use it (the language
      flakes' explanation used to sit after `{ description = ...; }`, not at
      the top); the reasons are ARCHITECTURE 16's five "Nix" parts, grouped
      by theme, so the `patchShebangs` and check-inputs explanations, once
      repeated verbatim in four files, are stated once. Two were stale and
      are corrected rather than moved: `nix/context.nix` still said Maven
      publication needed a Gradle build the library did not have, and the
      formatter's checks said alignment was "not yet a check" (it is
      `tb-aligned`). Checked mechanically: across all 28 files the only
      changed line that is not a comment or a blank is the one trailing
      comment removed, and no heredoc body held a `#` line, so no generated
      file changes
- [x] **Stage 3a: the smaller shell scripts and repository files** --
      `tools/docs`, `gradle-lock`, `swift-lock`, Rust's `compile-fail`,
      `central-bundle`, the formatter's `verify`, `.editorconfig`,
      `.gitignore`; 427 lines removed. Reasons to ARCHITECTURE 16, "Scripts
      and repository files". `no-comments` now also takes a `clean_files`
      list, since scripts have no extension to match. Checked: the only
      changed code line is one trailing comment; shellcheck's findings are
      identical before and after; every heredoc and quoted line is
      byte-identical (536 in `tools/docs`, the site's prose). The
      formatter's `verify` header said alignment was "not yet wired" --
      stale, it is `tb-aligned`; `.gitignore` listed two patterns twice
      - [x] `justfile` needs no change: the comment above each recipe is
            its description in `just --list`, read by a tool, so it is
            exempt (ARCHITECTURE 15) and `no-comments` allows a comment
            directly above a recipe line
      - [x] **A bug in `no-comments`, found before it shipped.** It looked
            for a heredoc marker after stripping quoted text, so
            `prose <<'MD'` lost its `'MD'`, the heredoc went unrecognised,
            and every markdown heading `tools/docs` writes read as a comment.
            Found by emulating the checker over every file in scope before
            enabling it, which is now part of each stage's method; it now
            detects the marker on the raw line
- [x] **Stage 3b: the four `verify` scripts** (root, Rust, Kotlin, Swift) --
      1,248 lines removed, the longest rationale in the tree. Each opens
      with a header of usage and steps; the reasons are ARCHITECTURE 16,
      "The checks, step by step", one entry per step, with the four shared
      mechanisms (ledger, verdict, missing directory, portability) stated
      once in "Scripts" rather than four times. Much was history already
      told in this file and is deleted, not moved. One stale claim dropped:
      "Kotlin builds with kotlinc directly -- no Gradle", which predates the
      offline Maven repository. Checked as before: the only changed code
      lines are four identical trailing comments; shellcheck's findings and
      every quoted and heredoc line are identical; no step parses its own
      script's comments; the checker emulation is clean over all 61 files in
      scope
      - [x] **The classifying lexer was wrong, and stage 3a was re-verified.**
            It did not model a command substitution inside double quotes
            (`"$(sed -n 's|...|')"`), where bash starts a fresh quoting
            context, so it lost sync and labelled ~170 Kotlin and Swift
            comments as string content. Its failure mode was to leave
            comments in place, never to remove code, but a lexer that is
            wrong is wrong: it now keeps a context stack for `$(...)`, every
            comment classifies as code (counts match the raw totals), and
            stage 3a's heredoc and quoted lines were re-checked identical
            with it
- [x] **`#![warn(missing_docs)]` removed from the Rust library.** The first
      new functions written to the rule (`Step`'s combinators, 0017) failed
      `clippy -D warnings` with "missing documentation for a method": the
      lint requires a doc comment on every public item, and ARCHITECTURE 15
      says functions have none. rustc has no lint that separates types from
      functions, so the rule and the lint could not both stand, and stage 4
      would have met the same wall on the first doc comment it removed.
      ARCHITECTURE 15 says so, so nobody restores it
- [x] What `missing_docs` enforced that the rule keeps: every public type,
      trait and macro carries a comment, and every module a header. **Rust:
      done in stage 4b** (`documented_paths`), **Kotlin in stage 5** (`core`,
      `annotations`), **Swift in stage 6** (`Sources/TabularCenter`)
- [x] **Stage 4a: Rust outside the library** -- tests and compile-fail
      fixtures, the bench, the conformance crate, the examples,
      `tabular-center-fmt`: 68 files, 578 comment lines and 4 trailing
      comments removed. Four files kept their main explanation in the first
      block after the `use` lines (`scale.rs`'s "A genuine 8x12 machine, to
      retire a risk"); those blocks are promoted into the file header rather
      than deleted. What a reader needs is ARCHITECTURE 16, "Rust tests,
      examples and the conformance harness". The column-label exemption now
      covers a label line directly above a matrix row in any file, since test
      matrices are not all `.tb.rs`.
      Checked: lexed old and new, every file's code lines (string literals
      included) are identical but for the four trailing comments; no new
      blank line where rustfmt would remove one (start or end of a block, a
      double blank); no removed comment held a doctest; the only removals
      inside list contexts were struct-field docs and a comment between match
      arms, which rustfmt never collapses
      - [x] **A lexer bug caught by its own review list**: `tabular-center-fmt`'s
            tests feed the formatter matrices inside multi-line raw strings,
            `// idle` comments included, and a per-line lexer took those for
            comments. Removing them would have changed the formatter's test
            inputs. The lexer now carries string, raw-string and
            block-comment state across lines
      - [x] `no-comments` learned Rust: a character scanner carrying string,
            raw string (`r#"..."#`, and Kotlin/Swift `"""`), char literal and
            block-comment state across lines, the matrix-row label rule, and
            `clean_paths` for path-scoped enforcement (the library's `src/`
            waits for 4b). Ported line for line and run over the 68 files:
            zero findings; run over their originals as a negative test: 582,
            exactly the 578 lines and 4 trailing comments removed, and none of
            the text inside the formatter's raw strings
- [x] **Stage 4b: the Rust library**, `tabular-center-rust/tabular-center/src`
      -- 11 files, 615 lines removed. Module headers and the comments on
      public types and on `transition_matrix!` stay. Member docs -- enum
      variants, struct fields, trait and inherent methods, free functions --
      are not deleted but **folded**: each becomes one line in its type's
      comment (`- \`go\`: Transition to \`next\`, emitting nothing.`), or in
      the module header for free items, so docs.rs still says what every
      member is for while the code reads clean. The one doctest in a removed
      doc (`emit`'s) moved into `Step`'s type-level example. The macro's
      maintainer notes are ARCHITECTURE 11.1, "How the macro is built"; the
      rest is 16, "The Rust library's internals".
      Checked as in 4a: code identical in all 11 files (strings included), no
      new blank-line hazards, and the only added lines are folded member
      lists and the relocated doctest line
      - [x] **One rustfmt regression, found by `rust-fmt` after landing**:
            `DriverError::QueueFull { capacity }` had been held vertical by
            the doc comment on `capacity`; without it, rustfmt puts the
            variant on one line. The review had treated field docs as safe
            because rustfmt never collapses a `struct` item, but struct-like
            *enum variants* follow `struct_variant_width` (35), with one
            twist that explains why conformance's `CellSpec::Emit { effects }`
            stayed vertical with no comment at all: if any struct-like variant
            of an enum must be vertical (`Go { target, effects }`), rustfmt
            lays all of them out vertically. Applied to every enum in the
            tree, the rule predicts exactly the one diff the check reported.
            The list-context review 4a ran, but 4b had not, was rerun on the
            library: 26 removals, all at the start of a block (function
            bodies, `if`, match arms, trait bodies, macro rules), which
            rustfmt never folds into the opening line
      - [x] `no-comments` now enforces `*.rs` everywhere, and gains the
            documented check: in `documented_paths`, every file a header and
            every public type, trait and macro a comment. It flagged six items
            on first run, all undocumented before this stage too, and both
            kinds are not API: items the macro generates (`pub enum $a`) and
            `__tabula_*` helper macros. Both are excluded, and ARCHITECTURE 15
            says so. Emulated: clean on the library, 4 of 4 planted defects
            caught; the comment checker finds nothing in all 79 `.rs` files
            and exactly 615 in the library's originals
- [x] **Stage 5: Kotlin**, `*.kt` and `*.kts` -- 142 files, 1,424 comment
      lines and 3 trailing comments removed. Seven published files had no
      header (each began with `package`) and have one now; member KDoc in
      `core` and `annotations` folds into its type's KDoc as a list, primary
      constructor properties included, and free items into the file header;
      fourteen files' main explanation, sitting after the imports, is
      promoted to the header (one helper's KDoc excluded by hand). The
      rationale is ARCHITECTURE 16, "Kotlin generation and processing". Safe
      by construction: `//~ AT:` matches a line's content, not its number,
      and nothing reads `ReferenceTimer.kt`'s `GENERATED` marker.
      Checked: a Kotlin lexer with a mode stack (string templates holding
      nested strings, raw strings across lines, nested block comments) ends
      every file in code mode; code identical in all 142 files, template and
      raw-string contents included; all 17 Kotlin samples `tools/docs` cuts
      still match
      - [x] Two defects in the first folding pass, caught by reading its
            output and reverted, not patched: list lines indented one space
            too far, and extension properties (`val Step<*, *>.isIgnored`)
            named after their receiver
      - [x] `no-comments` enforces `*.kt` and `*.kts`; its scanner learned
            Kotlin string templates (`"${f("x")}"`), unexercised by today's
            tree but a desynchronisation waiting for the first one. Port
            results: nothing in the stripped tree; exactly 1,427 on the
            Kotlin originals, the 1,424 lines and 3 trailing comments removed
      - [x] The documented check covers `core` and `annotations`: public
            means not `private`/`internal`/`protected`, KDoc lines count as
            comment, multi-line annotations are skipped by parenthesis depth.
            Clean on all 18 published files; 3 of 3 planted defects caught
- [x] **Stage 6: Swift** -- 80 files, 1,340 comment lines and 1 trailing
      comment removed. Kept: `// swift-format-ignore-file` in all 18
      `.tb.swift` files, `// swift-tools-version:` on line 1 of each manifest,
      the macro fixtures' prose (all of it header), file headers and the
      comments on types. Member docs in `Sources/TabularCenter` fold into
      their type's comment; members of an `extension` whose type lives in
      another file fold into the file header. Eleven files' real explanation
      is promoted to the header. Rationale: ARCHITECTURE 16, "Swift packaging
      and generation".
      Decided along the way: a Swift `extension` counts as a type
      declaration (five `.tb.swift` files document theirs, "the matrix, in a
      file of its own"), and a `#if` line between a comment and its type does
      not detach it.
      Checked: the Swift lexer (interpolation with nested strings, `#"..."#`
      raw strings to any depth, multi-line strings, nested block comments)
      ends all 80 files in code mode; code identical in every file; all 12
      Swift samples `tools/docs` cuts still match
      - [x] **A checker bug caught by its own test case**: inside a string,
            the generic backslash-escape rule ran before the interpolation
            check, so `\(` was swallowed as an escape and interpolation never
            recognised. Interpolation now comes first, in the awk and the
            port. (The first version of that test was itself wrong -- it
            wrote `\\(`, an escaped backslash -- and was rewritten.)
      - [x] `no-comments` enforces `*.swift`, understands interpolation and
            raw strings, and the documented check covers
            `Sources/TabularCenter` (public means `public` or `open`). Port
            results: nothing in the stripped tree, now 301 source files;
            exactly 1,341 on the Swift originals; documented check clean on 7
            files, 3 of 3 planted defects caught
- [x] **Done.** `clean_patterns` and `clean_files` cover every file type in
      ARCHITECTURE 15's scope; the staging scaffold (`clean_paths`) is gone,
      and `no-comments`' header describes the finished tool. 6,811
      comment lines removed across stages 1-6, the reasons kept in
      ARCHITECTURE 16 and this file

Found while doing stage 1, not fixed here: `ci.yml` uses actions by moving
tag (`actions/checkout@v4`, the Determinate Systems actions `@main`) where
`publish.yml` and `pages.yml` pin every action to a commit. CI holds no
credentials, so it is not the release's risk, but a moved tag still changes
what runs on every push.

---

## Rename to `tabular-center`

The project becomes **tabular-center**, and each implementation directory is
named for it: `rust/` -> `tabular-center-rust/`, `kotlin/` ->
`tabular-center-kotlin/`, `swift/` -> `tabular-center-swift/`. Each of those
becomes a flake of its own -- `flake.nix`, `nix/` and `tools/` inside it --
and the root `flake.nix` composes the three.

Staged so that each step is one reviewable patch that leaves the tree green,
and so that the breaking part is last and alone. Nothing has been published
(Phase 10's publish box is open), so no stage needs a compatibility shim or a
deprecation period, and `VERSION` stays where it is.

### R1. Directories -- paths only

- [x] `git mv` the three directories. Nothing inside them is renamed
- [x] Every path that names them: `tools/`, `nix/`, `.gitignore`, `ci.yml`,
      the `justfile`, the docs, and the example manifests' `path =` lines
- [x] SwiftPM names a path dependency by its directory's basename, so
      `.product(name: "Tabula", package: "swift")` becomes
      `package: "tabular-center-swift"` in `examples/swift-examples` and in
      `tabular-center-swift/macros`. The one place a directory name is an identifier
- [x] Gradle is unaffected: included builds are named by `rootProject.name`,
      which each `settings.gradle.kts` already sets
- [x] `examples/<lang>/` keeps its name. It is not an implementation and the
      rename is about those

### R2. One flake per implementation, composed at the root

- [x] Each `tabular-center-<lang>/` holds `flake.nix`, `nix/` and `tools/`,
      and `nix flake check ./tabular-center-<lang>` checks that language
      alone, with only that language's toolchain in its closure
- [x] What moves: each language's `tools/verify` steps, toolchain, shells,
      checks and apps; the Kotlin Gradle lock and offline repository; the
      Swift lock, offline checkouts and `CompilerPluginSupport` build;
      `tools/compile-fail` (Rust), `tools/gradle-lock` (Kotlin),
      `tools/swift-lock` and `tools/swift-probe` (Swift). Each script's step
      bodies moved byte for byte; two comment blocks that had drifted away
      from their functions (the Kotlin-codegen note above `step_rust_gui`, the
      ktlint note above `step_no_bless`) went back to them on the way
- [x] What stays at the root: everything that reads more than one
      implementation -- `version`, `docs`, `renderings-agree`,
      `matrix-covered`, `diagnostics-coverage`, `diagnostics-tested`,
      `fixtures-complete`, `no-bless`, `no-generated` -- plus `release` and
      `publish`, `spec/`, `examples/` and the combined dev shell
- [x] **Still one definition of green.** Root `tools/verify` runs its own
      steps and hands every other step to the `tools/verify` that owns it, so
      `./tools/verify`, `./tools/verify test` and CI are unchanged. Step names
      are unchanged, and so are the root flake's check names
- [x] Each language flake reaches `spec/` and `examples/` through
      `self.sourceInfo`, which is the whole repository both when the flake is
      checked on its own from a git checkout and when the root composes it
      through a relative `path:` input (Nix 2.26 or later)
- [x] Each language flake's `flake.lock` pins the same revisions as the root's,
      and the root makes every shared input `follows` its own, so composing
      cannot fetch a second nixpkgs
- [x] `renderings-agree` needs all three toolchains in one derivation. The
      root takes them from each language flake's `legacyPackages.<system>`
      rather than rebuilding the list, so a toolchain is declared once. Each
      language renders through a `<lang>-render` step in its own script, into
      a directory the root names; the root only diffs
- [x] The root `verify` and `conformance` apps put Swift on PATH without the
      runtime library path every Swift check exports, so a Swift binary they
      built could not load libdispatch. They take the Swift flake's `setup`
      now, as `renderings-agree` does
- [x] Commit the root `flake.lock` that `nix flake lock` writes once the three
      relative inputs exist. Written by nix rather than by hand: the format of
      a relative-path node is nix's to decide. Done: CI composes the three flakes green on both platforms, which it could not do from an uncommitted lock

### R3. The name in prose and tooling -- nothing a user compiles against

- [x] Titles and descriptions: `README.md`, `ARCHITECTURE.md`, this file, the
      Kotlin and Swift READMEs, flake descriptions, dev-shell banners, and the
      prose that names the *project*. Prose naming the *library* ("the
      examples depend on tabula by path") stays until R4 renames the library;
      README says so up front
- [x] Derivation and app names: `tabula-check-<step>` ->
      `tabular-center-check-<step>`, `tabula-verify` ->
      `tabular-center-verify`, and so on; the offline Gradle repository and
      swift-syntax checkouts too. Store paths change, so the first run after
      this rebuilds everything, `swiftpm-plugin-support` included
- [x] Environment variables: `TABULA_OFFLINE`, `TABULA_MAVEN_REPO`,
      `TABULA_SWIFT_DEPS`, and R2's `TABULA_NESTED` and `TABULA_RENDER_DIR`
      -> `TABULAR_CENTER_*`, in the flakes, the scripts and the Gradle builds
      that read `TABULAR_CENTER_MAVEN_REPO`. `no-bless` already scans for
      the one variable that must never come back; it keeps doing so under
      either spelling
- [x] The repository URL: `https://github.com/tabula-center/tabular-center`,
      in `Cargo.toml` and in `tools/docs`, which also moves the docs base to
      `https://tabula.center` -- the address
      `spec/diagnostics.md` tells every message to end with

### R5. Each implementation owns its examples

- [x] `examples/rust` -> `tabular-center-rust/examples`,
      `examples/kotlin` -> `tabular-center-kotlin/examples`,
      `examples/swift-examples` -> `tabular-center-swift/examples`. The root
      `examples/` is gone; its README is split three ways, each keeping the
      shared framing (the same four machines, why these four) and only its
      own language's sections
- [x] Each example still depends on its library by path, the way a user
      would, now from inside the library's directory: `path = "../../tabula"`,
      `srcDir("../../core")` and `includeBuild("../../ksp")`,
      `.package(path: "..")`. Each set is still outside its library's build:
      its own cargo workspace, its own `kotlinc` and Gradle builds, its own
      SwiftPM package
- [x] `05-iced` gets its own `rust-toolchain.toml` (stable). It now sits under
      `tabular-center-rust/rust-toolchain.toml`, and rustup takes the NEAREST
      one, so under rustup -- ci.yml's check-no-nix -- it would otherwise build
      on the MSRV, which cannot parse iced's edition-2024 crates
- [x] The scans that listed the examples as a second root
      (`rust-matrix-stable`, `kotlin-matrix-stable`) now list one: the second
      would have been copied into the first (`examples/examples`) and each
      example matrix counted twice. `rust-matrix-stable` still formats both
      cargo workspaces in its copy, since `cargo fmt` never descends into a
      nested one. `kotlin-ksp-incremental` copies one tree instead of two
- [x] The Rust flake vendors the examples' crates from `../examples/*.lock`,
      a path inside its own directory, rather than through the repository root
- [x] **Independence, checked.** Each language's checks are handed only their
      own directory, `spec/` and `.editorconfig`, laid out as in the
      repository. A step that reached into another language, or anywhere else
      at the root, fails instead of working by accident. `spec/` is the one
      shared input, on purpose
- [x] `GRADLE_USER_HOME` is `tabular-center-kotlin/.gradle-home` in both dev
      shells, found from the git root. It was `./.gradle-home`, relative to
      wherever `nix develop` was typed
- [x] **Decoupled.** Each language check depended on the whole checkout's
      store path, so a change anywhere rebuilt every check even after each had
      been trimmed to read only its own subtree. Now its three inputs are
      separate store paths -- `builtins.path` on `./..`, `../../spec` and
      `../../.editorconfig`, each hashed by its own contents -- and a check's
      derivation depends on those and its toolchain alone. Path literals rather
      than `self.sourceInfo.outPath + "/spec"`: a string carries the whole
      checkout as its context, which is the dependency being removed.
      `self.sourceInfo` survives only as an evaluation-time guard -- a boolean,
      which carries no store path -- so a flake that cannot see spec/ still
      says why
- [ ] Confirmed on a real run: a Rust check's `drvPath` is unchanged by an
      edit under `tabular-center-kotlin/`, and changed by one under `spec/`.
      Written, not yet observed; the commands are in the patch's message

### The documentation site

The published site was the repository's README, rendered by Pages from the
branch -- not the site `tools/docs` builds, which `pages.yml` was building and
uploading for nobody. So the page a visitor saw carried a note about the
rename, a development section, and one Rust sample.

- [x] `tools/docs` writes a front page and a page per language -- Rust,
      Kotlin, Swift -- beside the spec pages it already rendered. Each language
      page walks the same Timer: the matrix, the code you write around it,
      what the generator produces, the compiler's message when a cell is
      missing, composition, colors and setup. The front page leads with the
      matrix and the measured 8x12 machine (96 cells, 9 methods written,
      asserted by `scale.rs`)
- [x] **Every sample is included from the tree**, by file and line range, at
      generation time -- never pasted. They are code CI compiles and runs, and
      the compiler messages are the `//~ EXPECT:` lines the compile-fail steps
      require, so a page cannot show a machine or an error that no longer
      exists. A range that stops matching fails `tools/docs`, and so
      `tools/verify docs`, rather than publishing a page with a hole in it
- [x] Honest about Swift: the `@Machine` surface shown is the block
      `TabulaMacroSyntaxCheck` parses on every run, and the page says the
      macro is pending and shows the form written today
- [x] The README's rename note is gone; it points at the site instead
- [x] **`doc/`, committed.** The first version relied on Pages' source being
      set to GitHub Actions; it was left on the branch, so only the README was
      a page and every language link was a 404. The pages are now written to
      `doc/` and committed, and Pages serves them from the branch at
      `/tabular-center/doc/` with no setting to get right. `pages.yml` is
      removed: it built an artifact nothing served. This reverses Open
      decision 0 ("docs/ is no longer committed") -- deliberately, and with the
      cost that decision named paid in a check: `tools/verify docs` now
      regenerates and diffs against the committed `doc/`, so a stale page
      fails CI and the fix is `./tools/docs` and a commit. The docs base
      diagnostics link under is `.../tabular-center/doc`
- [x] The language pages name the libraries by their current identifiers
      (`tabula`, `dev.tabula`, `Tabula`). R4 changes them; the pages follow in
      the same patches, since the samples are included from the renamed code -- done: R4 renamed them and regenerated `doc/`

### CI

- [x] `ci.yml` was an invalid workflow file, so none of its jobs ran:
      `check-darwin` was gated on `hashFiles(...)` in a job-level `if`, which
      GitHub rejects. The gate was a leftover from before Phase 5 that always
      held; removed
- [x] **The first CI run found what local runs could not.** Every check died
      `/usr/bin/env: bad interpreter`: the scripts start
      `#!/usr/bin/env bash`, and a strict sandbox has no /usr/bin/env. Local
      runs passed with the sandbox relaxed. Each check builder now runs
      `patchShebangs` over its copy before any step, which also covers the
      scripts the verify scripts call by path
- [x] **And Darwin could not evaluate.** `rust-gui` listed wayland, X11,
      Vulkan and libGL unconditionally; nixpkgs refuses to evaluate `wayland`
      for Darwin, and one refused package fails the whole platform's
      evaluation. Linux-only now -- iced on macOS uses Metal from the SDK
      stdenv carries -- and the X11 names are written `libx11 or xorg.libX11`
      across the `xorg` rename
- [x] **Same flake.lock, different JVM.** Nix pins the JDK, not which JVM
      Gradle picks: Gradle auto-detects installations, the Darwin sandbox is
      not sealed, and on the macOS runner it found the runner's JDK 17 and
      loaded a KSP processor our 21 had compiled ("class file version 65.0").
      `JAVA_HOME` was also the JDK's package root, which on Darwin is not a
      Java home. Now `jdk.home` everywhere, and each check writes
      `org.gradle.java.home`, `org.gradle.java.installations.paths` and
      `auto-detect=false` into its own `GRADLE_USER_HOME/gradle.properties`,
      so our JDK is the only JVM Gradle can see -- without a store path in any
      committed file
- [x] **A lock made on one platform.** Compose Desktop's artifact is chosen by
      OS and CPU, so the lock generated on Linux had no
      `desktop-jvm-macos-arm64`. `07-compose` takes `-PdesktopTarget` and has
      a `resolveForLock` task; `tools/gradle-lock` runs it for linux-x64,
      linux-arm64, macos-x64 and macos-arm64 into one cache
- [x] **The apps were not pinned.** 0011 pinned the JVM inside the checks;
      the JDK-17 error came back from `nix run .#gradle-lock -- --check`, an
      app, which runs on the host and inherited the Ubuntu runner's
      `JAVA_HOME` (Temurin 17). The `gradle-lock`, Kotlin `verify` and root
      `verify` apps now export `JAVA_HOME` and `TABULAR_CENTER_JDK_HOME`, and
      every Gradle run in `tools/gradle-lock` and the Kotlin `tools/verify`
      passes the same three pins when it is set. Tell-tale for next time: a
      nix check's log lines carry the derivation's name; an app's do not
- [x] **`nm -D` is ELF-only.** `swiftpm-plugin-support`'s symbol check stopped
      the Darwin build ("no dynamic symbol table") after the build itself had
      succeeded: Mach-O has no ELF dynamic table, whatever nixpkgs names the
      file. `nm -gU` on Darwin; Linux's command is unchanged, so the Linux
      derivation does not rebuild
- [x] **"Stale" was locale.** `tools/gradle-lock` sorted the lock with a bare
      `sort`, which follows the locale: a desktop's en_US.UTF-8 ignores
      punctuation, CI's C compares bytes. Same 283 artifacts, different order
      (`annotation/1.9.1/` before or after `annotation-jvm/`), so the lock was
      current on the machine that wrote it and stale everywhere else.
      `LC_ALL=C` in `tools/gradle-lock`, and in `tools/docs`, whose diagnostics
      index is sorted the same way into a committed file
- [x] `swift-examples` named its failures only inline, far above the 25 lines
      nix shows of a failed check, so a macOS failure read "FAILED" under a
      passing spec-check. It now ends with the failing examples by name
- [x] **`NIX_CC` in the apps.** `swift-lock --check` ran in CI for the first
      time (the job used to stop at the gradle-lock check just before it) and
      SwiftPM reported malformed target-info JSON: `swiftc` had died on
      `NIX_CC: unbound variable` before printing anything. The checks set
      `NIX_CC`; the apps never did. `swiftSetup` exports it now, so every
      Swift entry point has it, and `swift-lock` prints `swiftc`'s own error
      when resolution fails instead of SwiftPM's summary of it
- [x] **macOS 13 APIs on a 10.13 target.** `String.contains(_: some
      StringProtocol)` is `@available(macOS 13)`; Linux has no availability
      gates, so 19 calls crept in unnoticed: 7 in `TabulaCheck`, 12 in the
      macro syntax check -- both internal, neither a library product.
      Replaced with a stdlib-only `containsText`, one internal copy per
      module, keeping the promise that the package asks nothing of a
      deployment target. Next time: a Linux-only green run says nothing about
      availability
- [x] **And a wrong fix, caught by the next run.** The first version also
      rewrote two calls in `TabulaCodegen/Emit.swift` and called them library
      exposure. They were `[String].contains(_:)` -- an element test, always
      available -- matched by a regex that saw the shape and not the type, and
      `swift-codegen` stopped compiling. Reverted, with a comment. Every
      remaining site's receiver was then checked to be a `String`
- [x] **`NIX_CC` was not enough for SwiftPM.** With it, `swiftc
      -print-target-info` answered correctly when asked directly, and SwiftPM
      still got an empty answer. An app gets a PATH and no SETUP HOOKS; a nix
      build and `nix develop` run them, and nixpkgs' Swift depends on what
      they export. The `swift-lock` app now `exec`s `nix develop
      ./tabular-center-swift --command tools/swift-lock` -- the environment
      the checks and the committed lock already came from -- rather than
      reconstructing it variable by guessed variable
- [x] **`codesign` in debug builds.** SwiftPM signs macOS debug executables
      with a get-task-allow entitlement using /usr/bin/codesign, which is not
      on a nix build's PATH. `swift-macros` is the one debug build (every
      other Swift step is `-c release`, which applies no entitlement) and now
      passes `--disable-get-task-allow-entitlement` on Darwin
- [x] **`observable-counter` did not compile on macOS.** Not a runtime
      failure and not an `ObservableStore` bug: the store is `@MainActor`,
      and the example used it from top-level code, which Swift 5.10 does not
      isolate to the main actor. The block is `#if os(macOS) || ...`, so no
      Linux run had ever compiled it; the first Darwin job was the first
      compiler to read it. Wrapped in `MainActor.assumeIsolated` (macOS 14,
      inside the existing `#available`) -- true, since top-level code runs on
      the main thread, and synchronous, so the checks still run before exit.
      `TabulaCheck` already did this properly; the example had not followed.
      The replayed output from the last patch is what showed it
- [x] **`swift-lock`: same dev shell, passes locally, fails on CI** -- so the
      host. `nix develop` adds to the host's PATH, the Ubuntu image ships its
      own Swift, and SwiftPM finds its compiler by discovery, not simply first
      on PATH; a foreign swiftc under nix's LD_LIBRARY_PATH printing nothing
      fits every observation. `tools/swift-lock` now sets SWIFT_EXEC, SwiftPM's
      override, to the swiftc it resolved, and on failure lists every swiftc on
      PATH. Confirmed: the next Linux run went green, lock check included
- [x] **Regenerate the lock** (`nix run .#gradle-lock`, needs network) and
      commit it. Until then `kotlin-compose` fails on macOS and CI's
      "gradle lock is current" step is red -- correctly: the committed lock
      does not match what the tool now resolves -- done, in byte order after the locale fix; CI's "gradle lock is current" step is green
- [x] `check-darwin` has never passed: the invalid workflow meant it never
      ran, so this is its first real outing. `rust-gui` building on macOS in
      the sandbox is expected, not yet observed -- it has now: the first fully green macOS run came after the `observable-counter` fix
- [x] `check-no-nix` removed. CI checks the Nix path only. `tools/verify`
      still runs without Nix -- the scripts are plain bash and nothing in them
      needs Nix -- but that path is supported and no longer exercised, and
      CONTRIBUTING says so rather than claiming a check that is gone

### Found by the first composed run

- [x] **`swiftpm-plugin-support`'s own assertion could lie, and did.** R3
      renamed its log prefix, which changed the derivation and forced its
      first rebuild in a while -- and it failed with "libPackageDescription.so
      defines no CompilerPluginSupport symbols" after both modules had
      compiled and linked cleanly. The check was `nm -D ... | grep -q`, and
      stdenv runs builders with `set -o pipefail`: `grep -q` exits at its first
      match, `nm` is killed by SIGPIPE writing the rest of a large symbol table,
      and pipefail reports the pipeline failed. Whether it lies depends on where
      in the output the first match falls, which is how it could pass once and
      fail on an identical rebuild. Now through a file, and on a real failure
      it says whether the object or the library lost the symbols
- [x] **The same trap in the definition of green.** Every `tools/verify` runs
      with `set -o pipefail`, and twelve places matched compiler output with
      `printf '%s' "$out" | grep -q`. With output past a pipe buffer and an
      early match, `printf` dies of SIGPIPE and a message that WAS there reads
      as absent: a compile-fail fixture reported FAIL for the right error, or
      `no-std` skipping its fallback. All twelve are here-strings now
      (`grep -q ... <<<"$out"`). Three pipelines are left, each fed a few lines
      at most -- a lock entry, a doc block, `--list-all` -- well under a buffer

### R4. Public identifiers -- the breaking stage, decisions first

Every name below is API. Each needs a decision before it needs work, and the
proposals are only proposals.

- [x] Rust: crate `tabula` -> `tabular-center` (imported as
      `tabular_center`), `tabula-conformance` -> `tabular-center-conformance`,
      directories renamed to match. `transition_matrix!` keeps its name: it
      names what it does, not whose it is. Things a find-and-replace would
      have missed: the harness imports its own library as
      `tabula_conformance` (underscore, so no `tabula::` to match); the
      compile-fail tool links `libtabula.rlib` with `--extern tabula=`;
      `default-run` names the binary, which takes the package's name; and
      `rust-conformance` was gated on `../tabula-conformance/Cargo.toml`
      existing, so after the move it would have vanished from
      `nix flake check` without failing. All three `Cargo.lock`s are the
      rename and nothing else, re-sorted as Cargo sorts them. One call
      crossed rustfmt's 60-column argument heuristic -- found by `rust-fmt`,
      because my pre-check matched only one level of parentheses and this one
      nests two; rescanned with a balanced matcher, arrays and struct literals
      included, and it was the only one. Kept: the hidden macro helpers (`__tabula_arms!` and kin), which no user sees.
      crates.io availability still to check before Phase 10 publishes
- [x] The runtime message prefix `tabula: ` -> `tabular-center: ` (the
      UNREACHABLE trap, the effect-capacity panic, the processor's and
      emitter's errors), in one commit across `spec/cells.md`, which defines
      the trap's format, and all three implementations. Nothing asserted the
      prefix: compile-fail expectations match the diagnostic code that follows
      it, and the one `should_panic` expects a substring after it
- [x] Kotlin: package `dev.tabula` -> `dev.tabularcenter` (one segment, as
      proposed), group `dev.tabula` -> `dev.tabularcenter`, artifacts
      `tabula-core` ... `tabula-testing` -> `tabular-center-core` ...
      `tabular-center-testing`. Source directories follow the package
      (`core/dev/tabularcenter/`, ...); `TabulaProcessor`,
      `TabulaProcessorProvider` and `TabulaError` become `TabularCenter...`,
      and the KSP service file names the new provider -- the one place a
      class name is data, where a stale entry is a processor that silently
      never runs. The three Gradle builds substitute
      `dev.tabularcenter:tabular-center-ksp` for the included processor,
      whose `group` and `rootProject.name` say the same. No option keys or
      generated-file names carried the brand. The Gradle lock is untouched:
      the processor comes from the included build, never from Maven. KSP
      compile-fail positions are matched by line content, and no line was
      added, so they cannot shift. Swift's own `TabulaError` is the Swift
      patch's
- [x] Swift: products, targets and modules `Tabula`, `TabulaTesting`,
      `TabulaCodegen`, `TabulaMacroSyntax` (and the checks, conformance,
      examples and pending macro targets) -> `TabularCenter...`; the package
      name follows; executables `tabula-check` / `tabula-conformance` ->
      `tabular-center-*`; Swift's own `TabulaError` -> `TabularCenterError`.
      Target directories moved, since SwiftPM finds `Sources/<Target>` by
      name. What depended on the names as strings: the scripts that
      `swift run` the executables (including the render step
      `renderings-agree` uses), `swift-probe`, and the emitter's
      `import Tabula` -- text inside `Emit.swift` that must match the module
      the build produces, which it now does. Checked and unaffected: the
      compile-fail and codegen steps find modules by directory, not name;
      no type is named like the module (it would shadow it); no matrix row
      mentions the module, so `swift-matrix-stable` is safe; and
      `workspace-state.json` records only the remote swift-syntax. With the
      three languages done, the only bare `tabula` left outside history is
      `tabula-fmt` and the runtime `tabula: ` prefix -- the next patch
- [x] `tabula-fmt` (backlog, unwritten) -> `tabular-center-fmt`, and
      `spec/tabula-fmt.md` -> `spec/tabular-center-fmt.md` with it (and its
      page in `doc/`). The `*.tb.*` matrix-file suffix is kept: it is short,
      unclaimed, and `spec/matrix-files.md` explains it without reference to
      the old name
- [x] Order: diagnostic codes first (the spec and all three at once, as the
      cross-language checks demand), then Rust, Kotlin, Swift, each green on
      its own before the next, then the message prefix and `tabula-fmt`.
      R4 is done: outside this file's history, the old name survives only in
      the GitHub organisation (`tabula-center`), the hidden Rust macro helpers
      (`__tabula_*`), and a quoted historical log line

### 0b. Two runs are needed, both needing network — done

Both have been run: `flake.lock` pins `nixos-26.05`, and `nix/gradle-lock.json`
is committed (108 artifacts, produced by gradle 8.14.4). Kept for the record:

1. **`nix flake update`.** `flake.nix` now asks for `nixos-26.05` instead of
   `nixos-25.05`, to get a Swift whose SwiftPM ships `CompilerPluginSupport` —
   the thing that actually blocks `tabular-center-swift/macros`, ahead of swift-syntax being
   remote. `flake.lock` still pins 25.05 and cannot be regenerated offline.
2. **One run of `./tools/gradle-lock`.** It resolves the KSP example against
   real repositories and writes `nix/gradle-lock.json`. Commit that and
   `examples/kotlin/06-generated` builds offline against pinned store paths,
   and the last avoidable skip in `nix flake check` is gone.

This item used to say "one build of `nix/gradle-deps.nix`", whose zeroed
`outputHash` would be replaced by the real one from the first failure — "the
normal workflow for a fixed-output derivation rather than a workaround". That
was true about fixed-output derivations and wrong about this one. See 0d: the
build never got as far as producing a hash, because the failure was resolution
rather than hashing, and a Gradle cache would not have hashed stably anyway.

The instinct behind it was right and is preserved: a build that fetches is what
`cargoDeps` and `vendorHash` exist for, and Gradle is no different. What
changed is *who* fetches. `cargoDeps` works because Cargo's download set is a
lockfile; Gradle has no equivalent, so 0d writes one.



### 0c. Kotlin was never checked by the flake — fixed

`nix/context.nix` gated every Kotlin check on `builtins.pathExists
../kotlin/src`. There is no `kotlin/src` and there never has been: the tree is
`kotlin/{core,annotations,testing,codegen,test,conformance,compile_fail,ksp}`
(`tabular-center-kotlin/` since the rename).
So `has.kotlin` was always false, `nix/checks.nix` dropped all six Kotlin
checks, and `ci.yml`'s `check` job — which runs `nix flake check` and nothing
else — ran none of them. Kotlin was covered only by `check-no-nix`.

The gate now names `tabular-center-kotlin/core/dev/tabula/Step.kt`, which is the file every
Kotlin step compiles first. Kotlin has no build file to gate on, deliberately
(ARCHITECTURE 11.2), so the core source is the honest stand-in.

Two things this is worth recording for:

- **A gate that names a path which does not exist cannot report that it is
  off.** `lib.optionalAttrs` produces a smaller attribute set, and a smaller
  set of checks is indistinguishable from a correct one in `nix flake check`'s
  output. The Rust and Swift gates were right, so the summary looked plausible.
- **Turning it on found two checks that had never run anywhere**, which is the
  usual yield of switching on a gate rather than the exception:
  1. `kotlin-examples` guarded `06-generated` on `command -v gradle`. The
     sandbox *has* gradle — `kotlinInputs` ships it — and has no network, so
     the guard tested for the wrong thing and the step would have failed while
     its message promised a skip. `mkCheck` now exports `TABULA_OFFLINE=1` and
     `tools/verify` reads it. Declared, not probed: nix knows and the script
     would be guessing.
  2. `kotlin-matrix-stable` is gated on ktlint being present *and* on
     `has.kotlin`. `check-no-nix` installs no ktlint and the flake dropped the
     check, so it had executed in neither. With `pkgs.ktlint` it runs — and the
     matrix it guards was in `tabular-center-kotlin/test/ReferenceTimer.kt`, outside the
     `[*.tb.kt]` exemption in `.editorconfig`. Moved to
     `tabular-center-kotlin/test/TimerSpec.tb.kt`; see `spec/matrix-files.md`, which had
     already written down that the library's own matrices had not moved yet.

`docs` was in `nix/checks.nix` but not in `tools/verify`'s default step list,
so the two disagreed about green in the other direction. Added.

### 0d. The KSP dependency problem, solved the other way round

`nix/gradle-deps.nix` was a fixed-output derivation: run Gradle in a sandbox,
let it reach Maven, hash the cache. It never produced an output. The last
failure was

```
Plugin [id: 'org.jetbrains.kotlin.jvm', version: '2.1.20'] was not found
  Searched in the following repositories:
    Gradle Central Plugin Repository
    MavenRepo
```

which is one sentence covering at least four distinct causes — no route, no
DNS, a CA bundle the JVM will not read, a repository that genuinely lacks the
artifact — and Gradle cannot tell the reader which. That is the first reason
this was the wrong shape. The second is that a Gradle cache does not hash
reproducibly: `caches/modules-2` carries lock files, `gc.properties`, and
binary descriptors keyed by absolute paths, so `outputHash` is a moving target
even when the network cooperates.

Replaced with the core of [gradle2nix](https://github.com/tadfisher/gradle2nix),
owned rather than depended on. The idea is to stop asking a nix build to
resolve anything:

- `tools/gradle-lock` runs Gradle **once, with network, outside nix**, and
  records every artifact as `{path, url, sha256}` in `nix/gradle-lock.json`.
- `nix/gradle-repo.nix` reads that and `fetchurl`s each artifact into a Maven
  layout. One artifact, one fetch, one pinned hash — the shape nix already
  knows how to make reproducible.
- `TABULA_MAVEN_REPO` points both Gradle builds at that directory.

gradle2nix recovers URLs with a Gradle plugin that queries the resolution
engine. `tools/gradle-lock` does it from outside, because Gradle's cache layout
is `files-2.1/<group>/<name>/<version>/<sha1>/<file>` and those four components
are exactly a Maven coordinate, which is exactly a path under a repository
root. Rebuild the path, try each known repository, keep the one whose bytes
hash to the bytes on disk. The hash comparison is the proof, not a
belt-and-braces check: a reconstructed URL that is wrong cannot pass it.

What this does not do is gradle2nix's other half — resolving configurations
nobody builds. It does not need to: the lock is generated by building exactly
what the check builds.

- [x] `tools/gradle-lock`, and `--check` wired into `ci.yml`'s `check-no-nix`
      job. That job has network and the nix jobs do not, so it is the only
      place lock drift can be caught.
- [x] `nix/gradle-repo.nix`, `nix build .#gradle-repo`, `has.gradleLock`.
- [x] `tabular-center-kotlin/ksp/settings.gradle.kts`. Its absence was recorded as "harmless
      for a build, wrong for publication" and stopped being harmless: an
      included build resolves plugins through its own `pluginManagement`, so
      without it the processor reached for the plugin portal no matter how the
      example was configured.
- [x] `gradle.properties` in both builds: `auto-download=false`. A toolchain
      provisioner is a network access no repository list governs, and
      `jvmToolchain(21)` invites one.
- [x] `kotlin-ksp` split out of `kotlin-examples` — its inputs are not just
      source, and a stale lock should not read as a broken example.
- [x] `nix run .#gradle-lock`, so the bootstrap uses the flake's pinned
      gradle, jdk and curl. A lock generated by whatever gradle was on
      someone's PATH is a lock nobody can reproduce, and a non-reproducible
      bootstrap poisons everything downstream of it.
- [x] The `kotlin-ksp` check is gated on `has.kotlin` alone, **not** on the
      lock existing. Without a lock it is present and RED, with the command
      that fixes it. Gating it on the lock was the obvious move and would have
      repeated 0c exactly: a check absent from the attribute set cannot report
      that it is absent, and `nix flake check` prints the same tidy summary
      either way.
- [x] A skip ledger in `tools/verify`. Every step's output is tee'd and
      anything saying `skip` is reprinted before the verdict. A skip is not an
      error, so nothing counted it; two suites hid behind that.
- [x] The lock records the Gradle version that produced it, and
      `kotlin-ksp` warns on skew. Two Gradle versions can want two different
      artifact sets for one build file, and when they do the replay fails with
      `Could not find <artifact>` against a directory that looks complete.
- [x] `--check` moved from `check-no-nix` to the `check` job, as
      `nix run .#gradle-lock -- --check`. Putting it in the no-nix job was
      wrong for the reason directly above: that job installs its own Gradle
      through setup-gradle, so `--check` there would have gone red on version
      skew rather than on a stale lock. `nix run` is not sandboxed, so the
      `check` job has both the flake's toolchain and a network -- the only
      place the question can be asked honestly.
- [x] **`nix run .#gradle-lock` once, on a machine with network, and commit
      `nix/gradle-lock.json`.** Done; the lock is in the tree. The one remaining out-of-band step, and the
      same kind of thing as `nix flake update` in 0b above: nix cannot pin a
      hash it has never seen. After it, `nix flake check` fetches every
      artifact itself and the KSP example runs in the sandbox like everything
      else.

No `--offline` anywhere in this, deliberately. It reads like the enforcing flag
and is the opposite: Gradle's offline mode resolves from the dependency cache
and refuses every external repository, and a `maven { url = file:// }` is an
external repository. The flag that looks like it implements this design is the
one that breaks it.

### 0a. Both build paths are checked

`tools/verify` never needed Nix — it is bash, and the flake's checks call it —
but nothing ran it without Nix, so "works without Nix" was documentation.
`ci.yml` now has a `check-no-nix` matrix on Linux and macOS with ordinary
toolchains.

It also reaches what the Nix jobs structurally cannot: the sandbox has no
network, so Gradle and KSP are skipped in all of them. With Maven available,
`examples/kotlin/06-generated` is the only consumer of the annotation processor
and this is the only job that exercises it. Expect it to be the noisy one:
`tabular-center-kotlin/ksp` has never executed and two bugs in its build file were found by
reading alone.

### 0. docs/ is no longer committed -- reversed

*Reversed in September 2026: the pages are committed again, as `doc/`, because
Pages serves from the branch; `tools/verify docs` diffs them against a fresh
render. See "The documentation site" under the rename. Kept for the reasoning.*


Generated output does not belong in the tree — the rule that keeps generated
dispatchers out of `examples/kotlin/06-generated` applies to `docs/` too, and
it was being broken by the patch that created it. `.github/workflows/pages.yml`
runs `tools/docs` and publishes the result as a Pages artifact; `docs/` is
gitignored.

`tools/verify docs` had to change with it: there is nothing committed to be
stale against, so it now checks that **every code in `spec/diagnostics.md` has
an anchor in the rendered page**. That found ten codes on its first run — the
lints are described as a group and in tables rather than as sections, so their
links would have resolved to nothing and dropped the reader at the top of a
long page. An `All codes` index now gives every code a landing point.



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
- [x] The `payload-hoist` fixture itself -- landed; see Phase 3

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

### 4. The KSP adapter has never run — superseded

It runs now: see 0d, and 0f below. The rest of this entry is the history of
getting there.

`tabular-center-kotlin/ksp/` was the only code in the repository that had never executed —
there is no Gradle, and KSP is a Maven artifact this environment cannot reach.
`tabular-center-kotlin/ksp/README.md` records what will break first, re-read against the code
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

`examples/kotlin/06-generated` is the consumer: a machine declared in
`@Machine` and `@Row` annotations, with its own `settings.gradle.kts` and
`build.gradle.kts` applying the processor by path. KSP generates the
dispatcher, the `Cells` interface and the effect-handler surface into
`build/generated/ksp/`, and **nothing generated is committed** — `src/Impl.kt`
implements an interface that does not exist until the build runs, so a
committed copy would be a second source of truth nothing checks.

Rust needs no equivalent: `transition_matrix!` is a `macro_rules!` macro, so
every Rust example exercises the generator by compiling, with no build script
and nothing written to disk.

Swift has no compile-time generator to consume yet — `TabulaMacros` is blocked
on swift-syntax packaging, and `TabulaCodegen` takes a `MachineDesc` value
rather than a file, so there is nothing a build plugin could invoke. When one
lands, the example is a SwiftPM build-tool plugin with generated sources in
`.build/` and nothing committed, matching Kotlin.

It is skipped where Gradle is absent rather than faked. An earlier attempt
stood in for the processor with a hand-written `MachineDesc`, which was
committing by hand precisely what the example exists to generate.

One Maven run settles the rest. The generator itself is split out and tested
without KSP, so what is unverified is the adapter, not the logic.

## Phase 0 — Foundations

**Exit criterion:** `nix develop` works on Linux and macOS; empty test suites
green in CI for all three languages.

- [x] `flake.nix`: nixpkgs pin, `rust-overlay`, JDK 21, Swift (5.10.1 today,
      from the `nixpkgs-swift` input; see ARCHITECTURE 13)
- [x] Per-language dev shells (`.#rust`, `.#kotlin`, `.#swift`) + combined default
- [x] `nix flake check` wired to all three (empty suites for now)
- [x] Repo skeleton per ARCHITECTURE §12
- [x] CI matrix: Linux (all three, through `nix flake check`), macOS (all
      three), and `check-no-nix` on both. Swift-on-Linux is no longer
      `continue-on-error`: it is a normal check since `swiftChecked` became
      `swiftAvailable` (ARCHITECTURE 13)
- [x] `CONTRIBUTING.md`, `.editorconfig` (incl. ktlint alignment
      exemptions for annotated declarations)
- [x] Kotlin group and package `dev.tabularcenter` -> `center.tabula`, the
      namespace the domain `tabula.center` proves (RELEASING.md), before any
      Maven release -- published coordinates never change. As 0023 did for
      `dev.tabula`: source directories moved (`core/center/tabula/`, ...), the
      KSP service file, the processor's group and the three builds'
      substitution, the emitter's imports and the processor's qualified-name
      constants, all rewritten (258 occurrences, PLAN's history untouched).
      One hazard particular to this name: `center` is a common identifier,
      and a qualified `center.tabula.X` resolves its first segment by scope.
      Generated code wrote only `PAYLOADS: center.tabula.Payloads` that way --
      a type position, so values could not shadow it, but it now imports
      `Payloads` like every other library type it uses
- [x] The site is deployed by a workflow again, and `doc/` is no longer
      committed -- reversing the 0009 decision, on purpose. Branch-serving
      needed no setting, but Pages serves only a branch's root or a folder
      named `docs/`, so the site root was the repository's and generated
      output lived in git behind a staleness check. Now
      `.github/workflows/pages.yml` runs `tools/docs`, renders with GitHub's
      Jekyll action and deploys the artifact; the generated `doc/` is the site,
      so `doc/index.md` is `https://tabula.center/` and pages lose the `/doc`
      segment. The original failure -- Pages' Source left on the branch, so the
      workflow was ignored and every page 404'd -- is guarded twice: the
      setting is written down (RELEASING.md, "The site"), and `deploy-pages`
      fails rather than falling back. `tools/verify docs` keeps what still
      matters: every sample resolves, every diagnostic has its anchor
- [x] Maven Central, ready: a root Gradle build in `tabular-center-kotlin/` for
      core, annotations, codegen and testing (each project's directory is its
      source root, so no build files among the sources), `ksp/` applying the
      same `gradle/publication.gradle.kts`, `tools/central-bundle` staging
      both into one bundle, `publish --only kotlin` uploading it to the
      Central Portal API and waiting for validation, and the publish
      workflow's job ungated. Gradle's own plugins only, so the lock stands.
      Before publishing, `codegen`'s package moved from the bare `codegen`
      to `center.tabula.codegen`: a top-level `codegen` on Maven Central
      would claim a name any library might use. Checked on every push by
      `kotlin-publication` -- the real bundle, offline, signed with a
      key made for the run, verified with gpgv (no agent, whose socket path a long
      sandbox directory overflows), every file signed and checksummed, every
      POM complete. `<developers>` is `hadilq`. Signing is by subkey ID
      (`SIGNING_KEY_ID`): the release key is exported subkey-only, its primary
      a stub, and the first CI run failed signing by the first key; the check
      key is shaped the same way, so the check would have caught it.
      That key is generated per run and destroyed after it -- never committed:
      a short GNUPGHOME under /tmp keeps the agent's socket path legal, and
      `gpgconf --kill all` stops gpg-agent and keyboxd. (An earlier version
      committed a throwaway private key to avoid that; it granted nothing,
      but committing private keys is the habit to never teach)
- [x] License files. Every manifest declared `MIT OR Apache-2.0`, but the tree
      had no `LICENSE-MIT` or `LICENSE-APACHE`. This box was ticked with the
      two above; the September 2026 re-audit found nothing behind it. Needs
      the copyright holder's name, which is not something to guess at, and
      must land before any Phase 10 publication.
      *The Swift mirror adds a requirement:* a `git subtree split` of
      `tabular-center-swift/` carries nothing from the root, so the license
      files need copies inside that directory too (and inside the Rust crate,
      whose archive likewise holds only its own directory)

      *Done, October 2026, and decided: **MIT only.*** The dual license was
      dropped rather than completed. `LICENSE` (MIT, naming Hadi Lashkati
      Ghouchani) stays the single license file; every Cargo manifest says
      `license = "MIT"` and the Maven POM lists MIT alone. Copies sit beside
      the crate and in `tabular-center-swift/`, the two directories published
      without the root -- copies, because a symlink to the parent dangles in
      the subtree mirror; `tabular-center-fmt` is `publish = false`. Root
      `licenses` checks the copies are identical to the root's and every
      manifest says MIT; Rust `package` fails unless `LICENSE` is inside the
      `.crate`. (A first version added `LICENSE-APACHE` to complete the
      dual license; reverted on the owner's decision.)

**Risk:** Swift toolchain on Linux via nixpkgs is the known-flaky piece. Do not
let it block Phase 0 — pin it, mark it best-effort, move on.

**Outcome:** done. *(Superseded: Swift jobs were once gated on
`hashFiles('tabular-center-swift/Package.swift')`; that gate made `ci.yml`
invalid and was removed -- see "CI" under the rename. Swift is now an ordinary
check on both platforms.)*

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
specification. It lives at `tabular-center-rust/tabular-center/tests/reference_timer.rs` — a test
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

- [x] Grammar: `machine` / `context` / `state` / `action` / `effects` /
      `initial` / `states` / `actions` / rows
- [x] `prototype` in the grammar: `prototype fn handle;` and
      `prototype async fn handle;`, after `context`. Unticked by the September
      2026 audit, written after it
- [x] Row parsing with positional cells
- [x] Static cell kinds: `IGNORE`, `GO!`, `EMIT`
- [x] `HANDLE` → trait method emission with **narrowed argument types**
- [x] `UNREACHABLE` → trap, counted by `Table::coverage` (stable
      `macro_rules!` cannot write to build output)
- [x] Dispatcher emission with **no wildcard arm** (so `rustc` catches missing rows)
- [x] Row-arity validation with a readable error
- [x] `TABLE` const emission
- [x] `TABLE` as a `const` `[[Cell; M]; N]` -- for every machine, not only
      payload-free ones
- [x] Index dispatch for payload-free machines -- **decided against**, on the
      Phase 10 benchmark's numbers. All three versions it timed dispatch
      through one `match`, and the 2x gap between the library and a plain
      `match` is in the return value (`Step`'s outcome and inline effects
      array), not in dispatch. Index dispatch would speed up the part that is
      already equal. The cost worth attacking is `Step`'s size: see Phase 10
- [x] Color, as Rust allows it: `async` only, through `AsyncHandle` /
      `AsyncPerform` and `.await` at the HANDLE call and in `perform`. Not
      `unsafe` / `const` / `extern` splatting: the cell surface is a library
      trait, and of those only `async` can be carried by a trait method on
      stable. See the audit's Rust-colors item
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
- [x] Fixture designed, and the blocker below turned out to be already solved.
      `spec/diagnostics.md`'s canonical vocabulary lands `attempt: Long`,
      `attempt: u32` and `attempt: Int` all on `attempt: int`, so a shared
      byte-for-byte `.lint` golden IS possible — that is what canonicalising
      *before the comparison* bought, and the note below predates it.

      The second thing worth recording: **`.tbl` needs no new field.**
      `conformance/Main.kt` builds the `.lint` golden from
      `report(adapter.table, adapter.payloads)`, so payloads come from each
      language's adapter, not from the fixture. The matrix file stays the
      matrix, which is the same separation `PAYLOADS`-beside-`TABLE` already
      makes in generated code.

      The machine, `Conn`, chosen so the ONLY finding is the one under test —
      no dead row or column, 4 of 12 cells `IGNORE` (33%, well under
      `IGNORE_HEAVY_PERCENT`), fully static with every non-initial state
      statically reached, so `lint()` is silent and `payloadHoist` is not:

      ```
      machine Conn
      initial Connecting
      states  Connecting Backoff Reconnecting Live
      actions Open Fail Timeout

      Connecting   | GO(Live) | GO(Backoff)      | GO(Backoff)
      Backoff      | IGNORE   | IGNORE           | GO(Reconnecting)
      Reconnecting | GO(Live) | GO(Backoff)      | GO(Backoff)
      Live         | IGNORE   | GO(Reconnecting) | IGNORE
      ```

      `Connecting`, `Backoff` and `Reconnecting` each carry `attempt`; `Live`
      carries nothing. Three states, which is `PAYLOAD_HOIST_STATES` exactly —
      the fixture sits on the boundary on purpose, so an implementation that
      used `>` instead of `>=` fails it.

      Expected `payload-hoist.lint`, one line:

      ```
      warning[tabula::payload-hoist]: Conn: `attempt: int` appears in the payloads of Connecting, Backoff, Reconnecting; consider hoisting it to Context
      ```

- [x] The fixture data: `payload-hoist.tbl`, `.grid`, `.cov`, `.lint` and
      `traces/payload-hoist.trace`. `.puml` is not among them because the
      format is gone. `.grid` and `.cov` were generated by mirroring
      `Export.toGrid` and `toCoverageReport` rather than typed by hand, after
      two rounds of hand-written literals being wrong about what the code
      does.
- [x] Kotlin adapter. `payloads` is spelled `Long`, not `int` -- the adapter
      reports its own language's type and `canonicalType` maps it before the
      comparison. Writing `int` there would pass today and hide the mapping
      that makes one shared `.lint` golden possible at all.
- [x] Rust adapter. `PAYLOADS` is emitted by `transition_matrix!` from the
      `states` block, so the field list is never spelled twice, and the type it
      records is `u32` against Kotlin's `Long` -- both canonicalise to `int`.
- [x] Swift adapter. `payload-hoist` now runs in all three, and the fixture
      that could not exist -- one `.lint` golden across three languages that
      each spell the field's type differently -- exists. `u32`, `Long` and
      `Int` all reach `attempt: int` through `canonicalType`, which is the
      decision in section 1 above finally exercised rather than asserted.
- [x] `ConnF` is the second uninhabited effect type, after `GateF`. This one
      reaches it with payload-carrying states, which `effects-never` does not. Kotlin first; Rust and Swift report the fixture as **skipped**
      until theirs land, which is the designed behaviour for a fixture without
      an adapter and is now visible in `tools/verify`'s skip ledger rather
      than silent.
- *Superseded, kept for the record (not a task):* the reason recorded here was **not** the
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
      stdlib, and the `kotlin` step compiles `tabula-core` against an empty
      one. A Gradle dependency-report check once sat in `nix/checks.nix`,
      gated on a `tabular-center-kotlin/settings.gradle.kts` the library will never have;
      removed by the September 2026 audit.
- [x] `SuspendDriver` exercised. It was not, until after Swift's `AsyncDriver`
      turned out to have the same gap — the blocking driver had checks from the
      day it was written and its twin had none. Both sides now assert the two
      colors report identical `Progress` for identical input, which is the
      property the duplication actually threatens.

**4b. Annotations**
- [x] `@Machine`, `@Row`, cell markers (`HANDLE`, `IGNORE`, `GO`, `EMIT`,
      `DELEGATE`, `UNREACHABLE`). **Not `EXPAND`**, which this box used to
      list: `spec/cells.md` section 3 makes it a *row* directive, so it has no
      place in `Kind`, and it is implemented in no language yet. See the
      `EXPAND` entry under 0f.
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
- [x] One run against Maven to confirm or correct it. It ran: `nix flake check`
      builds `examples/kotlin/06-generated` against the locked artifact set
      (see 0d), and the processor is exercised on every check rather than on a
      machine that happens to have Maven.
- [x] The output held to a golden, `tabular-center-kotlin/ksp/golden/TurnstileGenerated.kt`.
      The example compiling was the weaker claim: it proves `Cells` has a
      member `Impl.kt` can override and that `step` type-checks, and nothing
      about the table. Rows read out of order, an effect dropped from a `GO`
      cell, `initial` resolved to the wrong state -- all compile, and `TABLE`
      and `PAYLOADS` are read by nothing in the example. Since every decision
      lives in `codegen/`, extraction is the processor's entire untested
      surface, and extraction bugs are exactly the kind that yield a
      well-formed machine saying the wrong thing.

The split is worth keeping after KSP lands. A generator whose logic can only be
exercised through a compiler plugin is a generator nobody refactors.

**4c-old. KSP processor** *(the shape it must emit is fixed by
`tabular-center-kotlin/test/ReferenceTimer.kt` and `codegen/golden/`)*
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
Re-read against `tabular-center-kotlin/ksp/src/main/kotlin/dev/tabula/ksp/TabulaProcessor.kt`
and `tabular-center-kotlin/ksp/golden/`, not guessed (0f asked for exactly this pass):

- [x] ~~Resolve sealed hierarchies to ordered variant lists~~ — **superseded.**
      Order is declared, not discovered: `@Machine(states = [...], actions =
      [...], effects = [...])` and the processor reads those lists. Row
      identity is position, so an order a refactor of the sealed hierarchy
      could silently change is the wrong source for it.
- [x] Read the `handle` prototype: `suspend` and annotations, copied verbatim
      (`prototypeModifiers`).
- [x] Extension receiver: `fun Clock.handle` makes every cell, handler,
      `step` and `perform` an extension on `Clock` (qualified in the output).
      `Stopwatch` in `06-generated`, with a KSP golden byte-identical to its
      `codegen/golden/` twin. A receiver on a machine with `DELEGATE` cells is
      refused in `MachineDesc` rather than emitted half-right.
- [x] Visibility — read from the **annotated declaration**, not the prototype:
      the generated surface names the machine's types, so it can be no more
      visible than they are. `internal` is carried to `Cells`, `step`,
      `perform`, `TABLE` and `PAYLOADS`; `private`/`protected` are refused,
      since the generated file is another file. Found on the way: before this,
      an `internal` machine could not compile at all (a public `Cells` over
      internal types).
- [ ] Context parameters. **Blocked on the compiler, not on work**: they
      arrived in Kotlin 2.2.0 as a preview behind `-Xcontext-parameters` and
      are stable only from 2.4, and the flake pins kotlinc 2.1.20, where the
      syntax does not parse. Bumping it moves the message text the
      `tabular-center-kotlin/compile_fail/` fixtures match (0f), and KSP with it — a decision
      of its own. Once made, this is one more branch in `prototypeModifiers`
      and a `-Xcontext-parameters` in the example build.
- [x] ~~Emit abstract class~~ — **superseded** by `codegen/Emit.kt`: the
      surface is `interface Cells` (Phase 6's Kotlin finding: a class extends
      one parent, so abstract members would cap composition at one child),
      with copied modifiers and narrowed types. Pinned by `ksp/golden/`.
- [x] Nested `when` dispatcher, **no `else`** — `codegen/Emit.kt`, golden-diffed
      and compiled.
- [x] `TABLE` — a top-level `val` beside `step` rather than a companion, for
      the same reason as the interface.
- [x] Diagnostics per `spec/diagnostics.md`, via `KSPLogger.error`, authored in
      `codegen/Raw.kt` and exercised by the 11 `kotlin-ksp-compile-fail`
      fixtures.
- [x] Diagnostic *positions*, to the row. `TabulaError` carries the state
      whose row was being validated -- attached in `buildDesc`'s loop, not at
      each of the eighteen `fail` sites, since the row is known in exactly one
      place -- and the processor maps it to that `@Row` annotation, which KSP
      accepts as a position. Row-level, the same as Phase 5 accepts for Swift;
      a `CellSpec` inside an annotation argument is not separately addressable
      here. Declaration-level diagnostics (a bad `initial`, a broken path, a
      missing row) still point at the interface, which is where they belong.
      Checked, not assumed: `//~ AT: <text>` in a KSP fixture asserts the line
      the compiler underlined contains that text, and two fixtures say so.
- [x] Incremental-processing correctness: `kotlin-ksp-incremental` edits
      `Types.kt` (not the annotated file) and requires the regenerated output
      to change. The processor declares only the annotated file as a
      dependency, so this rests on KSP's own reference tracking — which is
      why the check exists rather than the argument.

**4d. Conformance**
- [x] Kotlin harness green on all five fixtures. It started green on `timer`
      and `toggle` with `retry` and `nested-delegate` reporting as **skipped**;
      Phase 6 landed `RetryAdapter` and `JobAdapter` in `conformance/Compose.kt`
      and Phase 7 landed `EffectsNeverAdapter`, so `conformance/Machines.kt`
      now registers all five. Verified to catch both table drift and
      behavioural drift. The skip path is still live and still matters — it is
      what a sixth fixture would hit before it has an adapter.
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
four fixtures passed then, with the same golden `.grid` and `.lint` files; all
eleven pass now, and the goldens have been replaced by `renderings-agree`.

- [x] `Step`, `Cell`, `Table`, `Export`, `Lint`, `Driver`, testing harness
- [x] Reference machine and compile-fail suite, the counterparts of
      `reference_timer.rs` and `tabular-center-kotlin/compile_fail/`
- [x] `Sources/TabulaCodegen`: the same `MachineDesc -> String` split Kotlin
      took, with 13 declaration diagnostics. *Its golden diff was later
      removed with every other emitted-source golden: `swift-codegen`
      compiles the output instead. See the audit, and "Generated code is not
      committed" below.* Split for the
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
      duplicated loop, documented in `tabular-center-swift/README.md`, run by nothing. The
      check asserts the two colors report identical `Progress` for identical
      input, since that is the property duplication threatens
- [ ] `@Machine` attached macro (SwiftSyntax, **build-time only** — assert with
      a linked-binary check in CI). Blocked on the swift-syntax packaging
      decision; see the backlog entry below.
- [ ] Synthesize payload-free `Tag` enums for table indexing
- [ ] Validate `matrix` literal shape at expansion; row-arity diagnostics at
      correct source positions
- [ ] Prototype capture: `async`, `throws`, `@MainActor`, `@Sendable`, isolation.
      Captured by `MachineSyntax`, and now *placed* correctly by the emitter
      (attributes before `func`, specifiers after the parameters), with
      `async throws` compiled end to end. `@MainActor` and isolation are
      emitted but not yet compiled by any check
- [x] Emit protocol requirements with narrowed types -- `TabulaCodegen`'s
      job, not the macro's. Compiled by `swift-codegen` against
      `codegen-support/`
- [x] Emit exhaustive `switch (state, action)` with payload binding, **no
      `default:`** -- same. Delegation is the remaining gap; see the audit
- [x] Conformance harness green -- `TabularCenterConformance` registers an
      adapter for all eleven fixtures (October 2026 audit: the box had been
      left open after the work landed)

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
- [x] One-way color flow. Ticked until the September 2026 audit as
      "enforced by construction in Rust"; it held only vacuously, because
      Rust had no colors to mismatch. Rust has `async` now: a plain parent
      over an async child is refused by rustc, and an async parent over
      either child compiles (`compile_fail/async_child_in_plain_parent.rs`,
      `tests/async_composition.rs`). In Kotlin it is by construction: the
      generated `delegateTo<Child>` carries the *parent's* modifiers and calls
      the child's `step`, so a suspending child under a plain parent is a
      kotlinc error. Swift's generator does the same since the audit, and
      `codegen-support/compile_fail/job-mixed_*.swift` proves it: an uncolored
      parent over an `async throws` child is refused by swiftc, and
      `complete/job-async.swift` shows the reverse compiles. Kotlin now has
      the same pair: `codegen/compile_fail/jobmixed_*.kt` and
      `support/CompleteJobSuspend.kt`. Rust has no colors
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

### Findings from Phase 8's PlantUML patch (format since removed)

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

"Gated" is per machine: nothing is generated unless a machine declares a
rendering prototype, and a machine that does not emits exactly what it did
before. Order of work: the Kotlin emitter (proven with plain `kotlinc`, no
KSP), then the processor and the Compose example, then Swift's emitter, then
the transition-prototype warning -- which needs harness work of its own, since
a warning refuses nothing and every other fixture here proves a refusal.

- [x] Kotlin emitter: `RenderDesc` (modifiers, return type) on `MachineDesc`
      and `RawMachine`, defaulted to null so every existing caller compiles
      untouched. With one, `emit` adds a `Renders` interface -- one member per
      state, `render<State>(state: S.<State>)`, narrowed -- and a `render`
      dispatcher that is an exhaustive `when` with no `else`, both carrying the
      render prototype's modifiers and neither the transition prototype's.
      Proven by `kotlin-codegen`: a `timerrender` twin (the Timer's `suspend`
      transitions, plain renderers) emits and compiles, `CompleteRender`
      compiles against it, and `timerrender_missing_renderer.kt` must be
      refused. `Tests.kt` checks the surface is additive -- cut the render
      block from a rendered machine and the rest is byte-identical to the
      plain one -- and exhaustive. No extension receiver on the render
      prototype yet: refused at extraction, not generated wrong
- [x] KSP: `renderOf` reads a second function, `render`, from the annotated
      interface -- `suspend` and annotations as its color, its return type
      fully qualified -- and refuses an extension receiver or any shape but
      one parameter, as a `tabular-center:` error at the declaration.
      Annotations are copied by QUALIFIED name: the generated file imports
      only `dev.tabularcenter`, so a short `@Composable` would not resolve
      there. The Compose example's connection screen renders through it:
      `Machine.tb.kt` declares `fun render(state: S): Pair<String, String>`,
      and `ConnectionDescriptions` replaces a hand-written `when` over `S` --
      exhaustive before too, but by convention; now by a surface the
      generator owns. Built by `kotlin-compose` through KSP. The renderer
      is plain on purpose: `connectionModel` is a pure function both screens
      share, and making it composable to exercise the annotation path would
      change the design for a test. So `@Composable` on a renderer is proven
      at string level (`Tests.kt`), not yet compiled by an example
- [x] The transition prototype copied its annotations by SHORT name, which
      cannot resolve in the generated file; no machine had put one on
      `handle`, so it had never run. Qualified now, as `renderOf` copies --
      and proven by the warning fixture below, whose generated cells carry
      `@androidx.compose.runtime.Composable` and must compile
- [x] Swift emitter: `RenderDesc` (modifiers, a concrete return type) on
      `MachineDesc` and `RawMachine`, nil by default. With one, `emit` adds a
      file-scope `<Machine>Renders` protocol -- `renderIdle()`,
      `renderRunning(_ state: Timer.Running)`, narrowed as cells are -- and
      `static func render` in the machine's extension: a `switch` with no
      `default:`, binding payload fields and building the narrowed struct as
      `step` does. The render prototype's color goes through `Color`, like
      the cells': attributes before `func`, `async`/`throws` after, `try await`
      at the call. Proven by `swift-codegen`: a `TimerRender` twin
      (`async throws` cells, plain renderers) compiles with
      `CompleteTimerRender`, and `timer-render_missing_renderer.swift` must be
      refused naming `TimerRenderRenders` -- a hole in the cells would name
      `TimerRenderCells` and not match. `TabularCenterCodegenCheck` checks it
      is additive (both render blocks cut, the rest byte-identical) and
      exhaustive, line by line, since `String.contains(String)` is macOS 13+
- [x] Swift `@ViewBuilder` renderers: a builder mode on `RenderDesc`
      (`builder`, `conformance`) taking SwiftUI's own shape -- `View` has
      `associatedtype Body` under `@ViewBuilder var body`. One associated
      type per state (`IdleBody: View`, so each state may return a different
      view) with the builder on the requirement; `render` generic over the
      conformer, `@ViewBuilder`, returning `some View`, arms bare because a
      `return` in a builder body switches the builder off; `@available`
      macOS 10.15 / iOS 13, where opaque result types begin. Refused by name:
      no conformance, or an `async`/`throws` builder renderer. Proven on Linux
      as well as Darwin with a stand-in builder (`ViewishBuilder`, `buildBlock`
      and `buildEither`, as `ViewBuilder` has) since SwiftUI is absent there:
      a `TimerView` twin compiles with `CompleteTimerView`, whose renderers
      return concrete views and infer the associated types, and
      `timer-view_missing_renderer.swift` must be refused
- [x] Second prototype for view derivation (`S -> UI`) -- the emitters and
      KSP above
- [x] One required member per state, narrowed payloads -- in both emitters,
      each with a fixture refusing a missing renderer
- [x] Kotlin: `@Composable` rendering cells -- copied qualified by `renderOf`,
      checked at string level; the qualified-copy mechanism itself is compiled
      by the warning fixture below. No example renders composably yet (the
      Compose example's renderer is plain, for the reason given above)
- [x] Swift: SwiftUI `@ViewBuilder` cells -- the builder mode above. Proven
      with a stand-in builder, not SwiftUI itself: no example is a SwiftUI app
      rendering through it yet
- [x] Warning when `@Composable` appears on a *transition* prototype (Compose
      runtime may skip / restart / discard — a real correctness hazard, not
      style): `tabular-center::composable-transition`, Kotlin only, positioned
      at `handle`. The first diagnostic that warns instead of refusing, so the
      KSP harness gained a mode for it: a fixture marked `//~ BUILDS` must
      build, print the diagnostic, and position it. Its fixture stubs
      `androidx.compose.runtime.Composable` -- the processor matches by
      qualified name, and without Compose's compiler plugin it is only an
      annotation -- so it needs nothing new in the Gradle lock

---

## Phase 10 — Release

- [x] README leading with the composition property and the one guarantee.
      It led with both already; the composition property was a claim with no
      demonstration, and now shows a DELEGATE row and what the compiler does
      with a hole in the child
- [x] Migration guide: from Tinder StateMachine, KStateMachine, Spring
      Statemachine, TCA -- `doc/migrating.md`, generated like every page. A
      concept map (states -> rows, guarded transitions -> `HANDLE`, unlisted
      pairs -> explicit `IGNORE`, listeners -> effects, nesting ->
      `DELEGATE`), an honest list of what has no equivalent (hierarchy,
      parallel regions, history, entry/exit, runtime-built machines, undo),
      and one machine before and after per library: the Kotlin three against
      the KSP Stopwatch, TCA against the Swift Timer. The "after" code is
      included from the examples; the "before" code is other libraries', not
      compiled here, and the page says so where it shows it
- [ ] Publish: crates.io, Maven Central, Swift Package Index
      - [x] **Maven Central: published** (October 2026), from
            `publish.yml`'s `maven-central` job, after two fixes the first
            real run found: `SIGNING_KEY_ID` in gpg's long form, and the
            registry switch set as an environment variable (both under
            "Audit, October 2026")
      - [x] **crates.io: published** (crates.io/crates/tabular-center).
            Releases are tagged `v0.1.1` through `v0.2.0` in this repository
      - [x] **Swift: published through the mirror.** Checked against the
            mirror itself (October 2026): `tabula-center/tabular-center-swift`
            holds tags `0.1.2` through `0.1.6` and `0.2.0`, so SwiftPM users can
            already depend on it. There is no Swift registry to upload to;
            the mirror *is* the publication
      - [ ] **Swift Package Index: not listed.** Its public package list
            (12,213 entries) has no `tabula-center` repository. The index is
            discovery, not distribution: a repository URL is submitted once,
            through swiftpackageindex.com's "Add a Package", which adds it to
            `SwiftPackageIndex/PackageList`'s `packages.json` (entries are
            written `https://github.com/<owner>/<repo>.git`). Submit the
            mirror, `https://github.com/tabula-center/tabular-center-swift.git`
            -- never this repository, whose `Package.swift` is not at the
            root. A person's step: it is a pull request from a GitHub account
      - [ ] Then `tools/compat backfill` once, now that the tags are known to
            exist (`v0.1.1`..`v0.2.0`), and commit `compatibility.toml`
      *Distribution decided, and made checkable before any credential
      exists.* Rust: crates.io receives an archive of the crate directory
      alone, so `rust-package` runs `cargo package` -- which builds the crate
      from exactly that archive -- on every push; the crate gained its own
      README and crates.io metadata. Kotlin: Maven Central gets compiled jars,
      nothing to check. Swift: SwiftPM and the Package Index need
      `Package.swift` at a repository's root, so Swift ships through a mirror,
      `tabula-center/tabular-center-swift`, made on each `v*` tag by
      `.github/workflows/swift-mirror.yml` (`git subtree split`, tagged with
      the bare version); `swift-standalone` builds `tabular-center-swift/` with
      nothing beside it, which is what the mirror holds. Still needed once,
      by hand: the mirror repository, its `SWIFT_MIRROR_TOKEN` secret, and its
      Package Index registration (RELEASING.md). *Pipeline:* `.github/workflows/publish.yml` on
      the release tag -- `verify` reruns the checks on the tagged commit;
      `crates-io` publishes by trusted publishing (OIDC, no stored secret);
      `maven-central` holds the only long-lived secrets (user token, signing
      subkey) in its own environment, and stays off until the Kotlin Gradle
      publication exists. `publish` gained `--only rust|kotlin|swift` so each
      job carries one registry's credentials. Actions pinned to commits.
      The domain is `tabula.center`, so Maven's namespace is `center.tabula`
      (a DNS TXT record proves it)
- [x] Semantic-versioning policy — specifically, what counts as a breaking
      change to *generated* code. `RELEASING.md`: generated code is API, one
      `VERSION` for all three, and one test -- does an unchanged declaration
      with an unchanged implementation still compile and behave the same.
      A table of cases follows from it, including the two that surprise: a
      new required member is major *because the guarantee works*, and a bug
      fix that removes a wrongly required member is still a signature change
- [x] Benchmarks vs. hand-written dispatch (the honest claim is "identical after
      monomorphization"). Written: `tabular-center/benches/dispatch.rs`, run by
      `nix run .#bench`. Three versions of the Timer -- the matrix
      (`tests/timer_matrix.rs`), its hand-written expansion
      (`tests/reference_timer.rs`), and a plain `match` with no library --
      the first two included from the test files, so the machines timed are
      the ones the suite checks. It asserts all three visit the same states
      and emit the same effects before timing anything. No dependencies
      (std's `Instant` and `black_box`), no harness, `test = false`: timing is
      not a check, but `clippy --all-targets` keeps it compiling
- [x] Run it on real hardware and record the numbers here. One run, on a
      working machine with a dirty tree, ns per step, 21 rounds of 200 000
      cycles:

      | | min | median |
      |---|---|---|
      | `matrix` | 2.13 | 2.70 |
      | `reference` | 1.88 | 2.55 |
      | `plain` | 0.94 | 1.19 |

      Two readings. `matrix` against `reference` is 13% slower at the minimum
      and 6% at the median, but each version's own min-to-median spread is
      about 25% -- wider than the gap -- so this run neither confirms nor
      refutes "identical after monomorphization"; timing is the wrong
      instrument for "identical". And `plain` is 2x faster than both, which
      is the real result: the three dispatch alike, so the difference is the
      value returned -- `Step<S, F, K>` carries an `Outcome` and a fixed-
      capacity inline `Effects` array where `plain` returns
      `(State, Option<Effect>)`. About a nanosecond per step, paid by the
      macro and the hand-written reference alike: "zero-cost" holds against
      hand-written code of the same shape, not against the smallest `match`
- [x] "Identical after monomorphization", settled properly: compare the
      optimised assembly of `matrix` and `reference` (`cargo asm`, or
      `--emit asm` on the bench), not their timings. If they differ, the
      difference is a bug in the macro
      - [x] The instrument: `nix run .#bench-asm` (`tabular-center-rust/tools/asm-diff`).
            The bench exports both dispatchers as `#[no_mangle]
            #[inline(never)]` wrappers; the tool compiles it with
            `--emit=asm,link` and one codegen unit, resolves each side to its
            full dispatch body (the wrapper if `step` was inlined into it,
            else the monomorphized `step` it calls, and says which), and
            diffs them after normalising only what differs by construction:
            directives, comments, label numbers, mangling hashes, and the
            `matrix`/`reference` module names. Exits 0 identical, 1
            different, 2 undecided. No `cargo asm`: a dependency for one
            `--emit` flag
      - [x] The machines made comparable first. `reference_timer.rs` emitted
            `StopClock { reason: 1 }` on Cancel and `reason: 2` on timeout,
            where the matrix and `plain` emit 0 and 1 -- invisible to timing,
            and an immediate-value difference to any assembly diff. Aligned
            on the matrix's values, with the one test that asserted them.
            The two `Ctx` types still differ (the reference's carries
            `last_stop_reason` for its perform test); if that moves a field
            offset, the diff shows offsets alone and the tool says so
      - [x] Run it, record the answer here, and if it is IDENTICAL make it a
            check. **First run (x86-64): identical but for two field
            offsets.** Both sides kept `step` as a separate function, 48
            normalised lines each, every instruction, register and immediate
            the same; the only lines that differed were `incl 4(%rsi)` /
            `incl 12(%rsi)` and `cmpl (%rsi)` / `cmpl 8(%rsi)` -- `ticks_seen`
            and `limit`. rustc had laid the reference's `Ctx` out with its
            extra `Option<u32>` first, moving the two shared fields from 0/4 to
            8/12. The test's struct, not the macro's code. So the two `Ctx`
            types are now the same struct, field for field (the matrix's gains
            `last_stop_reason`), which makes the claim exact rather than
            "identical modulo layout"
      - [x] `asm-identical`, a Rust step and the check `rust-asm-identical`:
            `tools/asm-diff` must say IDENTICAL. Deterministic under the pinned
            toolchain, so a change to the macro's expansion that alters the
            generated code now fails CI instead of waiting for someone to run
            the app. `nix run .#bench-asm` stays for reading the diff.
            *Expected green, not yet observed under `nix flake check`.*
            Normalised before the diff, and only these, since each differs by
            construction: directives with no code in them and comments; local
            label numbers, which count functions in emission order; mangling
            hashes; and the module segment (`matrix` / `reference`) that
            differs by design. A body the tool cannot find, or an empty one,
            is exit 2 -- never "identical"
      - [x] **Its first `nix flake check` failed, and the failure was the
            proof.** With the two `Ctx` types identical, the two dispatchers
            compiled to one function, and LLVM's function merging (rustc's
            default, `MergeFunctions::Aliases`) kept one body and emitted the
            other wrapper as `.set tabular_center_asm_reference,
            tabular_center_asm_matrix` -- no label, so `asm-diff` reported "no
            function". It now follows aliases (`.set a, b` and `a = b`), a
            wrapper that only jumps to the other, and a `step` merged into its
            twin; two sides that resolve to one symbol are IDENTICAL by the
            compiler's own comparison, and only two surviving bodies are
            diffed
- [ ] `Step`'s cost. A nanosecond a step over a plain `match`, from the
      outcome-plus-effects-array return value. Worth measuring what the
      default effect capacity `K` contributes before changing anything --
      the array is what makes `Step` allocation-free, which is not to be
      traded casually
      - [x] The instrument: `nix run .#bench` now also times `step k=K`,
            `plain`'s machine returning `Step<State, Effect, K>` for K = 1, 2,
            4 and 8, and prints every version's return size in bytes. The
            macro does not expose `K`, so this is the way to vary it alone:
            `plain` against `step k=1` is what `Step` itself costs (the
            outcome enum, `emit`'s checks) with the smallest array that holds
            this machine's one effect; `k=1` to `k=8` is what the array's size
            adds. The same parity check runs first: every version must visit
            the same states and emit the same four effects
      - [ ] Run it, record the numbers here, and decide: if the cost tracks
            the bytes, a smaller default `K` (or one chosen per machine) is
            worth a design; if `step k=1` is already most of the gap, the
            array is not the cost and stays as it is
- [x] **One definition of green.** `tools/verify` is it; `nix flake check` runs
      its steps in a sandbox and CI runs the flake. Any new check goes in
      `tools/verify`, never directly in the workflow.

      This was learned the hard way. Three lints reached CI because the
      workflow, the flake, and the local loop each checked slightly different
      things — most recently an unused import in a *test* file, which
      `cargo build` never compiles, so it passed locally and failed clippy in
      CI. `--all-targets` is load-bearing.
- [x] Every diagnostic gets a UI test (`trybuild` / KSP compile-testing /
      swift-macro-testing) -- and `diagnostics-tested` now enforces it rather
      than trusting the habit. From `spec/diagnostics-coverage.md`: a runtime
      lint must name conformance fixtures that exist, every other emitted code
      must have a compile-fail fixture whose `//~ EXPECT:` names it, and a
      code emitted by nobody must have no fixture expecting it -- so the `-`
      beside `color-mismatch` cannot quietly become false either

**Standing rules**, not tasks -- they were written as boxes and so could never
be closed (moved out of the list by the October 2026 audit):

- Any behavioural change lands in `spec/conformance` before any implementation.
- Docs are updated in the same PR.
- All three implementations are green before merge to `main`.

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
| ~~N×M cell count makes real machines unpleasant~~ | any | **Measured** on a genuine 8×12 order machine: 96 cells, 78% `IGNORE`, **9 members to write**. Two costs found and recorded — a raised `recursion_limit` past ~7×10, and `ignore-heavy` firing on a machine that arguably is two machines. See `tabular-center-rust/tabular-center/tests/scale.rs`. |

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

## `TabulaMacros` — decided: a separate package

The Swift generator's logic is done and testable (`Sources/TabulaCodegen`, 13
diagnostics plus a golden diff). What was left was the macro that parses syntax
into a `RawMachine`, and one packaging decision that had to come first.

**Chosen: option 2.** `tabular-center-swift/macros/` is its own SwiftPM package, built in the
dev shell and reported as `skip` by `nix flake check` rather than passing
silently.

The argument that settles it is sharper than "swift-syntax is remote". A
macro's *declaration* must live wherever users import it from, and
`#externalMacro` names the implementation module — so declaring `@Machine` in
`Tabula` makes `Tabula` depend on the macro target and therefore on
swift-syntax. **There is no arrangement where the macro lives in the main
package and the main package stays offline-buildable.** The declaration
therefore lives in `tabular-center-swift/macros` too, and a user who wants the macro takes a
second dependency while a user who does not pays nothing.

Option 1 — vendoring swift-syntax with `swiftpm2nix` or a fixed-output
derivation — remains the correct end state and is strictly more work. It can be
adopted later without moving any code: only `nix/` changes.

- [x] The packaging decision, and the package that embodies it
- [x] `TabulaMacroDecl`, the declaration users import
- [ ] **Blocked earlier than expected.** The pinned toolchain's SwiftPM does
      not ship `CompilerPluginSupport`, so `Package.swift` fails to *compile* —
      `no such module 'CompilerPluginSupport'` — before any dependency
      resolution. No macro package can be declared with it. Vendoring
      swift-syntax would not help; this needs a SwiftPM that ships the module,
      which in practice means Darwin or a non-nix toolchain.
- [x] `tabular-center-swift/macros/SURFACE.md`: the declaration surface and its field-by-field
      mapping to `RawMachine`. The reviewable half, settled first because the
      traversal's shape follows from it and nothing here can compile a
      traversal. Rows are **aligned array literals**, matching Rust and Kotlin:
      a labelled-tuple draft was rejected because labels make every row a
      different width, and a matrix whose rows do not line up is just a list of
      transitions.
- [x] `MachineMacro` itself: **SwiftSyntax nodes to a `RawMachine`**, and
      nothing else. Landed as `TabulaMacroSyntax.MachineSyntax`, a library
      rather than a `.macro` target, for the reason in 0e; the expansion glue
      waits in `pending/TabulaMacros/MachineMacro.swift`. Everything downstream exists — `TabulaCodegen` validates a
      `RawMachine` into a `MachineDesc` with every diagnostic and emits the
      source. That split is why this package is small, and why the Kotlin side
      survived KSP being unrunnable.
- [x] A `swift-macros` step in `tools/verify`, skipping without network. It
      matches the error text SwiftPM prints for an unreachable host, so an
      absent network is a skip and a real build failure is still a failure.
- [ ] The Swift `06-generated` equivalent, which is what this unblocks: a
      SwiftPM build with the macro applied, generated code not committed

## Backlog — `tabula-fmt`, a formatter for matrix files

`spec/matrix-files.md` lands the half of this that does not need the tool: a
`*.tb.rs` / `*.tb.kt` / `*.tb.swift` convention, with `rustfmt.toml` and
`.editorconfig` configured to leave those files alone. Worth having before the
formatter exists — the `.editorconfig` exemption currently disables alignment
rules for *every* Kotlin file to protect the few holding matrices, and an
extension narrows that to exactly the files that need it.

- [x] The convention, and the formatter exemptions for it
- [x] Narrowed the `[*.kt]` exemption to `[*.tb.kt]`, so ktlint formats
      ordinary Kotlin again. Rust gets no `rustfmt.toml` entry at all: `ignore`
      is nightly-only and on stable prints a warning per file while formatting
      everything regardless. `#[rustfmt::skip]` is the stable, silent, per-item
      equivalent.
- [x] First consumer: `examples/kotlin/06-generated/src/Machine.tb.kt`. An
      example rather than library code on purpose — examples are read as
      templates, and a convention that appears in none of them is one nobody
      adopts.
- [x] Swift consumer: `SpecCheck/Turnstile.tb.swift`. **Not a rename** — only
      the `Table` literal moves, into an extension. Renaming the whole file
      would have exempted the handler bodies too, which is the over-broad
      exemption the `[*.kt]` block had before it was narrowed.
- [x] Rust consumer: `01-traffic-light/src/machine.tb.rs`, reached with
      `#[path]` and re-exported with `pub use machine::*;` — because
      `transition_matrix!` generates the state and action types, so the split
      moves the crate's namespace rather than just text. `#[rustfmt::skip]` on
      the invocation is the stable exemption.
- [x] The hand-written examples in all three languages kept their matrix and
      their handlers in one file. All three done. **Rust**: every example's
      matrix is in a `.tb.rs` (`04-login` has two). **Kotlin**: `01`-`05`
      each hold their `Table` literal in a `.tb.kt`, and
      `kotlin-matrix-stable` now checks every `.tb.kt` -- it used to check
      only annotated files, while `matrix-covered` counted every `.tb.kt` as
      covered by it. **Swift**: `TrafficLight`, `Retry`, `ObservableCounter`
      and `Timer` hold their `Table` in an extension in a `.tb.swift`, as
      `SpecCheck` did; `Login`'s top-level `SESSION_TABLE` moved as it was.
      Six `.tb.swift` files, covered by `swift-format-config` reading their
      `// swift-format-ignore-file` -- cover by directive until
      `swift-matrix-stable` runs a formatter over them
- [x] `spec/tabula-fmt.md`: the contract. Written first for the reason
      `SURFACE.md` was — a formatter's contract is almost all of its risk, and
      it is the part reviewable by reading.
- [x] `tabular-center-fmt` itself, at the repository root in
      `tabular-center-fmt/` (named `tabula-fmt` when this was written): Rust,
      no dependencies, its own workspace and its own flake -- the fourth,
      composed by the root like the languages, with `tb-fmt-test`,
      `tb-fmt-clippy` and `tb-fmt-rustfmt` handed over by name.
      `nix run .#tb-fmt [-- --check]`. Prototyped first, in Python, over all
      52 `.tb.` files: that settled what the contract left open (which
      bracket is the row, columns never shrink, closers stay the author's,
      header keys and `@Path` never form runs) and the contract now says so.
      The Rust tests are that prototype's outputs, so they also say the two
      implementations agree. Idempotence asserted on every case
- [x] Wire `--check` over the repository's matrices into `tools/verify`:
      `tb-aligned`, a root step and check (it reads every language's
      matrices, as `renderings-agree` does), building the formatter with the
      toolchain its flake exports and running `--check .`. The 9 predicted
      files are aligned -- 18 lines, whitespace only (`git diff -w` empty) --
      and the three column-header comments the widened columns left behind
      (`session.tb.rs`, `Job.tb.kt`, `TimerSpec.tb.kt`) were realigned once by
      hand, each keeping its own file's label offset; the formatter never
      touches comments, by contract. Those edits came from the prototype, not
      the Rust tool, whose `--check` output was not available; `tb-aligned`
      runs the Rust tool, so if the two disagree on any line it fails naming
      it, and `nix run .#tb-fmt` writes the tool's version. No compile-fail
      fixture changed. Confirmed afterwards: `nix run .#tb-fmt` found
      nothing to change and `tb-aligned` passed, so the Rust tool and the
      prototype agree on every real matrix in the repository, not only on
      the test cases

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

**Swift: not yet measurable** *(superseded: `swift-matrix-stable` runs the
pinned swift-format over every `.tb.swift`; see "Every matrix survives every
formatter")*. There is no matrix *declaration* syntax in Swift
until `TabulaMacros` lands — the reference machine writes its dispatcher by
hand, and the `Table(...)` literals are one row per line but not column-aligned.
A `swift-matrix-stable` check today would guard nothing. It becomes the right
thing to add in the same patch as the macro, and not before.

*Superseded: the formatter was written (see the boxes above) and `tb-aligned`
runs it over every matrix. The analysis below is what argued against writing
it, kept for the record.*

**So the first task is still not the formatter.** The evidence so far says the
danger is real but that per-path configuration handles it. Write `tabula-fmt`
only if a case turns up that configuration cannot fix — and note that `.tb.*`
would cost Rust users a `#[path]` attribute on every matrix module, which is the
largest single cost in the proposal and buys nothing for the language that is
already safe.

## 0e. Nothing skips silently; swift-syntax is next

Two findings, both the shape of 0c.

**Twelve skips were invisible to the ledger.** `tools/verify` collects lines
beginning `skip `, but every toolchain-absence skip said `note: $KOTLINC not
found; skipping` instead. So the mechanism built to make skips visible could
not see the most common skip in the repository. All twelve now use the prefix
and name their step.

**Six Swift checks vanish from the flake on Linux.** `lib.optionalAttrs
(has.swift && swiftChecked)` drops them, and a smaller attribute set is
indistinguishable from a correct one in `nix flake check` output -- the same
property that hid the whole Kotlin suite in 0c and that 0d refused to repeat
for `kotlin-ksp`. A `swift-unavailable` check is now present on exactly the
platforms where the others are not, and says which six are missing and why.

It passes rather than fails, unlike `kotlin-ksp` without its lock. The
distinction is whether the user can fix it: a missing lock is one command, and
a Swift toolchain nixpkgs does not package for this platform is not. A check
that cannot go green is noise with a red light.

### Still skipping, and what it would take

`swift-macros` skips for **two** stacked reasons, and only one of them is a
dependency problem:

1. `swift-syntax` is remote and the sandbox is offline. This is the half that
   looks exactly like the Gradle problem in 0d, and the same answer fits:
   `Package.resolved` already pins every dependency to a revision, so a
   `tools/swift-lock` could record each as a GitHub archive URL plus a sha256
   and `nix/swift-deps.nix` could `fetchurl` them into `.build/checkouts` with
   a `workspace-state.json`, exactly as `gradle-lock` does for Maven. It is
   the core of `swiftpm2nix`, the same way `gradle-lock` is the core of
   `gradle2nix`.
2. The pinned toolchain's SwiftPM ships no `CompilerPluginSupport`, so
   `Package.swift` fails to **compile** before resolution is even attempted.
   No lock can fix this. It is upstream of every dependency question.

Doing (1) while (2) holds produces a vendored dependency set that SwiftPM never
gets far enough to use. So (2) has to be answered first, and answering it is
one command on a machine with a Swift toolchain:

```
cd tabular-center-swift/macros && swift build
```

`no such module 'CompilerPluginSupport'` means (2) is live and the lock is
premature. A network error instead means (2) has aged out -- the note dates
from an older toolchain -- and the lock is the whole remaining job.

- [x] Run it. Answer: (2) is live. nixpkgs' **swiftpm 5.10.1** ships no
      `CompilerPluginSupport` in its ManifestAPI.

      ```
      error: 'macros': Invalid manifest
      Package.swift:5:8: error: no such module 'CompilerPluginSupport'
      ```

      Which confirms the lock would have been premature in the most expensive
      way: it would have produced a correct, verified, vendored swift-syntax
      that SwiftPM never got far enough to ask for.

- [x] Make the manifest compile, which is upstream of everything else.
      `Package.swift` now imports only `PackageDescription` and declares a
      plain `.target`. `TabulaMacroDecl` moved to `pending/` — `#externalMacro`
      names a module SwiftPM only wires up for a `.macro` target, so declaring
      it without one yields a macro nobody can apply.

      The cost is smaller than it looks. `MachineMacro`'s whole job is
      SwiftSyntax to `RawMachine`, which is a function over syntax trees:
      writable, buildable and unit-testable here by parsing source with
      `SwiftParser`. Expansion is the only part needing plugin wiring and it is
      the part with no decisions in it. `SURFACE.md`'s two open questions
      become answerable by a test rather than by a toolchain upgrade.

- [x] Export `TabulaCodegen` as a product of `tabular-center-swift/Package.swift`. With the
      manifest compiling, resolution got far enough to find the next blocker,
      which had been sitting behind it since `tabular-center-swift/macros` was written:

      ```
      error: 'macros': product 'TabulaCodegen' required by package 'macros'
      target 'TabulaMacroSyntax' not found in package 'swift'
      ```

      SwiftPM only lets one package reach another's *products*, and
      `TabulaCodegen` was a target only. The original `.macro` manifest named
      the same product and would have hit this too -- two blockers stacked, the
      first hiding the second, which is the argument for fixing the outermost
      one rather than reasoning about the pile.

      Swift-syntax resolved at 509.1.1 on the way past, which is the version a
      lock will pin.

- [x] `tools/swift-lock` and `nix/swift-deps.nix`, `nix run .#swift-lock`,
      and the lock itself — `nix/swift-lock.json` pins swift-syntax 509.1.1.
      `swift-macros` resolves offline from `TABULA_SWIFT_DEPS` when nix has
      built the checkout set. Kept for the record, the reasoning that made it
      the right next step rather than a premature one: with the manifest compiling, the *only*
      thing between `swift-macros` and running under `nix flake check` is that
      swift-syntax is remote. `Package.resolved` already pins it; the shape is
      `gradle-lock`'s, one artifact one hash, generated once with network by
      `nix run .#swift-lock` and committed.
- [x] The half of `MachineMacro` that needs no plugin wiring:
      `Sources/TabulaMacroSyntax/MachineSyntax.swift`, SwiftSyntax to
      `RawMachine`, checked by `TabulaMacroSyntaxCheck` against the 11
      rejection fixtures in `tabular-center-swift/macros/fixtures/`.
- [ ] Restore `pending/Machine.swift` and the `.macro` target on a SwiftPM
      that ships `CompilerPluginSupport`. Only `Package.swift` changes.
      `nix/swiftpm-plugin-support.nix` now builds the module; what remains, per
      the note at the top of `tabular-center-swift/macros/Package.swift`, is that
      `swift build` still loads nixpkgs' original ManifestAPI rather than the
      augmented one. `tools/verify swift-macro-support` reports which.

## 0f. Kotlin under `nix flake check`: one compiler, and checks that run

An audit of the tree against this file and `ARCHITECTURE.md`, with Kotlin
under the flake as the priority. Two defects, both of the shape this file
keeps recording -- something that looked checked and was not compared against
anything.

**The flake's kotlinc floated.** `kotlinInputs` took `pkgs.kotlin`, whatever
the channel ships. Every other place names 2.1.20: both `build.gradle.kts`
files, the KSP pair `2.1.20-1.0.32`, `ci.yml`'s check-no-nix download, and
`tabular-center-kotlin/README.md`. The bump from `nixos-25.05` to `nixos-26.05` -- made for
Swift -- therefore changed the Kotlin compiler too, silently, and the four
`tabular-center-kotlin/compile_fail/` fixtures plus `codegen/compile_fail/` match kotlinc's
own message text, which a compiler release is free to reword. Same shape as
0c: a change to one language's toolchain landing in another's checks.

- [x] `kotlinc` owned in `nix/context.nix` (`kotlinVersion`), fetched from the
      JetBrains release by hash and wrapped with the flake's JDK. Not
      `pkgs.kotlin.overrideAttrs`, which would depend on nixpkgs' installPhase
      for a release it was not written for.
- [x] `tools/verify` prints a `note:` from the two text-matching steps when the
      kotlinc on PATH is not the version `06-generated` names. A note, not a
      failure -- the same call `kotlin-ksp` makes on Gradle version skew.

**`06-generated`'s checks were compiled and never run.** `test/GeneratedTest.kt`
and `test/GateTest.kt` are `main` functions; `gradle build` compiled them and
its JUnit `test` task found nothing to discover and passed. `tabular-center-kotlin/ksp/README.md`
said "the behavioural checks passing against it". They had never executed --
including `GateTest`, the only check on the suspend machine driven by
`SuspendDriver`.

- [x] One `JavaExec` per check, hung off `check`, so `gradle build` runs them.
      The JUnit task is disabled: nothing to discover, and from Gradle 9 an
      empty discovery is a failure rather than a pass.
- [x] `GateImpl.chime`'s doc described a follow-up the code does not return.

**Docs that had fallen behind the tree**, corrected in the same patch:
`ARCHITECTURE` 12/13 and `tabular-center-kotlin/README.md` still said KSP had never run and
that 06-generated is skipped under nix; `tabular-center-kotlin/ksp/build.gradle.kts` was
headed UNVERIFIED; the 0b and 0d boxes above were open for work that is in
the tree; the status counts were a release behind.

Found and **not** fixed in this patch, in priority order:

- [x] `ignore-heavy` and `no-static-exit` have fixtures (`.tbl`, goldens,
      traces) and had no adapter in **any** language, so all three harnesses
      reported them as `skip`. `diagnostics-coverage.md`'s `fixtures` table
      already credited them, which was true of the goldens and not of any
      implementation's output.
      - [x] Kotlin: `IgnoreHeavyAdapter`, `NoStaticExitAdapter`. **The first
            implementation to read `ignore-heavy.cov` found it wrong.** The
            golden's warning line stopped at `75% of cells are IGNORE`; all
            three renderers print `; consider splitting this machine` after
            it. So the golden was typed rather than blessed -- the thing
            `spec/conformance/README.md` says never to do -- and no harness
            could say so while none had an adapter. Corrected to what the
            three renderers agree on, which also matches the `.lint` line.
            `no-static-exit.tbl` also claimed to be the first fixture using
            EMIT; `toggle` is. Comment corrected; no golden changes.
      - [x] Rust: `machines/ignore_heavy.rs`, `machines/no_static_exit.rs`.
            `Poll` is the first 4x5 `transition_matrix!` in the conformance
            crate; `scale.rs` recorded a recursion-limit cost past ~7x10, well
            clear of this. Rust now reads the corrected `ignore-heavy.cov`
            too, so two renderers agree on it rather than one.
      - [x] Swift adapters: `IgnoreHeavyAdapter` over `POLL_TABLE`,
            `NoStaticExitAdapter` over `BEACON_TABLE`. With them the third
            renderer reads both goldens, so `ignore-heavy.cov` — the one found
            typed rather than blessed — is now agreed on by all three.
- [x] `no-static-entry` and `unreachable-heavy` still have no fixture.
      - [x] `no-static-entry`: `Door`, the first **fully static** fixture —
            no `HANDLE`, so no cell surface at all in any language. Pins the
            reachability gate open, where `effects-never` pins it shut, and
            puts an `EMIT` in the unreached row so an implementation counting
            `EMIT` as a self-transition goes silent and fails.
      - [x] `unreachable-heavy`: `Link`, three `UNREACHABLE` of twelve —
            25%, the threshold exactly, so `>` for `>=` fails it the way
            `payload-hoist` pins its own boundary. Traces never visit a
            trapping cell; the claim is carried by the table and goldens.
- [x] 4c-old's seven open boxes describe the processor as unwritten; most are
      now either done by `TabulaProcessor.kt` or superseded by `codegen/`.
      Done: five closed or superseded, with the reason beside each. Two stay
      open and are real — the prototype's context parameters / receiver /
      visibility are not read, and diagnostics point at the declaration
      rather than the row.
- [x] `Kind` has no `EXPAND` although 4b lists it. Confirmed: the checkbox was
      wrong and is corrected. The finding underneath it is larger than the
      box, though — `EXPAND` is implemented **nowhere**: no language parses
      it, no fixture uses it, and ARCHITECTURE 6 R5 described it in the
      present tense. R5 now says so; the work itself is not scheduled.

## Skips are named, everywhere

`tools/verify` collects every line beginning `skip ` and reprints it before the
verdict. The conformance harnesses were the one place that never reached it:
all three printed a COUNT of fixtures with no adapter — `1 fixture(s) have no
Rust adapter (skipped)` — which says how many without saying which, and does
not carry the prefix the ledger greps for.

So the harness that exists to make missing coverage visible was invisible to
the tool that exists to make skips visible. All three now name each fixture on
its own `skip <name> (no <lang> adapter)` line.

When this landed nothing was skipped — `payload-hoist` had closed the last
gap. That stopped being true when `ignore-heavy` and `no-static-exit` arrived
with Kotlin and Rust adapters only (0f), and the ledger is how that showed.
Their Swift adapters have since landed, so it is true again. The next fixture added before its adapters
is the one that would have gone quiet.

## Backlog — happy paths

Prior art, and it is ours: [`hadilq/happy`](https://github.com/hadilq/happy)
does this for `sealed` classes. `@Happy` marks one variant as the success case
and a processor generates a DSL that narrows to it, so the caller writes

```kotlin
val result: HappyA = doWork() elvis (
    OptionOne = ::handleOptionOne,
    OptionTwo = { f -> return B.failure(f.why) },
)
```

instead of a `when` over every branch. The argument in that README is worth
restating because it is the same argument this repository makes about matrices:
Kotlin's null-safety is loved not because `Optional` is clever but because the
happy path reads differently from the failure. `when` flattens that back out.

The task here is the state-machine version. A user marks the happy path **in
the matrix** — which is where every other fact about the machine already lives
— and the generator derives defaults from it and offers a narrowed calling
surface for developers who only want to say what happens when things go right.

### The one thing to get right

A happy-path sugar is an `else` unless it is built very carefully, and `else` is
the thing this library exists to make unavailable. ARCHITECTURE 1: the
dispatcher exists only in generated code so that `else` is not a temptation but
an absence.

`happy` ships both shapes and the difference is exactly the line:

- **`elseIf`** takes one lambda for everything that is not the happy variant.
  That is an `else`. Add a state and the lambda still compiles, still runs, and
  now silently swallows a case nobody has considered — the failure mode the
  matrix exists to prevent.
- **`elvis`** takes one named parameter per non-happy variant. Add a variant and
  every call site stops compiling. That is exhaustiveness wearing nicer syntax,
  which is the whole of what we want.

So: the `elvis` shape, and the `elseIf` shape only where a machine has exactly
two outcomes, where the two are indistinguishable. That restriction has to be
enforced by the generator rather than documented, for the usual reason.

### What "the happy path" is in a matrix

Two readings, and they are not the same feature:

1. **Per-cell.** A cell is marked happy; the generated member for it is the one
   with the convenient name and the narrowed return.
2. **Per-run.** The happy path is a *spine* through the table — a sequence of
   transitions from `initial` to a terminal state — and marking it is marking a
   route rather than a square.

(2) is the one that earns its keep. It is what makes defaults derivable: a
`HANDLE` cell on the spine with no declared target defaults to the next state
along it, so the common case stops being typed at all. It is also what gives
the lints something to check. (1) falls out of (2) for free.

Open, and the reason this is backlog rather than a phase:

- **How is a spine written?** A `Kind.HAPPY` alongside `GO`/`HANDLE` reads
  wrong — happiness is orthogonal to what a cell *does*. A `happy = true`
  argument on the existing kinds is honest but verbose in a file whose entire
  point is that a reader scans columns. A separate `@Path` annotation naming a
  state sequence keeps the matrix clean and puts the route somewhere a reader
  will not see it. No obvious winner yet.
- **Does a machine get more than one?** Probably yes, and then they need names,
  and then the calling surface needs to say which one it is narrowing to.

### It has to be three languages

The convergence rule (ARCHITECTURE 2) applies: one guarantee, three
implementations. The `elvis` shape is Kotlin-shaped and does not transfer
directly.

- **Rust.** The narrowed result is a `Result`-alike and `?` already does this.
  The interesting question is whether the generated type can be `Try`-compatible
  so the happy path is a `?` and nothing else is needed.
- **Swift.** `guard case .happy(let x) = step else { ... }` is the existing
  idiom, and a generated `throws` overload plus `try` is the closer analogue.
  Either way the compiler has to reject a missing case, which `guard ... else`
  does not.

If it cannot be made to hold in all three, it is Kotlin sugar and belongs behind
the same kind of gate as the rendering surface in 9b — not in the core.

### Order of work

Per the cross-cutting rule above, behaviour lands in `spec/conformance` first.
That is not ceremony here: a happy path changes what a *run* means, so the
fixture format itself may need a field, and finding that out after three
implementations is how the expensive version of this goes.

**`spec/happy-paths.md` is now the source of truth for this feature** and
carries its own checklist; the boxes below track it rather than duplicate it.

- [x] Read `hadilq/happy`'s processor, `happy-processor-common`, for what the
      generated DSL actually looks like once nested cases are involved — the
      naming scheme there (`SituationOneOptionTwo`) is the part that got
      thought about, and matrix cells have the same flattening problem.
      Read from source; findings in `spec/happy-paths.md`, "What
      `hadilq/happy` does". Leaves flatten by path with no separator; `elvis`
      is an `inline` extension on the sealed type (which is what lets a handler
      `return` from the caller) with one UpperCamel parameter per leaf and a
      `when` with no `else`; `elseIf` loses an omitted case to `result!!` at
      runtime, which is the documented reason it is forbidden here. Two
      consequences for this project: a hop's `elvis` cannot be a `Cells`
      member (interface members cannot be `inline`), so the narrowed surface
      needs a generated per-hop outcome type; and flattened names are never
      collision-checked -- neither there nor here
- [x] Member-name collisions: `tabular-center::member-collision`, Kotlin and
      Swift, in `buildDesc`. Every member of the generated `Cells` surface --
      HANDLE cells, DELEGATE prisms, child lens members, effect handlers -- is
      checked against every other, from the list the emitter names them
      from (`cellsMembers`), so the check cannot disagree with the emitter.
      Refused in Kotlin too, where it would compile as overloads: one rule
      across both. Not Rust, which generates no member names. Fixtures: a KSP
      one positioned at the second colliding row, and a Swift macro one,
      `(logIn, start)` against `(log, inStart)`. No existing machine collides
      (20 Kotlin specs scanned; the scan does flag the fixture)
- [x] Decide spine-vs-cell and the declaration syntax, in `spec/`, before any
      implementation. A spine, declared by a separate `@Path` whose elements
      alternate state and action.
- [x] ~~A conformance fixture with a happy path~~ — answered without one:
      `.tbl` needs no field, because the spine resolves away before anything
      a fixture compares. Coverage is compile-fail fixtures instead.
- [x] Checks that only exist once a spine does — as compile-time diagnostics,
      not lints: `path-broken` (covers a spine leaving through an `IGNORE`),
      `path-unterminated`, `path-unknown-state`, `path-duplicate`, in Kotlin
      and Swift, with four fixtures each. **Not Rust**, where `@Path` does not
      exist yet.
- [x] The narrowed calling surface, `elvis`-shaped, with the two-outcome
      `elseIf` special case allowed and everything else refused.
      *Design constraint from the `happy` reading:* Kotlin's `elvis` must be
      an `inline` extension on a generated per-hop outcome type, not a `Cells`
      member, for handlers to `return` from the caller
      *Decided* in `spec/happy-paths.md`, "Settled before implementation": a
      hop member takes the action that arrived (after derivation every hop
      cell is a `GO`, so the hop's own action has one outcome and nothing for
      `elvis` to do); its outcomes are the states the `from` row can produce,
      keyed by state; effects come back with the state, never run inside;
      Kotlin `inline` extension on a per-hop sealed type, Swift labelled
      `rethrows` closures, Rust `into_happy()` and `?`. Implemented in all
      three: Kotlin (emitter, KSP) and Swift row-precise; Rust generic,
      `narrow::<From, Action, _>` with the whole `State` as its `Err` side,
      chosen over a proc-macro or `paste` dependency because `macro_rules!`
      cannot build names or deduplicate sets. The checklist is in
      `spec/happy-paths.md`, "Order of work"
- [x] Defaults derived from the spine: a `HANDLE` named by a hop becomes a
      `GO` (`derive` in `codegen/Raw.kt` and `TabulaCodegen/Raw.swift`), shown
      by `examples/kotlin/06-generated/src/Spine.tb.kt` and pinned by
      `ksp/golden/SpineGenerated.kt.golden`.
- [x] Rust: `paths { .. }` as a `transition_matrix!` arm, by approach A --
      chosen to keep Rust close to Kotlin and Swift. The path compiles to a
      local `__tabula_hop!` whose rules are its own identifiers, since
      `macro_rules!` cannot compare two; every cell passes through it once,
      before `@main` sees a row, so the three munchers are untouched and a
      machine without `paths` never reaches the new arms.
- [x] Rust: the four `path-*` codes. `path-unknown-state`, `path-broken` and
      `path-unterminated` in tabula's own words, from lookups generated out of
      the declared states and actions and extra rules in `__tabula_hop!`;
      `path-duplicate` by rustc, like `unknown-child`. Errors continue the
      munch, so the rest of the machine expands and the tabula error is the
      one a reader sees first

## PlantUML — removed

`toPlantuml` is gone from all three cores, the `.puml` goldens are deleted, and
`GOLDEN_EXTS` is `grid lint cov`. Mermaid and DOT stay.

What went with it is worth naming, because the section above argued for the
golden and the argument was right: the `.puml` snapshot was the only thing
comparing a line of diagram output **across** the three implementations, and it
was added after they had already drifted -- Rust emitting every `GO` edge
before every self-loop while Kotlin and Swift interleaved them in cell order.

Each language now pins its own edge order against a literal in its unit tests.
That catches one renderer growing a second walk. It does not catch the three
disagreeing with each other, which is the failure that actually happened.

- [x] Restored on mermaid. `<name>.mmd` per fixture, six of them, compared by
      all three harnesses; `GOLDEN_EXTS` is `grid mmd lint cov`. The goldens
      were generated from the `.tbl` files by a script mirroring `edges` and
      `toMermaid` rather than typed, for the reason two earlier hand-written
      literals give.
- [x] Derived again, in all three. Kotlin and Swift now compare mermaid
      against DOT the way Rust does, and no hand-written edge list is left in
      the repository.

      Worth keeping as a note rather than just a checkbox: the literals were
      introduced as a stopgap when PlantUML left, and one of them was wrong
      within the hour -- it said `Idle->Running` where HANDLE draws a
      self-loop, which reads correctly off the matrix and is wrong about the
      diagram. A derived comparison cannot make that mistake, because neither
      side is anybody's belief about what the walk should produce.

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

## Backlog — four GUI examples: Compose and iced

Two Kotlin apps on Compose Desktop, two Rust apps on iced. In each pair, one
small machine and one composing several with payloads. They exist to be *shown*
— the current examples are correct and none of them is a screenshot.

### Why iced is the sharper of the two

iced is The Elm Architecture: a `Message` enum, and

```rust
fn update(&mut self, message: Message) -> Task<Message>
```

which is a hand-written dispatcher over `(state, message)` — the exact artifact
this library exists to delete, in a framework people already use. The demo is a
substitution, not a decoration: `Message` becomes `A`, `update` becomes the
generated `step`, and the `match` with its `_ =>` arm stops existing.

The effect story lines up too, which is luck worth using. `perform(cells, ctx,
f) -> A?` returns an optional follow-up action; iced's `Task<Message>` is an
optional follow-up message. One maps onto the other with no adapter layer, so
the example can show effects being carried out rather than describing them.

Compose has no equivalent shape. State lives in `remember`/`MutableState` and
effects in `LaunchedEffect`, so the Kotlin apps demonstrate a `Driver` feeding a
`StateFlow` the UI collects. Worth doing, and a weaker argument than the iced
one — say so in the README rather than implying symmetry.

### Happy paths come first

Requested as the reason to build these, and the ordering is right rather than
merely convenient. A UI is where the asymmetry actually shows: the success path
is a screen, and the rest is an error banner. An app that renders

```kotlin
val next = machine.send(action) elvis (
    Rejected  = { showBanner(it.why) },
    Locked    = { navigateToSupport() },
)
```

makes the case in a way no test can. Which also means the apps are the
acceptance test for that design: if the sugar does not read well in a `@Composable`
or in `view()`, it is the sugar that is wrong.

So: **happy paths land first**, and these four are what judge them.

### The dependency problem, which is the real work

These are the first things in the repository with heavyweight third-party
dependencies, and each lands on machinery that is half-built.

**Rust/iced is the harder half, and it is a new instance of a solved problem.**
Every example today depends on `tabula` by path and nothing else — the entire
`examples/rust` workspace has zero crates.io dependencies. `CARGO_NET_OFFLINE=true`
in `mkCheck` works because there is nothing to fetch, not because anything
vendors it. iced pulls in winit, wgpu and a few hundred transitive crates, so
this needs the Cargo analogue of `gradle-lock` and `swift-lock`:
`Cargo.lock` already pins everything, and nixpkgs' `importCargoLock` consumes
exactly that. Third instance of one pattern, and the cheapest of the three,
because Cargo writes a complete lock as a matter of course.

Worth noting what it changes: `CARGO_NET_OFFLINE=true` currently passes
vacuously. Once a real dependency exists it starts meaning something, and a
missing vendor directory becomes a failure rather than a no-op.

**Kotlin/Compose is easier and noisier.** `tools/gradle-lock` resolves whatever
the example builds, so adding a Compose app is a re-lock and nothing more. But
Compose Multiplatform pulls hundreds of artifacts, so `nix/gradle-lock.json`
goes from a readable file to a large one. That is fine — it is generated and
hash-verified — but it stops being reviewable by reading, and the check that it
is current stops being optional.

**Compose Desktop, not Android.** The Android SDK is not something the flake
can supply without a licence-accepting download, which is the opposite of every
other dependency here. Desktop keeps it a plain JVM Gradle build, which is what
`06-generated` already proves works offline.

### What "checked" means for a GUI

A window cannot be run in `nix flake check`, so be explicit about the split
rather than letting a green check imply more than it covers:

- The machines are checked the way every other example is — headless, through
  the generated dispatcher, with the same trace fixtures.
- The UI layer is **compiled only**. That catches the thing worth catching: add
  a state or an action and the `Composable` or `view()` stops compiling,
  because the generated `Cells` surface changed. Which is the library's whole
  claim, demonstrated on a real framework.
- Nothing asserts what is on the screen. Saying so in the README is the point;
  an example that overclaims its coverage is worse than one that covers less.

### Order of work

- [x] Happy-path sugar, per the backlog above. These apps are its acceptance
      test and should not be written before it. (They were written first,
      and served as its acceptance test after.) Finding, in
      `spec/happy-paths.md`: it reads well in code that owns its stepping --
      `CheckoutCheck`'s `purchase` -- and has no place in a `model()` that
      `rememberMachine` drives, since the narrowed members hand effects back
      for their caller to run
- [x] `Cargo.lock`-driven vendoring for `examples/rust`, so a crates.io
      dependency can exist at all. `examplesVendor` in `nix/context.nix` is
      `importCargoLock` over the committed lock, and the `rust-examples` check
      points cargo's `crates-io` source at it, with `--offline --locked` from
      `tools/verify`. Nothing to generate and nothing to keep in step: the
      vendor directory is a function of the lock. Vacuous until the first
      real dependency, which is why it lands first. Adding one needs network
      once, on a developer machine: `cd examples/rust && cargo add <crate>`,
      then commit the updated `Cargo.lock` -- nix vendors the rest.
- [x] iced app 1: `examples/rust/05-iced`. The same connection machine as the
      Compose example, so the two read side by side: same states, same
      effects, different hosts. iced's `update` IS the substitution -- it
      sends an action and `Driver` does the rest, so `view` contains no
      transitions at all. The cells and the context travel as one tuple,
      because `dispatch` hands one environment to both closures; two closures
      borrowing them separately do not compile, which is what `03-retry` was
      restructured around. `tests/connection.rs` drives it with no toolkit,
      and nothing asserts the screen. First example with a third-party
      dependency, so the first real exercise of the Cargo vendoring -- and of
      `guiInputs`, since winit and wgpu look for fontconfig, xkbcommon, X11
      and wayland through pkg-config, which vendoring crates cannot supply.
      The window renders its own `TABLE`, so the machine is visible in the
      application rather than only behind it, and the README sets the
      hand-written `update` beside the three-line one for contrast -- which
      is what this item asked for.
      It is NOT a member of `examples/rust`'s workspace: iced's tree needs
      edition 2024, which 1.75's cargo cannot parse, so it has its own lock
      and its own check on current stable. tabula's MSRV stays where it is
      worth holding -- the library, and the four examples that depend on
      nothing else -- rather than being spent on a GUI application.
- [x] iced app 2: composition and payloads, in the same package as app 1 --
      a session containing a connection, the same pair as the Compose example
      rather than the `nested-delegate` fixture, so the two GUI examples read
      side by side. Two machines in one crate means two modules, since each
      generates `State`, `Action`, `step` and `TABLE`; the `#[path]`
      declarations sit at the crate root, as `04-login`'s do. One `Cells` type
      satisfies both surfaces, so a hole in the child is a build error in the
      parent. The prism declines while the connection dials, which is where
      "this button does nothing right now" lives -- in the table, not in a
      disabled button. The window shows both matrices.
- [x] Compose app 1: `examples/kotlin/07-compose`, in **bitkey's**
      architecture rather than over a `Driver` and a `StateFlow` -- the
      repository being matched (`proto-at-block/bitkey`,
      `app/libs/state-machine`) holds state in the Compose *runtime*:
      `interface StateMachine<PropsT, ModelT> { @Composable fun model(props) }`,
      machines composed by a parent calling a child's `model()`. The
      interface is eight lines in the example; tabula ships nothing for it,
      which is the demonstration -- tabula decides what a machine does, the
      architecture decides where it lives. `rememberMachine` drives the
      generated `step`/`perform` with the same enqueue-don't-recurse rule as
      `Driver`. Machine checked headlessly, UI compiled only, nothing asserts
      the screen -- stated in its README.
- [x] `@Path(back = ..)`, in Kotlin: the reverse of a route derives too. The
      first version of the spine derived forward hops only, which saved one
      target per step and left the wizard writing its whole `Back` column by
      hand -- the route again, backwards, where a wrong target looks like a
      right one. Derived over `HANDLE` cells only, so explicit cells win and a
      path without `back` is unchanged; unknown back actions are
      `tabula::path-unknown-state`.
- [x] `back` in Swift: a labelled third argument on `@Path`, read by
      `MachineSyntax`, derived by `derive` over HANDLE cells in both
      directions, with the same two rules Kotlin gained -- an undeclared back
      action is `path-unknown-state`, and a path's own back column does not
      count against `path-unterminated`. Checked in the codegen check (the
      four derivation cases) and in the macro check (that `back:` survives
      extraction, and that neither direction leaves a cell member behind).
- [x] `back` in Rust: `checkout: [..] back Back;` in the `paths` block. A
      second rule set in the generated `__tabula_hop!`, keyed on each hop's
      far side, deriving a HANDLE and passing anything else through. Two
      rules per reverse hop and no diagnostic, which is deliberate: a path has
      no opinion about what else a back action does, and passing is also what
      keeps a back cell clear of the `path-unterminated` rules, since walking
      a path backwards is walking the path. The back action is checked against
      the declared actions like any other name. All three implementations now
      agree.
- [x] A third Compose screen, `CheckoutMachine.tb.kt`: the happy path at a
      size worth showing. Five states on a `@Path`, four hops derived, two of
      them written as GOs because they emit, and the rest of the table -- back,
      decline, abandon, retry -- as the half a spine does not describe. Its
      states are payload-free because a derived GO carries no constructor
      arguments (`tabula::go-target` is what says so), and the payload lives
      where an explicit GO can supply it: `Declined(reason)`.
- [x] Compose app 2: composition and payloads, as a second screen in the same
      project -- no new dependencies, so it cannot turn the check red on
      artifacts. `SessionSpec` delegates to `ConnectionSpec` through the KSP
      DELEGATE surface, its state contains the child's, and the generated
      `session.Cells` extends `connection.Cells`, satisfied by Kotlin
      delegation to the child's implementation. The UI nests bitkey's way,
      `model()` inside `model()`, and the nested screen sends the PARENT's
      action: the prism decides which child action it is, so the matrix stays
      the only place a transition is decided.
- [ ] A screenshot in each README, which is most of why these exist.

## Every matrix survives every formatter

`kotlin-matrix-stable` existed and the other two languages had nothing. A
matrix is column-aligned on purpose and a formatter's job is to normalise
exactly that, so "the formatter leaves it alone" is a claim each language has
to make separately — and each makes it for a different reason, which is why one
check cannot cover three.

- **Kotlin.** ktlint formats Kotlin it understands, so the alignment survives
  only because `.editorconfig` disables four rules for `[*.tb.kt]`. The
  exemption is load-bearing and the check proves it still is.
- **Rust.** rustfmt needs no exemption: `transition_matrix!` takes a body that
  is not a Rust expression, so rustfmt bails on the whole invocation. That is
  an implementation detail of rustfmt rather than a promise, and 28 files
  depend on it. A release that got better at formatting macro bodies would
  collapse every matrix in the tree, and `cargo fmt --check` in `rust-fmt`
  would then demand the collapsed form forever after.
- **Swift.** Nothing to check against yet, which is not the same as safe.

- [x] `rust-matrix-stable`, scanning `tabular-center-rust/` and `examples/rust/`. Separate
      from `rust-fmt` because `cargo fmt --check` asks whether the tree matches
      rustfmt's opinion, and this asks whether rustfmt has one about matrices
      at all.
- [x] `kotlin-matrix-stable` extended to `examples/kotlin/`. It scanned the
      library only, so it reached one file and missed
      `examples/kotlin/06-generated/src/Machine.tb.kt` — the matrix a user
      copies, and so the more important of the two.
- [x] Both fail on an empty scan. `for f in $(grep -rl ...)` matching nothing
      prints nothing and returns zero, which is how either check would report
      success after a rename moved every matrix out from under it.
- [x] The exemption, which needed no dependency and was mis-specified:
      `spec/matrix-files.md` said swift-format has no in-file suppression. It
      has `// swift-format-ignore-file`, and since swift-format has no
      per-glob rule configuration, that directive is the whole mechanism. All
      seventeen `.tb.swift` files carry it, and `swift-format-config` requires
      it on every one -- checkable with no toolchain, so it holds the day
      before swift-format arrives rather than the day after it collapses a
      grid.
- [x] `swift-matrix-stable`, against `swift-format` itself. Route 1: the
      pinned `nixpkgs-swift` carries swift-format 5.10.1, and `context.nix`
      already put it in `swiftPkgs`, so this needed no lock entry, no build,
      and no version question of its own -- the pin that answers Swift's
      answers it. The step formats a copy of every `.tb.swift` and requires
      the file back byte for byte, which the ignore directive makes true.
      It opens with a liveness probe: swift-format must rewrite a
      deliberately misformatted file first, or the step reports that it
      cannot tell whether the formatter ran rather than passing seventeen
      files. The SwiftPM-dependency route was not needed.
- [x] A check that every `.tb.` file in the tree is covered by one of the
      three: `matrix-covered`. It enumerates the files that exist and asks
      which scan reaches each. `.tb.swift` is covered by
      `swift-format-config` reading its ignore directive: weaker than running
      a formatter, and no longer a skip, because something is looking.

## swift-matrix-stable — the cost, and what stands in until it is paid

The Kotlin and Rust matrix checks have no Swift counterpart, and the asymmetry
is not an oversight. It is worth writing down before someone "completes the
set" without pricing it.

**What the other two guard is a formatter that runs.** `cargo fmt --check` is
in `rust-fmt`; ktlint is on the path and a contributor may reach for it.
`swift-format` is not used anywhere in this repository, so a
`swift-matrix-stable` would guard a formatter nobody invokes.

**What it costs.** A second remote SwiftPM dependency in `tabular-center-swift/macros`, which
means `nix run .#swift-lock` again and swift-format's own tree — swift-syntax,
swift-argument-parser and more — entering every `swift-macros` build.

**And a version trap.** swift-format's releases track swift-syntax's:
swift-format 510 requires swift-syntax 510, and `tabular-center-swift/macros` pins
`from: "509.0.0"`, resolving to 509.1.1. Taking swift-format 510 drags
swift-syntax to 510 underneath `MachineSyntax`, so the traversal's API surface
moves as a side effect of adding a formatter check. swift-format 509.0.0 avoids
that and is the version to use.

**What stands in meanwhile.** `swift-format-config` — a check with no
dependencies that fails if a swift-format configuration ever appears without
mentioning `.tb.swift`. `Turnstile.tb.swift` survives today because nothing
formats it, which is luck rather than a design, and the luck expires precisely
when someone adds that config. This is the check standing there when they do.

- [x] `swift-format-config`, on every platform including those with no Swift
      toolchain. The risk is a file appearing in a commit and a commit can come
      from anywhere; gating it on `swiftChecked` would have removed the guard
      from the machines most likely to add a config they cannot run.
- [x] `swift-matrix-stable` proper. The cost above never had to be paid: the
      pinned `nixpkgs-swift` carries swift-format 5.10.1 and `context.nix`
      already had it in `swiftPkgs`, so it needed no SwiftPM dependency, no
      lock entry and no version of its own. It formats a copy of every
      `.tb.swift` and requires it back byte for byte, behind a liveness probe
      so a formatter that silently does nothing cannot pass seventeen files.

## The three implementations had diverged on diagnostics

Nothing compared them. `tools/docs --check` verified every code in
`spec/diagnostics.md` has an anchor in the rendered page — link integrity, not
behaviour — and each implementation's own tests checked its own messages. No
check asked whether the three emit the same set.

They do not. Rust emits twelve codes; Kotlin and Swift emit sixteen. (Twenty
since, with the four `path-*` codes, which Rust also lacks — see
`spec/diagnostics-coverage.md`.) Rust omits
`tabula::go-target`, `tabula::unknown-state`, `tabula::unknown-effect` and
`tabula::unknown-child`, and `tabula::color-mismatch` has a section in the spec
and no implementation at all.

The Rust gap is correct. All four say "a cell names something the machine does
not declare", and in Rust the matrix is `macro_rules!`, so `GO!(Typo)` expands
to a path that does not resolve — rustc names the token in the user's own file,
points at their line, and suggests the states that exist. A `compile_error!`
checking it first would replace a better message with a worse one. Same
argument `RELEASING.md` makes for Rust being one crate where Kotlin is five:
the language does the work.

Correct and unwritten, though, which is the part worth fixing. An unstated gap
is one a refactor closes or widens without anyone deciding to.

- [x] `spec/diagnostics-coverage.md`: a machine-readable table of code against
      implementation, with the reasoning for every absence.
- [x] `diagnostics-coverage`, checking it in **both** directions — a code
      emitted but unlisted, and a code listed but not emitted, both fail.
      One-directional would have missed the case that matters most, an
      implementation quietly losing a diagnostic.
- [x] Quoted matches only. `tabula::lint::report` is a module path, and
      counting it would have credited Rust with three codes it does not have —
      the check would have passed by measuring the wrong thing.
- [x] `tabula::color-mismatch` decided: **reserved, emitted by nobody.** Not
      unimplementable in principle, but unnecessary in all three, and for one
      reason -- every generator puts the PARENT's color on the call into the
      child, so the language refuses a colored child under a colorless parent
      before any check of ours could run. Each language now has a fixture
      proving it, and `spec/diagnostics.md` lists all three. Kept in the spec
      rather than deleted: it is the answer for a generator that cannot carry
      the color onto the call and would have to compare colors instead. The
      `-` row stays, and now means "by decision" rather than "nobody has
      looked".

## Five of seven lints are never tripped by a fixture

The diagnostics table said the three implementations emit the same codes. It
did not say any code is ever *exercised*, and that is a different question with
a worse answer.

The `.lint` goldens are the only cross-language check on lint behaviour — each
implementation renders `report(table, payloads)` and all three must produce the
same bytes. Across all six fixtures, two codes appear: `dead-row` and
`payload-hoist`. `dead-column`, `no-static-entry`, `no-static-exit`,
`ignore-heavy` and `unreachable-heavy` are implemented three times and tripped
zero times.

Each implementation's own unit tests cover them. Nothing compares the three,
which is precisely what the `.lint` golden exists for. The gap is not a
decision anyone made: every fixture happens to sit well under
`ignoreHeavyPercent`, and none has an `UNREACHABLE` cell at all.

- [x] A `fixtures` table in `spec/diagnostics-coverage.md`, checked. Recorded
      rather than required — a check that fails on a known gap is one people
      learn to ignore — so it catches movement instead: a fixture that stops
      tripping a lint, or a lint that gains coverage the table did not notice.
      Closing a gap is then a diff to that file.
- [x] Five fixtures, each the `payload-hoist` shape: a `.tbl`, `.grid`,
      `.lint`, `.cov`, a trace, and three adapters. Progress: dead-column,
      ignore-heavy, no-static-exit, no-static-entry and unreachable-heavy are
      done in all three. All seven lints are now compared across languages.
      - a matrix with a dead column
      - one over 70% `IGNORE`
      - one with enough `UNREACHABLE` cells to pass 25%
      - one fully static with a state nothing reaches
      - one row that cannot be left
      Four patches each, on the `payload-hoist` evidence. Worth it: these are
      the only lints in the library whose three implementations have never been
      compared to each other on a single byte.
