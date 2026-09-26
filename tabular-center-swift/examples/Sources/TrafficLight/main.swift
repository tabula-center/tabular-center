// Checks for `TrafficLight.swift`, in their own file and their own build product.
//
// Swift's split is by *target* rather than by module: these live alongside the
// implementation rather than importing it, because the example types are not
// `public` and making them so would be a sweep across every example for the
// benefit of the harness rather than of a reader. Each example is still its
// own target with its own dependency line, built and run on its own.

import ExampleCheck
import Tabula

#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

let ctx = TrafficLight.Ctx()
let c = TrafficLight.Controller()
var s = TrafficLight.S.red
for _ in 0..<6 {
    s = TrafficLight.step(c, ctx, s, .advance).target ?? s
}
Check.eq(s, .red, "traffic light: two full cycles return to red")
Check.eq(ctx.cycles, 2, "traffic light: context counted both cycles")

for from in [TrafficLight.S.red, .green, .amber] {
    Check.eq(
        TrafficLight.step(c, TrafficLight.Ctx(), from, .fault).target, .red,
        "traffic light: fault from \(from) goes red")
}

let cov = TrafficLight.TABLE.coverage()
Check.eq(cov.total, 6, "traffic light: six cells")
Check.eq(cov.requiredMembers, 1, "traffic light: one implementation")

exit(Check.report("swift traffic light"))
