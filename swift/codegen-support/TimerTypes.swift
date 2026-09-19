// What a developer declares for the timer machine the codegen check emits.
//
// The same shape as the top of Sources/TabulaCheck/ReferenceTimer.swift: the
// sum types, and one narrowed struct per payload-carrying state and action.
// The generated dispatcher binds each payload and builds these, so a cell
// receives `Running`, never `S`.

enum S: Equatable {
    case idle
    case running(since: Int)
    case done
}

enum A: Equatable {
    case start
    case tick(now: Int)
    case cancel
}

enum F: Equatable {
    case startClock
    case stopClock
    /// Named by no static cell, so it exists to exercise the payload-carrying
    /// handler: `note(_ ctx: Ctx, _ effect: String)`.
    case note(text: String)
}

final class Ctx {}

struct Running: Equatable { let since: Int }
struct Tick: Equatable { let now: Int }
