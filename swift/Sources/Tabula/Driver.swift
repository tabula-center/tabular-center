/// Why a driver call could not proceed.
public enum DriverError: Error, Equatable {
    /// The mailbox is full.
    case queueFull(capacity: Int)
    /// `run` was called from inside itself.
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
public final class Driver<S, A, F> {
    /// The current state.
    public private(set) var state: S

    /// Mailbox capacity. Fixed rather than growable: an unbounded mailbox just
    /// moves the failure somewhere harder to see.
    public let capacity: Int

    private var queue: [A] = []
    private var running = false

    public init(initial: S, capacity: Int = 8) {
        self.state = initial
        self.capacity = capacity
    }

    /// Pending actions.
    public var pending: Int { queue.count }

    /// Add an action to the back of the mailbox.
    public func enqueue(_ action: A) throws {
        guard queue.count < capacity else { throw DriverError.queueFull(capacity: capacity) }
        queue.append(action)
    }

    /// Dispatch one action and drain everything it causes.
    @discardableResult
    public func dispatch(
        _ action: A,
        step: (S, A) -> Step<S, F>,
        perform: (F) -> A?
    ) throws -> Progress {
        try enqueue(action)
        return try run(step: step, perform: perform)
    }

    /// Drain the mailbox, strictly FIFO.
    ///
    /// The outcome is applied **before** effects are performed, so a handler
    /// that enqueues an action sees the post-transition state. The reverse
    /// order would make `.go(x, effects: [e])` mean "perform e while still in
    /// the old state", which is almost never what a cell author intends.
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
                // Queued, never recursed. This is the whole point.
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
