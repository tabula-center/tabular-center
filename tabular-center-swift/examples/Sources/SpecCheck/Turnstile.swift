import TabularCenter

/// **7. Pinning a matrix to a text file.**
///
/// The other examples check what a machine *does*. This one checks what a
/// machine *is*, against a fixture a reviewer can read — which is the argument
/// the whole library rests on. A pull request that changes behaviour should
/// show the table diff, not only the code diff, because reviewing a matrix is
/// the thing this design is for and reviewing a `switch` is the thing it
/// exists to avoid.
///
/// It is also the only example that uses the `TabularCenterTesting` product. That
/// module ships in `Package.swift` and, until this existed, nothing outside
/// the library had ever imported it — the same shipped-surface-with-no-consumer
/// condition that left Rust's `PAYLOADS` unbuildable without `alloc` for as
/// long as it existed.
enum Turnstile {
    enum S: Equatable { case locked, unlocked }
    enum A: Equatable { case coin, push }

    final class Ctx {
        var admitted = 0
    }

    protocol Cells {
        func unlockedPush(_ ctx: Ctx) -> Step<S, Never>
    }

    static func step(_ c: Cells, _ ctx: Ctx, _ s: S, _ a: A) -> Step<S, Never> {
        switch (s, a) {
        case (.locked, .coin): return .go(.unlocked, effects: [])
        case (.locked, .push): return .ignored
        case (.unlocked, .coin): return .ignored
        case (.unlocked, .push): return c.unlockedPush(ctx)
        }
    }

    struct Impl: Cells {
        func unlockedPush(_ ctx: Ctx) -> Step<S, Never> {
            ctx.admitted += 1
            return .go(.locked, effects: [])
        }
    }

    static let FIXTURE = """
        machine Turnstile
        initial Locked
        states  Locked Unlocked
        actions Coin Push

        Locked   | GO(Unlocked) | IGNORE
        Unlocked | IGNORE       | HANDLE
        """

    static let DRIFTED = """
        machine Turnstile
        initial Locked
        states  Locked Unlocked
        actions Coin Push

        Locked   | GO(Unlocked) | IGNORE
        Unlocked | IGNORE       | GO(Locked)
        """
}
