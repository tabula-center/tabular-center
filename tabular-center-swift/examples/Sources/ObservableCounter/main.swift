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

// The machine itself is portable, so check it everywhere. A reader on Linux
// should still see that the example's machine works; only the store is gated.
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
        // ObservableStore is @MainActor -- SwiftUI observes it from the main
        // thread -- and top-level code in main.swift is not main-actor
        // isolated in Swift 5.10, so every `state`, `send` and `drain` below
        // was a cross-actor call the compiler refused. Nobody saw it: this
        // block is compiled on Darwin only, and the first Darwin job was the
        // first compiler ever to read it. `assumeIsolated` states the fact
        // rather than hiding it: top-level code runs on the main thread, and it
        // runs synchronously, so every check below still executes before exit.
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
                // The mirror is the whole reason this type exists rather than
                // being a computed forward to the driver. A SwiftUI view reads
                // `state`; if it did not move, the view would never redraw.
                Check.eq(store.state, .counting(n: 2), "observable: state mirrors the driver")

                try store.send(.bump)
                Check.eq(store.state, .full, "observable: the mirror follows the machine into Full")
                Check.eq(storeCtx.announced, [3], "observable: the effect ran on the way")
            } catch {
                Check.ok(false, "observable: store threw \(error)")
            }

            // enqueue does not drain, so the mirror must not move. A view showing
            // a state the machine has not reached is the failure this type invites.
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
    // Not a failure and not a pass. ObservableStore exists to be watched by
    // SwiftUI, and there is no SwiftUI here to watch it.
    print("skip swift observable store (Darwin only)")
#endif

exit(Check.report("swift observable counter"))
