// Checks for `Turnstile.swift`, and for `TabulaTesting` around it.

import ExampleCheck
import Tabula
import TabulaTesting

#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

// The machine works, first. An example whose only content is its own test
// harness teaches nothing.
let ctx = Turnstile.Ctx()
let cells = Turnstile.Impl()
Check.eq(
    Turnstile.step(cells, ctx, .locked, .coin),
    .go(.unlocked, effects: []),
    "turnstile: a coin unlocks")
Check.eq(
    Turnstile.step(cells, ctx, .locked, .push),
    .ignored,
    "turnstile: pushing a locked turnstile is not applicable")
Check.eq(
    Turnstile.step(cells, ctx, .unlocked, .push),
    .go(.locked, effects: []),
    "turnstile: pushing through relocks")
Check.eq(ctx.admitted, 1, "turnstile: the handler counted the admission")

// Now the point of the example: the generated table agrees with the fixture a
// reviewer reads. `checkTable` returns the differences, so no differences is
// an empty array rather than a boolean.
do {
    let spec = try parseSpec(Turnstile.FIXTURE, "Turnstile.FIXTURE")
    Check.eq(
        checkTable(Turnstile.TABLE, spec),
        [],
        "spec: the matrix matches the fixture a reviewer reads")

    // And it notices when they disagree. One cell changed from HANDLE to
    // GO(Locked) -- a difference that compiles, passes every behavioural test
    // that does not exercise that cell, and is exactly what a table diff is
    // for.
    let drifted = try parseSpec(Turnstile.DRIFTED, "Turnstile.DRIFTED")
    let differences = checkTable(Turnstile.TABLE, drifted)
    Check.ok(!differences.isEmpty, "spec: a changed cell is reported, not shrugged at")
    Check.ok(
        differences.count == 1,
        "spec: one changed cell is one difference, not a cascade")
} catch {
    Check.ok(false, "spec: the fixture failed to parse: \(error)")
}

exit(Check.report("swift spec-check"))
