import Tabula

// A colorless child inside a colored parent: the allowed direction of color
// flow. The child's cells stay uncolored -- they are `RetryCells`, exactly as
// in `CompleteJob` -- while the parent's are `async throws`, and the parent's
// generated helper calls `Retry.step` with a harmless `try await`.
final class CompleteJobAsync: JobAsyncCells {
    func readyAttempt(_ ctx: Retry.Ctx) -> Step<Retry.S, Retry.F> {
        .go(.waiting(attempt: 1), effects: [.sleep])
    }

    func waitingElapsed(_ ctx: Retry.Ctx, _ state: Retry.Waiting) -> Step<Retry.S, Retry.F> {
        .go(.exhausted, effects: [.giveUp])
    }

    func sleep(_ ctx: Retry.Ctx) -> Retry.A? { .elapsed }
    func giveUp(_ ctx: Retry.Ctx) -> Retry.A? { nil }

    func idleRun(_ ctx: JobAsync.Ctx) async throws -> Step<JobAsync.S, JobAsync.F> {
        .go(.retrying(child: .ready), effects: [.log])
    }

    func log(_ ctx: JobAsync.Ctx) async throws -> JobAsync.A? { nil }

    func retryingRunToChild(_ ctx: JobAsync.Ctx, _ state: JobAsync.Retrying) async throws -> Retry.A? {
        .attempt
    }

    func retryingTickToChild(_ ctx: JobAsync.Ctx, _ state: JobAsync.Retrying) async throws -> Retry.A? {
        .elapsed
    }

    func retryChildState(_ s: JobAsync.S) -> Retry.S {
        if case let .retrying(child) = s { return child }
        return .ready
    }

    func retryEmbed(_ s: JobAsync.S, _ child: Retry.S) -> JobAsync.S { .retrying(child: child) }
    func retryLift(_ effect: Retry.F) -> JobAsync.F { .log }
    func retryChildCtx(_ ctx: JobAsync.Ctx) -> Retry.Ctx { ctx.retry }
}

func driveJobAsync() async throws -> Step<JobAsync.S, JobAsync.F> {
    try await JobAsync.step(
        CompleteJobAsync(), JobAsync.Ctx(retry: Retry.Ctx(maxAttempts: 3)), .retrying(child: .ready), .run)
}
