import Tabula

/// Composition: a parent machine driving a child through a `DELEGATE` cell.
///
/// The claim under test, the same one `composition.rs` and `Composition.kt`
/// prove for their languages:
///
/// > Scoping a total child into a total parent yields a total parent, and the
/// > compiler proves it by the same mechanism as everything else.
///
/// **Protocols are Swift's trait bounds**, exactly as interfaces are Kotlin's.
/// `protocol JobCells: RetryCells` means implementing the parent requires
/// implementing the child, so a hole anywhere in the child breaks any type
/// conforming to the parent. `compile_fail/child_hole_breaks_parent.swift`
/// holds the proof; this file holds the behaviour.
///
/// A protocol rather than a base class for the same reason Kotlin uses an
/// interface: a class extends one parent, which would cap a machine at one
/// child.
///
/// ## Why this lives beside the adapters
///
/// Kotlin keeps its composition reference in `test/` and adapts it from
/// `conformance/`, because kotlinc compiles loose files. Swift executables
/// cannot import one another, so the machines live in the target that uses
/// them. A language-shaped difference, like every other one recorded in
/// ARCHITECTURE §11.0.

// MARK: - Child: a retry machine, written knowing nothing about its parent

enum RetryS: Equatable { case ready, waiting(attempt: Int), exhausted }
enum RetryA: Equatable { case attempt, elapsed, abort }
enum RetryF: Equatable { case sleep, giveUp }

final class RetryCtx {
    let maxAttempts: Int
    init(maxAttempts: Int) { self.maxAttempts = maxAttempts }
}

struct RetryWaiting { let attempt: Int }

protocol RetryCells {
    func readyAttempt(_ ctx: RetryCtx) -> Step<RetryS, RetryF>
    func waitingElapsed(_ ctx: RetryCtx, _ s: RetryWaiting) -> Step<RetryS, RetryF>
}

func retryStep(_ c: RetryCells, _ ctx: RetryCtx, _ s: RetryS, _ a: RetryA) -> Step<RetryS, RetryF> {
    switch (s, a) {
    case (.ready, .attempt): return c.readyAttempt(ctx)
    case (.ready, .elapsed): return .ignored
    case (.ready, .abort): return .go(.exhausted, effects: [])
    case (.waiting, .attempt): return .ignored
    case let (.waiting(attempt), .elapsed):
        return c.waitingElapsed(ctx, RetryWaiting(attempt: attempt))
    case (.waiting, .abort): return .go(.exhausted, effects: [])
    case (.exhausted, .attempt): return .ignored
    case (.exhausted, .elapsed): return .ignored
    case (.exhausted, .abort): return .ignored
    }
}

let RETRY_TABLE = Table(
    machine: "Retry",
    states: ["Ready", "Waiting", "Exhausted"],
    actions: ["Attempt", "Elapsed", "Abort"],
    cells: [
        [.handle, .ignore, .go(target: "Exhausted", effects: [])],
        [.ignore, .handle, .go(target: "Exhausted", effects: [])],
        [.ignore, .ignore, .ignore],
    ],
    initial: "Ready"
)

// MARK: - Parent: a job whose Retrying state holds the child's state

enum JobS: Equatable { case idle, retrying(child: RetryS), done }
enum JobA: Equatable { case run, tick, cancel }
enum JobF: Equatable { case log, backoff, alert }

/// The parent's context **contains** the child's, so `retryChildCtx` is a field
/// access and the child never sees job data it has no business with.
final class JobCtx {
    let retry: RetryCtx
    init(retry: RetryCtx) { self.retry = retry }
}

struct JobRetrying { let child: RetryS }

/// The parent's surface **extends the child's**.
protocol JobCells: RetryCells {
    func idleRun(_ ctx: JobCtx) -> Step<JobS, JobF>

    // One per DELEGATE cell: the action prism, and the only genuinely per-cell
    // part of composition.
    func retryingRunToChild(_ ctx: JobCtx, _ s: JobRetrying) -> RetryA?
    func retryingTickToChild(_ ctx: JobCtx, _ s: JobRetrying) -> RetryA?

    // Once per child: the lens, the effect relabelling, the context.
    func retryChildState(_ s: JobRetrying) -> RetryS
    func retryEmbed(_ s: JobRetrying, _ child: RetryS) -> JobS
    func retryLift(_ effect: RetryF) -> JobF
    func retryChildCtx(_ ctx: JobCtx) -> RetryCtx
}

func jobStep(_ c: JobCells, _ ctx: JobCtx, _ s: JobS, _ a: JobA) -> Step<JobS, JobF> {
    switch (s, a) {
    case (.idle, .run): return c.idleRun(ctx)
    case (.idle, .tick): return .ignored
    case (.idle, .cancel): return .ignored
    case let (.retrying(child), .run):
        let st = JobRetrying(child: child)
        return delegateToRetry(c, ctx, st, c.retryingRunToChild(ctx, st))
    case let (.retrying(child), .tick):
        let st = JobRetrying(child: child)
        return delegateToRetry(c, ctx, st, c.retryingTickToChild(ctx, st))
    case (.retrying, .cancel): return .go(.done, effects: [.log])
    case (.done, .run): return .ignored
    case (.done, .tick): return .ignored
    case (.done, .cancel): return .ignored
    }
}

/// Run the child and fold the result back through the lens.
///
/// A nil child action reports **ignored**, not stay: a parent action the
/// child's alphabet does not contain was not handled, and the distinction is
/// load-bearing for the lints.
private func delegateToRetry(
    _ c: JobCells, _ ctx: JobCtx, _ s: JobRetrying, _ childAction: RetryA?
) -> Step<JobS, JobF> {
    guard let childAction else { return .ignored }
    let childStep = retryStep(c, c.retryChildCtx(ctx), c.retryChildState(s), childAction)
    let effects = childStep.effects.map(c.retryLift)
    switch childStep {
    case let .go(next, _): return .go(c.retryEmbed(s, next), effects: effects)
    case .stay: return .stay(effects: effects)
    case .ignored: return .ignored
    }
}

let JOB_TABLE = Table(
    machine: "Job",
    states: ["Idle", "Retrying", "Done"],
    actions: ["Run", "Tick", "Cancel"],
    cells: [
        [.handle, .ignore, .ignore],
        [.delegate(child: "retry"), .delegate(child: "retry"), .go(target: "Done", effects: ["Log"])],
        [.ignore, .ignore, .ignore],
    ],
    initial: "Idle"
)

// MARK: - One type satisfying BOTH machines' surfaces

struct ComposedImpl: JobCells {
    // The child's cells, required because `JobCells: RetryCells`.
    func readyAttempt(_ ctx: RetryCtx) -> Step<RetryS, RetryF> {
        .go(.waiting(attempt: 1), effects: [.sleep])
    }

    func waitingElapsed(_ ctx: RetryCtx, _ s: RetryWaiting) -> Step<RetryS, RetryF> {
        s.attempt >= ctx.maxAttempts
            ? .go(.exhausted, effects: [.giveUp])
            : .go(.waiting(attempt: s.attempt + 1), effects: [.sleep])
    }

    // The parent's own cell.
    func idleRun(_ ctx: JobCtx) -> Step<JobS, JobF> {
        .go(.retrying(child: .ready), effects: [.log])
    }

    func retryingRunToChild(_ ctx: JobCtx, _ s: JobRetrying) -> RetryA? { .attempt }
    func retryingTickToChild(_ ctx: JobCtx, _ s: JobRetrying) -> RetryA? { .elapsed }

    func retryChildState(_ s: JobRetrying) -> RetryS { s.child }

    /// A child transition can be a parent transition: `embed` returns the full
    /// parent state, so the child reaching its terminal state moves the parent
    /// out of `retrying` entirely.
    func retryEmbed(_ s: JobRetrying, _ child: RetryS) -> JobS {
        if case .exhausted = child { return .done }
        return .retrying(child: child)
    }

    func retryLift(_ effect: RetryF) -> JobF {
        switch effect {
        case .sleep: return .backoff
        case .giveUp: return .alert
        }
    }

    func retryChildCtx(_ ctx: JobCtx) -> RetryCtx { ctx.retry }
}
