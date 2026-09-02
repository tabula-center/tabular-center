# Contributing

## Rules that are not negotiable

1. **No runtime dependencies.** Build-time code generators (KSP, SwiftSyntax)
   are fine; anything that links into a user's binary is not. CI enforces this
   for Kotlin via a dependency-report check.
2. **Behaviour changes land in `spec/conformance` first.** The three
   implementations will drift unless something forces them not to.
3. **Every diagnostic gets a compile-fail test.** `trybuild` for Rust, KSP
   compile-testing for Kotlin, swift-macro-testing for Swift.
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
