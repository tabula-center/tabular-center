import TabularCenter

/// **The Swift macro's specification.**
///
/// Hand-written, exactly as `reference_timer.rs` and `ReferenceTimer.kt` are
/// for their generators: the generator needs a target before it needs an
/// implementation. Everything below the `GENERATED` line is what the macro
/// must emit.
///
/// ## Which shape Swift takes
///
/// ARCHITECTURE §11.0 records a divergence that runs one way: *Rust reaches
/// for generics wherever `macro_rules!` cannot build an identifier; Kotlin
/// names things.* Swift macros **can** build identifiers, and a Swift type
/// cannot conform to one generic protocol at two different arguments — the
/// same restriction Kotlin has.
///
/// So Swift lands with Kotlin, not with Rust: a protocol with **named
/// members**, one per cell. That was the prediction, and it holds for both
/// reasons independently.
///
/// The matrix being specified:
///
/// ```text
///               Start                   Tick     Cancel
///   Idle    [   HANDLE,                 IGNORE,  IGNORE              ]
///   Running [   IGNORE,                 HANDLE,  GO(Idle, StopClock) ]
///   Done    [   GO(Running, StartClock) IGNORE,  IGNORE              ]
/// ```

// MARK: - What the developer declares

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

/// Why a clock stopped. `stopClock` is emitted from two different places.
enum Reason: Equatable { case cancelled, elapsed }

enum F: Equatable {
    case startClock
    case stopClock(reason: Reason)
}

/// Cross-state data. Rule R4: payload is state-local, `Ctx` outlives
/// transitions. A class because cells mutate it and Swift structs are values.
final class Ctx {
    let limit: Int
    var ticksSeen = 0
    var log: [String] = []
    init(limit: Int) { self.limit = limit }
}

// MARK: - Narrowed variant types
//
// One struct per payload-carrying variant, so a cell receives its payload
// already destructured. Payload-free variants need no type: the cell simply
// takes no state argument for them.

struct Running: Equatable { let since: Int }
struct Tick: Equatable { let now: Int }

// MARK: - GENERATED — everything below is what the macro must emit

/// The cell surface: one required member per non-static cell, with narrowed
/// argument types.
///
/// A protocol, not a base class, because this is what composes: a parent
/// machine declares `protocol Cells: AuthCells` and a hole anywhere in the
/// child then breaks the parent's build. Swift has no multiple inheritance for
/// classes, so a base class would cap composition at one child — the identical
/// argument that made Kotlin's surface an interface.
protocol TimerCells {
    func idleStart(_ ctx: Ctx) -> Step<S, F>
    func runningTick(_ ctx: Ctx, _ state: Running, _ action: Tick) -> Step<S, F>

    // One required member per effect variant. Add an effect to the declaration
    // and every handler stops compiling.
    func startClock(_ ctx: Ctx) -> A?
    func stopClock(_ ctx: Ctx, _ effect: Reason) -> A?
}

/// Dispatch one `(state, action)` pair.
///
/// The `switch` exists **only here**. A developer never writes one, so
/// `default:` is not a temptation — it is not available. That is the
/// difference between a convention and a guarantee, and it is why the macro
/// owns the dispatcher rather than checking one the developer wrote.
///
/// Note the absence of `default:`. Adding a case to `S` or `A` breaks this
/// switch at compile time via Swift's own exhaustiveness checking — the free
/// second guarantee, the same one rustc gives the Rust macro and kotlinc gives
/// the Kotlin one.
func step(_ cells: TimerCells, _ ctx: Ctx, _ s: S, _ a: A) -> Step<S, F> {
    switch (s, a) {
    case (.idle, .start):
        return cells.idleStart(ctx)
    case (.idle, .tick):
        return .ignored
    case (.idle, .cancel):
        return .ignored

    case (.running, .start):
        return .ignored
    case let (.running(since), .tick(now)):
        return cells.runningTick(ctx, Running(since: since), Tick(now: now))
    case (.running, .cancel):
        return .go(.idle, effects: [.stopClock(reason: .cancelled)])

    case (.done, .start):
        return .go(.running(since: 0), effects: [.startClock])
    case (.done, .tick):
        return .ignored
    case (.done, .cancel):
        return .ignored
    }
}

/// Carry out one effect, returning any follow-up action.
func perform(_ cells: TimerCells, _ ctx: Ctx, _ f: F) -> A? {
    switch f {
    case .startClock:
        return cells.startClock(ctx)
    case let .stopClock(reason):
        return cells.stopClock(ctx, reason)
    }
}

/// The matrix as inert data. Diagrams, lints, and coverage read this.
let TIMER_TABLE = Table(
    machine: "Timer",
    states: ["Idle", "Running", "Done"],
    actions: ["Start", "Tick", "Cancel"],
    cells: [
        [.handle, .ignore, .ignore],
        [.ignore, .handle, .go(target: "Idle", effects: ["StopClock"])],
        [.go(target: "Running", effects: ["StartClock"]), .ignore, .ignore],
    ],
    initial: "Idle"
)

// MARK: - DEVELOPER — two cells, two effects, four members

struct Timer: TimerCells {
    func idleStart(_ ctx: Ctx) -> Step<S, F> {
        .go(.running(since: 0), effects: [.startClock])
    }

    func runningTick(_ ctx: Ctx, _ state: Running, _ action: Tick) -> Step<S, F> {
        // Payload arrives destructured and non-optional: no `if case`, no
        // cast, no force-unwrap. Rule R2.
        ctx.ticksSeen += 1
        if action.now - state.since >= ctx.limit {
            return .go(.done, effects: [.stopClock(reason: .elapsed)])
        }
        // Handled, staying put. Distinct from `.ignored`, which would claim a
        // tick is meaningless while running.
        return .stay(effects: [])
    }

    func startClock(_ ctx: Ctx) -> A? {
        ctx.log.append("start")
        return nil
    }

    func stopClock(_ ctx: Ctx, _ effect: Reason) -> A? {
        ctx.log.append("stop:\(effect)")
        return nil
    }
}
