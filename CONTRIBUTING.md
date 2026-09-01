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

## Order of work

See `PLAN.md`. Phases are ordered by risk retirement, not convenience. M2
(Kotlin required-member enforcement) is a stop-or-go gate, not a checkpoint.
