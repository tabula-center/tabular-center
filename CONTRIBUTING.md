# Contributing

## Rules that are not negotiable

1. **No runtime dependencies.** Build-time code generators (KSP, SwiftSyntax)
   are fine; anything that links into a user's binary is not. For Kotlin this
   is currently enforced *by construction* rather than by a check: there is no
   build system, so there is no classpath but the stdlib. The dependency-report
   check is written but gated on `has.kotlinGradle` and dormant until Gradle
   can resolve.
2. **Behaviour changes land in `spec/conformance` first.** The three
   implementations will drift unless something forces them not to.
3. **Every diagnostic gets a compile-fail fixture**, under
   `rust/tabula/tests/compile_fail/`, `kotlin/compile_fail/`,
   `kotlin/codegen/compile_fail/` or `swift/compile_fail/`. Driven by
   `tools/verify` reading a `//~ EXPECT:` line — **not** by `trybuild`, KSP
   compile-testing, or swift-macro-testing. Each of those would have been the
   project's only dependency in its language, to do what a few lines of bash
   already do. A fixture passes only if the compiler *refused* it and the
   refusal contains the expected text; both halves matter.
4. **Diagnostics are normative.** Message text lives in `spec/diagnostics.md`
   and should be recognizably the same in all three languages.
5. **All implementations green before merge to `main`.**

## One definition of green

`tools/verify` is it. `nix flake check` runs each of its steps in a sandbox and
CI runs the flake, so all three paths execute the same commands.

```sh
./tools/verify              # everything
./tools/verify clippy       # one step
nix flake check             # sandboxed, exactly as CI runs it
```

This is not tidiness. Three lints reached CI because the workflow, the flake,
and the local loop each checked slightly different things — most recently an
unused import in a *test* file, which `cargo build` never compiles and which
therefore passed a local build and failed clippy in CI. Any new check goes in
`tools/verify`, never directly in the workflow.

`--all-targets` is load-bearing for the same reason. If you are adding a lint
pass, make sure it covers tests, benches, and examples.

**`tools/verify clippy` degrades when clippy is absent**, and says so. The
fallback runs rustc's lints over the same targets, which catches unused imports
and dead code but no clippy-only lint — `module_inception` reached CI exactly
this way. If you are working without clippy, `nix flake check` is the
authority.

**There are two cargo workspaces.** `rust/` and `examples/rust/`, the second
deliberately outside the first so the examples depend on tabula the way a user
would. Every Rust step must run in both. It has now cost us three times —
clippy missed five warnings, `cargo fmt --check` passed a file with trailing
whitespace, and a version bump staled a lockfile nothing refreshed. A step that
runs in one workspace and reports green for both is worse than no step.

## Building without Nix

Nix is the convenient path, not the required one. `tools/verify` is plain bash
and the single definition of green; `nix flake check` runs it in a sandbox and
CI runs the flake, so all three paths execute the same commands. Nothing needs
Nix to work.

With `cargo`, `kotlinc` and `swift` on `$PATH`, `./tools/verify` runs
everything available and reports `skip` for what is not. That is checked rather
than asserted: `ci.yml` has a `check-no-nix` job on Linux and macOS using
toolchains installed the ordinary way. An untested claim about how to build a
project is worse than no claim, because someone believes it.

The non-Nix path also covers something Nix cannot. The sandbox has no network,
so Gradle and the KSP processor are skipped in every Nix job; with Maven
reachable, `examples/kotlin/06-generated` is the only consumer of the processor
and that job is where it runs at all.

## Reviewing: ask what is uncompared

Five defects have been found in this repository by the same question, so it is
worth writing down as a review habit.

None of them was a wrong algorithm. Each was something that existed in one
place with nothing to check it against: behaviour no fixture exercised, diagram
output no golden compared, a coverage report only one language produced, a
driver loop hand-copied into a second color and run by nothing, a grid renderer
hand-copied into a binary where no test can reach it. In every case all three
implementations *looked* green, because nothing was asking.

So when reviewing a change, the useful question is not "is this checked?" but
**"what would notice if this drifted?"** Concretely:

- Adding a renderer, a report, or any other output? It needs a golden, or it
  needs to share a code path with something that has one.
- Copying a loop or a function into a second language, or a second color of the
  same language? Something must assert the two agree, or they will not.
- Writing a helper inside a `bin/`? Nothing can test it there. Put it in the
  library.
- Adding a rule with a threshold? Import the constant. A copy of a rule is a
  rule that will drift, and it did.

`PLAN.md` has the full list under *Findings from the audit pass*.

## Applying patches

Use `git am`, not `git apply`.

`nix flake check` builds from the git tree, and on a **dirty** tree nix includes
tracked files that were modified but **excludes untracked files**. A patch
applied with `git apply` therefore shows up half-there: the modified scripts are
present and every newly added directory is not, producing errors like

```
cd: examples/swift: No such file or directory
```

from inside a nix build, while the directory sits plainly in the working tree.
`tools/verify` recognises that shape now and says so, but committing the change
avoids it entirely.

## After a version change

`VERSION` is the single source of truth; `rust/Cargo.toml` and **both**
`Cargo.lock` files are derived from it. `examples/rust/Cargo.lock` records
tabula's version too, because the examples depend on it by path — which is easy
to forget, and produces a failure that looks like a problem with the examples:

```
error: the lock file examples/rust/Cargo.lock needs to be updated
       but --locked was passed to prevent this
```

`./tools/verify version` runs first and diagnoses this before the confusing
errors appear. `nix run .#release` handles it automatically and restores the
tree if anything fails.

## Order of work

See `PLAN.md`. Phases are ordered by risk retirement, not convenience. M2
(Kotlin required-member enforcement) is a stop-or-go gate, not a checkpoint.
