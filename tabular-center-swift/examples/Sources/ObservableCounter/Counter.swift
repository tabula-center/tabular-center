import Tabula

/// **6. The observable store, and the only example that can be skipped.**
///
/// The machine is deliberately the smallest one in the set — a counter with a
/// ceiling. It is not what this example is about. What it is about is
/// `ObservableStore`, which is the only part of the library that does not
/// exist everywhere: it needs SwiftUI to be worth having, and SwiftUI is
/// Darwin only.
///
/// So this is the first example that **skips rather than fails** off Darwin.
/// That distinction matters more than the machine does: a check that quietly
/// passes where a feature is absent says the feature works, and a check that
/// fails there says the build is broken. Neither is true. Saying `skip` out
/// loud is the only honest third option, and it is the same call
/// `tools/verify` makes for a missing toolchain.
enum Counter {
    enum S: Equatable {
        case counting(n: Int)
        case full
    }

    enum A: Equatable {
        case bump
        case reset
    }

    enum F: Equatable {
        /// Emitted on the transition into `full`, so there is something for an
        /// effect handler to see.
        case announce(n: Int)
    }

    final class Ctx {
        let ceiling: Int
        var announced: [Int] = []
        init(ceiling: Int) { self.ceiling = ceiling }
    }

    protocol Cells {
        func countingBump(_ ctx: Ctx, _ n: Int) -> Step<S, F>
    }

    static func step(_ c: Cells, _ ctx: Ctx, _ s: S, _ a: A) -> Step<S, F> {
        switch (s, a) {
        case let (.counting(n), .bump): return c.countingBump(ctx, n)
        case (.counting, .reset): return .go(.counting(n: 0), effects: [])
        case (.full, .bump): return .ignored
        case (.full, .reset): return .go(.counting(n: 0), effects: [])
        }
    }

    static func perform(_ ctx: Ctx, _ f: F) -> A? {
        switch f {
        case let .announce(n):
            ctx.announced.append(n)
            return nil
        }
    }

    struct Impl: Cells {
        func countingBump(_ ctx: Ctx, _ n: Int) -> Step<S, F> {
            let next = n + 1
            if next >= ctx.ceiling {
                return .go(.full, effects: [.announce(n: next)])
            }
            return .go(.counting(n: next), effects: [])
        }
    }
}
