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

// MARK: - The observable store

// Apple platforms only, and that is the type's honest scope rather than a
// concession. `ObservableStore` exists to be watched by SwiftUI, and SwiftUI
// does not exist off Darwin, so a Linux build has nothing to observe it with.
//
// Two weaker guards were tried first and each answered a question adjacent to
// the one being asked:
//
//   - `#if canImport(Observation)` asks whether the module is present. It is
//     present on the pinned Linux toolchain, and `@Observable` still fails to
//     resolve, because a module says nothing about whether macro plugins load.
//   - Removing the macro got it compiling and linking, and the binary then
//     died on startup: `libswiftObservation.so: undefined symbol`. The module
//     is present, importable, and broken.
//
// Each guard was nearly right, and a guard that is nearly right reports green
// until the moment it matters. The question this type actually wants answered
// is "is there a SwiftUI to observe me", and `os(...)` asks it directly.
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

        /// The current state. Reading this inside a SwiftUI `body` subscribes.
        public var state: S {
            registrar.access(self, keyPath: \.state)
            return storedState
        }

        /// Pending actions.
        public var pending: Int { store.pending }

        /// Mailbox capacity.
        public var capacity: Int { store.capacity }

        /// Dispatch one action and drain everything it causes.
        ///
        /// The mirror is refreshed in a `defer`, so a throw part-way through a
        /// drain still leaves `state` showing where the machine actually got
        /// to. Reporting the old state after a partial drain would be worse
        /// than reporting the error.
        @discardableResult
        public func send(_ action: A) throws -> Progress {
            defer { publish() }
            return try store.send(action)
        }

        /// Add an action to the back of the mailbox without draining.
        ///
        /// Deliberately does not publish: nothing has been stepped, so a view
        /// that redrew here would be showing a state the machine has not
        /// reached.
        public func enqueue(_ action: A) throws {
            try store.enqueue(action)
        }

        /// Drain the mailbox.
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
