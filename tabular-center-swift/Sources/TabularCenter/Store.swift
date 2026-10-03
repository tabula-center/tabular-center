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
///
/// - `init`: - Parameters: - perform: runs one effect and may return a follow-up action.
/// - `state`: The current state.
/// - `pending`: Pending actions.
/// - `capacity`: Mailbox capacity.
/// - `send`: Dispatch one action and drain everything it causes.
/// - `enqueue`: Add an action to the back of the mailbox without draining.
/// - `drain`: Drain the mailbox.
public final class Store<S, A, F> {
    private let driver: Driver<S, A, F>
    private let stepFn: (S, A) -> Step<S, F>
    private let performFn: (F) -> A?

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

    public var state: S { driver.state }

    public var pending: Int { driver.pending }

    public var capacity: Int { driver.capacity }

    @discardableResult
    public func send(_ action: A) throws -> Progress {
        try driver.dispatch(action, step: stepFn, perform: performFn)
    }

    public func enqueue(_ action: A) throws {
        try driver.enqueue(action)
    }

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
///
/// - `state`: The current state.
/// - `pending`: Pending actions.
/// - `capacity`: Mailbox capacity.
/// - `send`: Dispatch one action and drain everything it causes.
/// - `enqueue`: Add an action to the back of the mailbox without draining.
/// - `drain`: Drain the mailbox.
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

    public var state: S { driver.state }

    public var pending: Int { driver.pending }

    public var capacity: Int { driver.capacity }

    @discardableResult
    public func send(_ action: A) async throws -> Progress {
        try await driver.dispatch(action, step: stepFn, perform: performFn)
    }

    public func enqueue(_ action: A) throws {
        try driver.enqueue(action)
    }

    @discardableResult
    public func drain() async throws -> Progress {
        try await driver.run(step: stepFn, perform: performFn)
    }
}

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
    import Observation

    /// A `Store` that SwiftUI can watch.
    ///
    /// The third of Phase 5's runtime types, and the one that moved the
    /// package's tools-version to 5.9. `Package.swift` still declares no
    /// `platforms:` clause: a deployment target there is a floor for every
    /// consumer, so the requirement lives on this type as `@available` rather
    /// than on the package. Nothing else here needs macOS 14.
    ///
    /// ## Written without `@Observable`
    ///
    /// The obvious version of this type is four lines shorter and starts with
    /// `@Observable`. Driving `ObservationRegistrar` by hand is what that
    /// macro expands to: a registrar, an `access` in the getter, a
    /// `withMutation` on write. SwiftUI observes the result identically.
    ///
    /// Kept that way even though the `os(...)` guard above now means only
    /// Darwin compiles this, where the macro does work. A library asking the
    /// toolchain to load macro plugins is asking for something it does not
    /// need, and the twelve lines are the whole cost of not asking.
    ///
    /// ## `state` is a mirror, not the source of truth
    ///
    /// Observation tracks *stored* properties, and a computed
    /// `{ store.state }` would be invisible to it — reading it in a `body`
    /// would subscribe to nothing and the view would never update. So `send`
    /// and `drain` copy the driver's state out afterwards. The copy is the
    /// price of observation and it is confined to this type; `Store` above
    /// still has one state and one owner.
    ///
    /// - `state`: The current state.
    /// - `pending`: Pending actions.
    /// - `capacity`: Mailbox capacity.
    /// - `send`: Dispatch one action and drain everything it causes.
    /// - `enqueue`: Add an action to the back of the mailbox without draining.
    /// - `drain`: Drain the mailbox.
    @available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)
    @MainActor
    public final class ObservableStore<S, A, F>: Observable {
        private let registrar = ObservationRegistrar()
        private let store: Store<S, A, F>
        private var storedState: S

        public init(
            initial: S,
            capacity: Int = 8,
            step: @escaping (S, A) -> Step<S, F>,
            perform: @escaping (F) -> A?
        ) {
            self.storedState = initial
            self.store = Store(
                initial: initial, capacity: capacity, step: step, perform: perform
            )
        }

        public var state: S {
            registrar.access(self, keyPath: \.state)
            return storedState
        }

        public var pending: Int { store.pending }

        public var capacity: Int { store.capacity }

        @discardableResult
        public func send(_ action: A) throws -> Progress {
            defer { publish() }
            return try store.send(action)
        }

        public func enqueue(_ action: A) throws {
            try store.enqueue(action)
        }

        @discardableResult
        public func drain() throws -> Progress {
            defer { publish() }
            return try store.drain()
        }

        private func publish() {
            registrar.withMutation(of: self, keyPath: \.state) {
                storedState = store.state
            }
        }
    }
#endif
