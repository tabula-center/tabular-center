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
| 4 Kotlin core + KSP | **done**; KSP adapter now runs — `examples/kotlin/06-generated` builds green |
| 5 Swift | core, reference, compile-fail, testing, conformance, examples, **codegen**, `MachineSyntax`; macro expansion to come |
| 6 Composition | **done (all three)** |
| 7 Effects surface | **done (Rust half)** |
| 8 Introspection & tooling | **done (Rust half)** |
| 9 Runtime / drivers | **done (Rust half)** |

93 Rust tests; 41 compile-fail fixtures (10 Rust, 4 Kotlin, 1 Kotlin-codegen,
11 Kotlin-KSP, 4 Swift, 11 Swift macro-syntax); 9 conformance fixtures (77
trace steps), every one with an adapter in all three languages; 9 each of
golden `.grid`, `.mmd`, `.lint`, `.cov`.

These counts are checked against the tree, not remembered. Regenerate with:

```
grep -rho '#\[test\]' rust/ | wc -l
ls rust/tabula/tests/compile_fail/*.rs | grep -vc _prelude
ls -d kotlin/ksp/compile-fail/fixtures/*/ | wc -l
ls -d swift/macros/fixtures/*/ | wc -l
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

### 0b. Two runs are needed, both needing network — done

Both have been run: `flake.lock` pins `nixos-26.05`, and `nix/gradle-lock.json`
is committed (108 artifacts, produced by gradle 8.14.4). Kept for the record:

1. **`nix flake update`.** `flake.nix` now asks for `nixos-26.05` instead of
   `nixos-25.05`, to get a Swift whose SwiftPM ships `CompilerPluginSupport` —
   the thing that actually blocks `swift/macros`, ahead of swift-syntax being
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
`kotlin/{core,annotations,testing,codegen,test,conformance,compile_fail,ksp}`.
So `has.kotlin` was always false, `nix/checks.nix` dropped all six Kotlin
checks, and `ci.yml`'s `check` job — which runs `nix flake check` and nothing
else — ran none of them. Kotlin was covered only by `check-no-nix`.

The gate now names `kotlin/core/dev/tabula/Step.kt`, which is the file every
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
     matrix it guards was in `kotlin/test/ReferenceTimer.kt`, outside the
     `[*.tb.kt]` exemption in `.editorconfig`. Moved to
     `kotlin/test/TimerSpec.tb.kt`; see `spec/matrix-files.md`, which had
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
- [x] `kotlin/ksp/settings.gradle.kts`. Its absence was recorded as "harmless
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
`kotlin/ksp` has never executed and two bugs in its build file were found by
reading alone.

### 0. docs/ is no longer committed

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

### 4. The KSP adapter has never run — superseded

It runs now: see 0d, and 0f below. The rest of this entry is the history of
getting there.

`kotlin/ksp/` was the only code in the repository that had never executed —
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
- [ ] Stale, kept for the record: the reason recorded here was **not** the
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
- [x] The output held to a golden, `kotlin/ksp/golden/TurnstileGenerated.kt`.
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
Re-read against `kotlin/ksp/src/main/kotlin/dev/tabula/ksp/TabulaProcessor.kt`
and `kotlin/ksp/golden/`, not guessed (0f asked for exactly this pass):

- [x] ~~Resolve sealed hierarchies to ordered variant lists~~ — **superseded.**
      Order is declared, not discovered: `@Machine(states = [...], actions =
      [...], effects = [...])` and the processor reads those lists. Row
      identity is position, so an order a refactor of the sealed hierarchy
      could silently change is the wrong source for it.
- [x] Read the `handle` prototype: `suspend` and annotations, copied verbatim
      (`prototypeModifiers`).
- [ ] Read the rest of the prototype: context parameters, extension receiver,
      visibility. `prototypeModifiers` reads none of the three today, so a
      `context(clock: Clock)` prototype generates uncolored cells — ARCHITECTURE
      5's headline Kotlin example is the one the processor cannot yet produce.
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
- [ ] Diagnostic *positions*. `logger.error(e.message, decl)` points at the
      annotated interface, not at the `@Row` or the `CellSpec` at fault.
      ARCHITECTURE 3 shows `row-arity` pointing at the row's line. Same
      trade-off Phase 5 accepts for Swift (row-level in v1); here it is
      declaration-level, one step coarser.
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

## `TabulaMacros` — decided: a separate package

The Swift generator's logic is done and testable (`Sources/TabulaCodegen`, 13
diagnostics plus a golden diff). What was left was the macro that parses syntax
into a `RawMachine`, and one packaging decision that had to come first.

**Chosen: option 2.** `swift/macros/` is its own SwiftPM package, built in the
dev shell and reported as `skip` by `nix flake check` rather than passing
silently.

The argument that settles it is sharper than "swift-syntax is remote". A
macro's *declaration* must live wherever users import it from, and
`#externalMacro` names the implementation module — so declaring `@Machine` in
`Tabula` makes `Tabula` depend on the macro target and therefore on
swift-syntax. **There is no arrangement where the macro lives in the main
package and the main package stays offline-buildable.** The declaration
therefore lives in `swift/macros` too, and a user who wants the macro takes a
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
- [x] `swift/macros/SURFACE.md`: the declaration surface and its field-by-field
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
- [ ] The hand-written examples in all three languages still keep their matrix
      and their handlers in one file.
- [x] `spec/tabula-fmt.md`: the contract. Written first for the reason
      `SURFACE.md` was — a formatter's contract is almost all of its risk, and
      it is the part reviewable by reading.
- [ ] `tabula-fmt` itself, at the repository root in `tabula-fmt/`. One tool
      for all three languages: the matrices differ in punctuation and agree in
      structure, and a tool that parses neither Rust nor Kotlin is correct for
      both. Root rather than inside `rust/` because a home in one language's
      directory would imply an ownership that is not true — it belongs to the
      `.tb.` format, which is language-agnostic.

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
cd swift/macros && swift build
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

- [x] Export `TabulaCodegen` as a product of `swift/Package.swift`. With the
      manifest compiling, resolution got far enough to find the next blocker,
      which had been sitting behind it since `swift/macros` was written:

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
      rejection fixtures in `swift/macros/fixtures/`.
- [ ] Restore `pending/Machine.swift` and the `.macro` target on a SwiftPM
      that ships `CompilerPluginSupport`. Only `Package.swift` changes.
      `nix/swiftpm-plugin-support.nix` now builds the module; what remains, per
      the note at the top of `swift/macros/Package.swift`, is that
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
`kotlin/README.md`. The bump from `nixos-25.05` to `nixos-26.05` -- made for
Swift -- therefore changed the Kotlin compiler too, silently, and the four
`kotlin/compile_fail/` fixtures plus `codegen/compile_fail/` match kotlinc's
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
its JUnit `test` task found nothing to discover and passed. `kotlin/ksp/README.md`
said "the behavioural checks passing against it". They had never executed --
including `GateTest`, the only check on the suspend machine driven by
`SuspendDriver`.

- [x] One `JavaExec` per check, hung off `check`, so `gradle build` runs them.
      The JUnit task is disabled: nothing to discover, and from Gradle 9 an
      empty discovery is a failure rather than a pass.
- [x] `GateImpl.chime`'s doc described a follow-up the code does not return.

**Docs that had fallen behind the tree**, corrected in the same patch:
`ARCHITECTURE` 12/13 and `kotlin/README.md` still said KSP had never run and
that 06-generated is skipped under nix; `kotlin/ksp/build.gradle.kts` was
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
- [ ] `no-static-entry` and `unreachable-heavy` still have no fixture.
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

- [ ] Read `hadilq/happy`'s processor, `happy-processor-common`, for what the
      generated DSL actually looks like once nested cases are involved — the
      naming scheme there (`SituationOneOptionTwo`) is the part that got
      thought about, and matrix cells have the same flattening problem.
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
- [ ] The narrowed calling surface, `elvis`-shaped, with the two-outcome
      `elseIf` special case allowed and everything else refused.
- [x] Defaults derived from the spine: a `HANDLE` named by a hop becomes a
      `GO` (`derive` in `codegen/Raw.kt` and `TabulaCodegen/Raw.swift`), shown
      by `examples/kotlin/06-generated/src/Spine.tb.kt` and pinned by
      `ksp/golden/SpineGenerated.kt.golden`.
- [ ] Rust: `@Path` as a `transition_matrix!` arm.

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

- [ ] Happy-path sugar, per the backlog above. These apps are its acceptance
      test and should not be written before it.
- [ ] `Cargo.lock`-driven vendoring for `examples/rust`, so a crates.io
      dependency can exist at all. Independent of the apps and worth landing
      on its own — it is the third instance of a pattern already proven twice.
- [ ] iced app 1: one machine, the `update`-becomes-`step` substitution, with
      the hand-written version in the README beside it for contrast.
- [ ] iced app 2: composition and payloads. `nested-delegate` and `retry`
      already model this as fixtures; the app should be recognisably the same
      machines so a reader can move between them.
- [ ] Compose app 1 and 2, mirroring those, over a `Driver` and a `StateFlow`.
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

- [x] `rust-matrix-stable`, scanning `rust/` and `examples/rust/`. Separate
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
- [ ] `swift-matrix-stable`, against `swift-format`. Blocked on the same
      question `swift-syntax` was: the formatter is a remote SwiftPM package
      and the sandbox is offline. `tools/swift-lock` already solves that shape,
      so this is adding a dependency to `swift/macros` and a step, not new
      machinery. Until it lands,
      `examples/swift-examples/Sources/SpecCheck/Turnstile.tb.swift` has no
      formatter guarding it — and no formatter running over it either, so
      nothing has broken it. That is luck, not a design.
- [ ] A check that every `.tb.` file in the tree is covered by one of the
      three. The scans are per-language and a fourth language, or a matrix in
      an unexpected directory, would be outside all of them without saying so.

## swift-matrix-stable — the cost, and what stands in until it is paid

The Kotlin and Rust matrix checks have no Swift counterpart, and the asymmetry
is not an oversight. It is worth writing down before someone "completes the
set" without pricing it.

**What the other two guard is a formatter that runs.** `cargo fmt --check` is
in `rust-fmt`; ktlint is on the path and a contributor may reach for it.
`swift-format` is not used anywhere in this repository, so a
`swift-matrix-stable` would guard a formatter nobody invokes.

**What it costs.** A second remote SwiftPM dependency in `swift/macros`, which
means `nix run .#swift-lock` again and swift-format's own tree — swift-syntax,
swift-argument-parser and more — entering every `swift-macros` build.

**And a version trap.** swift-format's releases track swift-syntax's:
swift-format 510 requires swift-syntax 510, and `swift/macros` pins
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
- [ ] `swift-matrix-stable` proper, at swift-format 509.0.0, when a formatter
      is actually adopted — or sooner, if the cost above is judged worth
      paying. Not a five-line change, and not urgent while nothing formats
      Swift here.

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
- [ ] Decide `tabula::color-mismatch`. Prototype modifiers are copied rather
      than enumerated, so a mismatch is a type error before any check runs,
      which suggests it is unimplementable by design and the spec should say
      so. Until someone answers, a documented diagnostic no implementation
      emits is a promise to a reader that nothing keeps.

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
- [ ] Five fixtures, each the `payload-hoist` shape: a `.tbl`, `.grid`,
      `.lint`, `.cov`, a trace, and three adapters. Progress: dead-column,
      ignore-heavy and no-static-exit are done in all three; no-static-entry
      and unreachable-heavy have nothing yet.
      - a matrix with a dead column
      - one over 70% `IGNORE`
      - one with enough `UNREACHABLE` cells to pass 25%
      - one fully static with a state nothing reaches
      - one row that cannot be left
      Four patches each, on the `payload-hoist` evidence. Worth it: these are
      the only lints in the library whose three implementations have never been
      compared to each other on a single byte.
