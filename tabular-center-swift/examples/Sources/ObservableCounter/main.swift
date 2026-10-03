// Checks for `Counter.swift`, and for `ObservableStore` around it.
//
// The only example in the set that can report `skip`. Everything else here
// either passes or fails; this one has a third outcome, because the type it
// demonstrates is absent on platforms the rest of the library supports fully.

import ExampleCheck
import TabularCenter

#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

let ctx = Counter.Ctx(ceiling: 3)
let cells = Counter.Impl()
Check.eq(
    Counter.step(cells, ctx, .counting(n: 0), .bump),
    .go(.counting(n: 1), effects: []),
    "counter: a bump below the ceiling keeps counting")
Check.eq(
    Counter.step(cells, ctx, .counting(n: 2), .bump),
    .go(.full, effects: [.announce(n: 3)]),
    "counter: reaching the ceiling announces and fills")
Check.eq(
    Counter.step(cells, ctx, .full, .bump),
    .ignored,
    "counter: bumping a full counter is not applicable, not a no-op")
Check.eq(Counter.TABLE.coverage().requiredMembers, 1, "counter: one implementation")

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
    if #available(macOS 14, iOS 17, tvOS 17, watchOS 10, *) {
        MainActor.assumeIsolated {
            let storeCtx = Counter.Ctx(ceiling: 3)
            let store = ObservableStore<Counter.S, Counter.A, Counter.F>(
                initial: .counting(n: 0),
                step: { s, a in Counter.step(Counter.Impl(), storeCtx, s, a) },
                perform: { f in Counter.perform(storeCtx, f) }
            )

            Check.eq(store.state, .counting(n: 0), "observable: starts where it was told")

            do {
                try store.send(.bump)
                try store.send(.bump)
                Check.eq(store.state, .counting(n: 2), "observable: state mirrors the driver")

                try store.send(.bump)
                Check.eq(store.state, .full, "observable: the mirror follows the machine into Full")
                Check.eq(storeCtx.announced, [3], "observable: the effect ran on the way")
            } catch {
                Check.ok(false, "observable: store threw \(error)")
            }

            do {
                let pending = ObservableStore<Counter.S, Counter.A, Counter.F>(
                    initial: .counting(n: 0),
                    step: { s, a in Counter.step(Counter.Impl(), Counter.Ctx(ceiling: 9), s, a) },
                    perform: { _ in nil }
                )
                try pending.enqueue(.bump)
                Check.eq(pending.state, .counting(n: 0), "observable: enqueue leaves the mirror alone")
                try pending.drain()
                Check.eq(pending.state, .counting(n: 1), "observable: drain moves it")
            } catch {
                Check.ok(false, "observable: store threw \(error)")
            }
        }
    } else {
        print("skip swift observable store (needs macOS 14 / iOS 17)")
    }
#else
    print("skip swift observable store (Darwin only)")
#endif

exit(Check.report("swift observable counter"))
