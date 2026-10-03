// What developers declare for the machines the codegen check emits.
//
// Every type a machine names lives in the machine's enum, as ARCHITECTURE
// 11.3 writes it (`enum Timer { enum S ...; enum A ... }`), and the emitter
// qualifies every reference: `Timer.S`, `Timer.Running`, `Retry.step`. That
// namespacing is what lets all of these compile in ONE module, which
// `tools/verify swift-codegen` does on purpose -- two machines that could not
// share a module would be a generator bug, and one this file would hide if
// every machine were compiled alone.
//
// The colored twins reuse their plain twin's types through typealiases. What
// differs between them is the generated surface, not the data.

// MARK: - Timer

enum Timer {
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
        case note(text: String)
        case halt(reason: Reason)
    }

    enum Reason: Equatable { case cancelled }

    final class Ctx {}

    // Narrowed variants: the dispatcher binds each payload and builds these,
    // so a cell receives `Running`, never `S`.
    struct Running: Equatable { let since: Int }
    struct Tick: Equatable { let now: Int }
}

enum TimerAsync {
    typealias S = Timer.S
    typealias A = Timer.A
    typealias F = Timer.F
    typealias Ctx = Timer.Ctx
    typealias Running = Timer.Running
    typealias Tick = Timer.Tick
}

/// The Timer again, with a rendering surface (ARCHITECTURE 9): its cells
/// `async throws` like `TimerAsync`'s, its renderers plain -- two prototypes,
/// two colors. The types are the Timer's; the rendering surface adds members,
/// not types.
enum TimerRender {
    typealias S = Timer.S
    typealias A = Timer.A
    typealias F = Timer.F
    typealias Ctx = Timer.Ctx
    typealias Running = Timer.Running
    typealias Tick = Timer.Tick
}

enum Connect {
    enum S: Equatable {
        case idle
        case connecting
        case live
        case failed
    }

    enum A: Equatable {
        case start
        case ready
        case drop
    }

    enum F: Equatable {
        case banner
    }

    final class Ctx {}
}

protocol Viewish {}

struct ViewishLabel: Viewish { let text: String }

enum ViewishEither<First: Viewish, Second: Viewish>: Viewish {
    case first(First)
    case second(Second)
}

@resultBuilder
enum ViewishBuilder {
    static func buildBlock<Content: Viewish>(_ content: Content) -> Content { content }
    static func buildEither<First: Viewish, Second: Viewish>(first content: First) -> ViewishEither<First, Second> {
        .first(content)
    }
    static func buildEither<First: Viewish, Second: Viewish>(second content: Second) -> ViewishEither<First, Second> {
        .second(content)
    }
}

/// The Timer with a builder-mode rendering surface: SwiftUI's shape, with the
/// stand-in above in SwiftUI's place.
enum TimerView {
    typealias S = Timer.S
    typealias A = Timer.A
    typealias F = Timer.F
    typealias Ctx = Timer.Ctx
    typealias Running = Timer.Running
    typealias Tick = Timer.Tick
}

enum Retry {
    enum S: Equatable { case ready, waiting(attempt: Int), exhausted }
    enum A: Equatable { case attempt, elapsed, abort }
    enum F: Equatable { case sleep, giveUp }

    final class Ctx {
        let maxAttempts: Int
        init(maxAttempts: Int) { self.maxAttempts = maxAttempts }
    }

    struct Waiting: Equatable { let attempt: Int }
}

enum RetryAsync {
    typealias S = Retry.S
    typealias A = Retry.A
    typealias F = Retry.F
    typealias Ctx = Retry.Ctx
    typealias Waiting = Retry.Waiting
}

enum Job {
    enum S: Equatable { case idle, retrying(child: Retry.S), done }
    enum A: Equatable { case run, tick, cancel }
    enum F: Equatable { case log }

    /// Contains the child's context, so `retryChildCtx` is a field access.
    final class Ctx {
        let retry: Retry.Ctx
        init(retry: Retry.Ctx) { self.retry = retry }
    }

    struct Retrying: Equatable { let child: Retry.S }
}

enum JobAsync {
    typealias S = Job.S
    typealias A = Job.A
    typealias F = Job.F
    typealias Ctx = Job.Ctx
    typealias Retrying = Job.Retrying
}

/// Only ever compiled by `compile_fail/job-mixed_*.swift`, and refused.
enum JobMixed {
    typealias S = Job.S
    typealias A = Job.A
    typealias F = Job.F
    typealias Ctx = Job.Ctx
    typealias Retrying = Job.Retrying
}
