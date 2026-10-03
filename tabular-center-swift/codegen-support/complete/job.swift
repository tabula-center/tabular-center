import TabularCenter

// One type satisfying BOTH machines' surfaces: `JobCells: RetryCells`, so
// implementing the parent requires implementing the child. The emitted twin
// of `Sources/TabularCenterConformance/Compose.swift`'s `ComposedImpl`.
final class CompleteJob: JobCells {
    func readyAttempt(_ ctx: Retry.Ctx) -> Step<Retry.S, Retry.F> {
        .go(.waiting(attempt: 1), effects: [.sleep])
    }

    func waitingElapsed(_ ctx: Retry.Ctx, _ state: Retry.Waiting) -> Step<Retry.S, Retry.F> {
        state.attempt >= ctx.maxAttempts
            ? .go(.exhausted, effects: [.giveUp])
            : .go(.waiting(attempt: state.attempt + 1), effects: [.sleep])
    }

    func sleep(_ ctx: Retry.Ctx) -> Retry.A? { .elapsed }
    func giveUp(_ ctx: Retry.Ctx) -> Retry.A? { nil }

    func idleRun(_ ctx: Job.Ctx) -> Step<Job.S, Job.F> {
        .go(.retrying(child: .ready), effects: [.log])
    }

    func log(_ ctx: Job.Ctx) -> Job.A? { nil }

    func retryingRunToChild(_ ctx: Job.Ctx, _ state: Job.Retrying) -> Retry.A? { .attempt }
    func retryingTickToChild(_ ctx: Job.Ctx, _ state: Job.Retrying) -> Retry.A? { .elapsed }

    func retryChildState(_ s: Job.S) -> Retry.S {
        if case let .retrying(child) = s { return child }
        return .ready
    }

    func retryEmbed(_ s: Job.S, _ child: Retry.S) -> Job.S { .retrying(child: child) }
    func retryLift(_ effect: Retry.F) -> Job.F { .log }
    func retryChildCtx(_ ctx: Job.Ctx) -> Retry.Ctx { ctx.retry }
}

func driveJob() -> Step<Job.S, Job.F> {
    Job.step(CompleteJob(), Job.Ctx(retry: Retry.Ctx(maxAttempts: 3)), .retrying(child: .ready), .run)
}
