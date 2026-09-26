// Checks for `Retry.swift`, in their own file and their own build product.
//
// Swift's split is by *target* rather than by module: these live alongside the
// implementation rather than importing it, because the example types are not
// `public` and making them so would be a sweep across every example for the
// benefit of the harness rather than of a reader. Each example is still its
// own target with its own dependency line, built and run on its own.

import ExampleCheck
import Tabula

#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

do {
    let (state3, ctx3) = try Retry.run(maxAttempts: 3)
    Check.eq(state3, .exhausted, "retry: backs off and gives up on its own")
    Check.eq(
        ctx3.performed, ["sleep:100", "sleep:200", "sleep:300", "give-up"],
        "retry: one dispatch, four effects, all follow-ups through the mailbox")

    let (_, ctx4) = try Retry.run(maxAttempts: 4)
    Check.eq(
        ctx4.performed, ["sleep:100", "sleep:200", "sleep:300", "sleep:400", "give-up"],
        "retry: backoff grows with the attempt")

    let (state1, ctx1) = try Retry.run(maxAttempts: 1)
    Check.eq(state1, .exhausted, "retry: a single attempt gives up immediately")
    Check.eq(ctx1.performed, ["sleep:100", "give-up"], "retry: no extra sleeps")
} catch {
    Check.ok(false, "retry: driver threw \(error)")
}

let aborted = Retry.step(
    Retry.Impl(), Retry.Ctx(maxAttempts: 5), .waiting(attempt: 2), .abort)
Check.eq(aborted, .go(.exhausted, effects: []), "retry: abort is static, no handler needed")

exit(Check.report("swift retry"))
