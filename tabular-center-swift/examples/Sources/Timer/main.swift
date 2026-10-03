// Checks for `Timer.swift`, in their own file and their own build product.
//
// Swift's split is by *target* rather than by module: these live alongside the
// implementation rather than importing it, because the example types are not
// `public` and making them so would be a sweep across every example for the
// benefit of the harness rather than of a reader. Each example is still its
// own target with its own dependency line, built and run on its own.

import ExampleCheck
import TabularCenter

#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

let m = Timer.Impl()

Check.eq(
    Timer.step(m, Timer.Ctx(limit: 10), .running(since: 0), .tick(now: 1)),
    .stay(effects: []),
    "timer: a tick below the limit stays")
Check.ok(
    !Timer.step(m, Timer.Ctx(limit: 10), .running(since: 0), .tick(now: 1)).isIgnored,
    "timer: a tick while running is meaningful, not ignored")
Check.eq(
    Timer.step(m, Timer.Ctx(limit: 3), .running(since: 2), .tick(now: 9)),
    .go(.done, effects: [.stopClock(reason: .elapsed)]),
    "timer: the limit finishes the timer")
Check.eq(
    Timer.step(m, Timer.Ctx(limit: 100), .running(since: 0), .cancel).effects,
    [.stopClock(reason: .cancelled)],
    "timer: cancelling stops the clock for a different reason")

let ctx = Timer.Ctx(limit: 1)
_ = Timer.perform(m, ctx, .stopClock(reason: .elapsed))
Check.eq(ctx.log, ["stop:elapsed"], "timer: effect handlers receive narrowed payloads")

let inapplicable: [(Timer.S, Timer.A)] = [
    (.idle, .tick(now: 1)), (.idle, .cancel), (.done, .cancel),
]
for (s, a) in inapplicable {
    Check.ok(
        Timer.step(m, Timer.Ctx(limit: 1), s, a).isIgnored,
        "timer: \(a) means nothing in \(s)")
}

exit(Check.report("swift timer"))
