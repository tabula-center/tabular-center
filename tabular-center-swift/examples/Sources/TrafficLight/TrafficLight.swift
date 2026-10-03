import TabularCenter

/// **1. The minimum.**
///
/// Three states, two actions, no payloads, no effects. Six cells, one of which
/// the developer writes.
///
/// `Never` is Swift's uninhabited type, so `Step<S, Never>` is a machine that
/// cannot emit — the counterpart of Rust's `effects Effect { }`.
enum TrafficLight {
    enum S: Equatable { case red, green, amber }
    enum A: Equatable { case advance, fault }

    final class Ctx {
        var cycles = 0
    }

    protocol Cells {
        func amberAdvance(_ ctx: Ctx) -> Step<S, Never>
    }

    static func step(_ c: Cells, _ ctx: Ctx, _ s: S, _ a: A) -> Step<S, Never> {
        switch (s, a) {
        case (.red, .advance): return .go(.green, effects: [])
        case (.red, .fault): return .go(.red, effects: [])
        case (.green, .advance): return .go(.amber, effects: [])
        case (.green, .fault): return .go(.red, effects: [])
        case (.amber, .advance): return c.amberAdvance(ctx)
        case (.amber, .fault): return .go(.red, effects: [])
        }
    }

    struct Controller: Cells {
        func amberAdvance(_ ctx: Ctx) -> Step<S, Never> {
            ctx.cycles += 1
            return .go(.red, effects: [])
        }
    }
}
