/// A machine, its state, and its mailbox, as one object.
///
/// `Driver` takes `step` and `perform` on every call, which is right for a
/// driver: the loop is generic over machines and owns none of them. It is
/// wrong for a caller, who has exactly one machine and would otherwise pass
/// the same two closures at every call site and get to choose, at each one,
/// whether to pass the right ones.
///
/// `Store` binds them once at construction. That is the whole difference, and
/// it is the difference between a library type and an application type.
public final class Store<S, A, F> {
    private let driver: Driver<S, A, F>
    private let stepFn: (S, A) -> Step<S, F>
    private let performFn: (F) -> A?

    /// - Parameters:
    ///   - perform: runs one effect and may return a follow-up action. The
    ///     follow-up is **queued, never recursed** — see `Driver.run`.
    public init(
        initial: S,
        capacity: Int = 8,
        step: @escaping (S, A) -> Step<S, F>,
        perform: @escaping (F) -> A?
    ) {
        self.driver = Driver(initial: initial, capacity: capacity)
        self.stepFn = step
        self.performFn = perform
    }

    /// The current state.
    public var state: S { driver.state }

    /// Pending actions.
    public var pending: Int { driver.pending }

    /// Mailbox capacity.
    public var capacity: Int { driver.capacity }

    /// Dispatch one action and drain everything it causes.
    @discardableResult
    public func send(_ action: A) throws -> Progress {
        try driver.dispatch(action, step: stepFn, perform: performFn)
    }

    /// Add an action to the back of the mailbox without draining.
    ///
    /// For enqueuing several actions and then draining once, which is not the
    /// same as sending them one at a time: a follow-up from the first would
    /// otherwise be processed before the second, and FIFO order is a property
    /// callers depend on.
    public func enqueue(_ action: A) throws {
        try driver.enqueue(action)
    }

    /// Drain the mailbox.
    @discardableResult
    public func drain() throws -> Progress {
        try driver.run(step: stepFn, perform: performFn)
    }
}

/// The asynchronous store.
///
/// An `actor` rather than a class with a lock, because the thing being
/// protected is exactly what an actor protects: one piece of mutable state
/// with serialized access. `Driver` already refuses re-entrancy by throwing
/// `DriverError.reentered`; actor isolation makes concurrent `send` calls
/// queue instead of racing to find out.
///
/// `state` and `pending` are `async` from outside, which is not an
/// inconvenience to be worked around. A state read that crossed the isolation
/// boundary synchronously would be a state read that could tear.
public actor AsyncStore<S, A, F> {
    private let driver: AsyncDriver<S, A, F>
    private let stepFn: (S, A) async -> Step<S, F>
    private let performFn: (F) async -> A?

    public init(
        initial: S,
        capacity: Int = 8,
        step: @escaping (S, A) async -> Step<S, F>,
        perform: @escaping (F) async -> A?
    ) {
        self.driver = AsyncDriver(initial: initial, capacity: capacity)
        self.stepFn = step
        self.performFn = perform
    }

    /// The current state.
    public var state: S { driver.state }

    /// Pending actions.
    public var pending: Int { driver.pending }

    /// Mailbox capacity.
    public var capacity: Int { driver.capacity }

    /// Dispatch one action and drain everything it causes.
    @discardableResult
    public func send(_ action: A) async throws -> Progress {
        try await driver.dispatch(action, step: stepFn, perform: performFn)
    }

    /// Add an action to the back of the mailbox without draining.
    public func enqueue(_ action: A) throws {
        try driver.enqueue(action)
    }

    /// Drain the mailbox.
    @discardableResult
    public func drain() async throws -> Progress {
        try await driver.run(step: stepFn, perform: performFn)
    }
}

// MARK: - On the observable store
//
// `@MainActor @Observable ObservableStore` is the third type Phase 5 lists and
// it is deliberately not here.
//
// `@Observable` is macOS 14 / iOS 17 and needs Swift 5.9. This package declares
// `swift-tools-version: 5.7` with no `platforms:` clause, which was a
// considered choice — a low tools-version builds on any toolchain above it, and
// nothing in the core needs newer. Adding an observable store means either
// raising the floor for every consumer of a library that does not otherwise
// need it, or carrying `#if canImport(Observation)` plus `@available`
// annotations around a type that is then absent on exactly the toolchains the
// CI sandbox is most likely to have.
//
// Neither is obviously right, and the decision belongs with the TabulaMacros
// packaging decision rather than ahead of it: macros need 5.9 too, so the
// floor moves once, for a reason, or not at all. `Store` above is what an
// observable store would wrap, so nothing here has to change when it lands.
