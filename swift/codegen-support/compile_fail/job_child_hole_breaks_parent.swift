//~ EXPECT: does not conform to protocol 'RetryCells'
//
// The composition property, after generation: scoping a total child into a
// total parent yields a total parent, by the same mechanism as everything
// else. The emitted `JobCells` refines the emitted `RetryCells`, so a hole in
// the CHILD's surface -- `waitingElapsed` below -- breaks any type conforming
// to the PARENT. The generated twin of swift/compile_fail/child_hole_breaks_parent.swift.
import Tabula

final class Incomplete: JobCells {
    func readyAttempt(_ ctx: Retry.Ctx) -> Step<Retry.S, Retry.F> { .ignored }
    // waitingElapsed is missing -- a child cell.
    func sleep(_ ctx: Retry.Ctx) -> Retry.A? { nil }
    func giveUp(_ ctx: Retry.Ctx) -> Retry.A? { nil }

    func idleRun(_ ctx: Job.Ctx) -> Step<Job.S, Job.F> { .ignored }
    func log(_ ctx: Job.Ctx) -> Job.A? { nil }
    func retryingRunToChild(_ ctx: Job.Ctx, _ state: Job.Retrying) -> Retry.A? { nil }
    func retryingTickToChild(_ ctx: Job.Ctx, _ state: Job.Retrying) -> Retry.A? { nil }
    func retryChildState(_ s: Job.S) -> Retry.S { .ready }
    func retryEmbed(_ s: Job.S, _ child: Retry.S) -> Job.S { s }
    func retryLift(_ effect: Retry.F) -> Job.F { .log }
    func retryChildCtx(_ ctx: Job.Ctx) -> Retry.Ctx { ctx.retry }
}
