// Checks for `Turnstile.swift`, and for `TabularCenterTesting` around it.

import ExampleCheck
import TabularCenter
import TabularCenterTesting

#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

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

do {
    let spec = try parseSpec(Turnstile.FIXTURE, "Turnstile.FIXTURE")
    Check.eq(
        checkTable(Turnstile.TABLE, spec),
        [],
        "spec: the matrix matches the fixture a reviewer reads")

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
