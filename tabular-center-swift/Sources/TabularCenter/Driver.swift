/// Why a driver call could not proceed.
///
/// - `queueFull`: The mailbox is full.
/// - `reentered`: `run` was called from inside itself.
public enum DriverError: Error, Equatable {
    case queueFull(capacity: Int)
    case reentered
}

/// What one drain accomplished.
public struct Progress: Equatable {
    public var steps = 0
    public var effects = 0
    public var followUps = 0
    public var transitions = 0
    public var ignored = 0
    public init() {}
}

/// Owns a machine's current state and its pending actions.
///
/// `step` is never re-entered, and follow-up actions are **queued, never
/// recursed**: a handler returns an action as data and is handed no way back
/// into `step`.
///
/// The closures capture rather than taking a shared environment, unlike Rust's
/// driver. That is not an oversight — Rust needs the parameter because two
/// closures cannot each capture the same `&mut`, and Swift has no such rule.
/// Where the languages differ, follow the language.
///
/// - `state`: The current state.
/// - `capacity`: Mailbox capacity.
/// - `pending`: Pending actions.
/// - `enqueue`: Add an action to the back of the mailbox.
/// - `dispatch`: Dispatch one action and drain everything it causes.
/// - `run`: Drain the mailbox, strictly FIFO.
public final class Driver<S, A, F> {
    public private(set) var state: S

    public let capacity: Int

    private var queue: [A] = []
    private var running = false

    public init(initial: S, capacity: Int = 8) {
        self.state = initial
        self.capacity = capacity
    }

    public var pending: Int { queue.count }

    public func enqueue(_ action: A) throws {
        guard queue.count < capacity else { throw DriverError.queueFull(capacity: capacity) }
        queue.append(action)
    }

    @discardableResult
    public func dispatch(
        _ action: A,
        step: (S, A) -> Step<S, F>,
        perform: (F) -> A?
    ) throws -> Progress {
        try enqueue(action)
        return try run(step: step, perform: perform)
    }

    @discardableResult
    public func run(
        step: (S, A) -> Step<S, F>,
        perform: (F) -> A?
    ) throws -> Progress {
        guard !running else { throw DriverError.reentered }
        running = true
        defer { running = false }

        var p = Progress()
        while !queue.isEmpty {
            let action = queue.removeFirst()
            let outcome = step(state, action)
            p.steps += 1

            switch outcome {
            case let .go(next, _):
                state = next
                p.transitions += 1
            case .stay:
                break
            case .ignored:
                p.ignored += 1
            }

            for effect in outcome.effects {
                p.effects += 1
                guard let followUp = perform(effect) else { continue }
                try enqueue(followUp)
                p.followUps += 1
            }
        }
        return p
    }
}

/// The asynchronous driver.
///
/// The same loop, a different color. Swift has no `reasync`, so an `async`
/// caller needs its own type rather than a generic parameter — the same
/// one-file-per-color shape Kotlin's `SuspendDriver` takes, for the same
/// reason.
public final class AsyncDriver<S, A, F> {
    public private(set) var state: S
    public let capacity: Int

    private var queue: [A] = []
    private var running = false

    public init(initial: S, capacity: Int = 8) {
        self.state = initial
        self.capacity = capacity
    }

    public var pending: Int { queue.count }

    public func enqueue(_ action: A) throws {
        guard queue.count < capacity else { throw DriverError.queueFull(capacity: capacity) }
        queue.append(action)
    }

    @discardableResult
    public func dispatch(
        _ action: A,
        step: (S, A) async -> Step<S, F>,
        perform: (F) async -> A?
    ) async throws -> Progress {
        try enqueue(action)
        return try await run(step: step, perform: perform)
    }

    @discardableResult
    public func run(
        step: (S, A) async -> Step<S, F>,
        perform: (F) async -> A?
    ) async throws -> Progress {
        guard !running else { throw DriverError.reentered }
        running = true
        defer { running = false }

        var p = Progress()
        while !queue.isEmpty {
            let action = queue.removeFirst()
            let outcome = await step(state, action)
            p.steps += 1

            switch outcome {
            case let .go(next, _):
                state = next
                p.transitions += 1
            case .stay:
                break
            case .ignored:
                p.ignored += 1
            }

            for effect in outcome.effects {
                p.effects += 1
                guard let followUp = await perform(effect) else { continue }
                try enqueue(followUp)
                p.followUps += 1
            }
        }
        return p
    }
}
