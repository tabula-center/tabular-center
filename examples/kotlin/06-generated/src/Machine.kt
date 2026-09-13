/**
 * The matrix, declared where a user declares it: in annotations.
 *
 * This replaces a hand-written `MachineDesc`. That object is what the KSP
 * processor *builds* from these annotations, so committing one by hand was
 * committing generated code — the dispatcher would have been generated from a
 * description that was not.
 *
 * Nothing here is the generator's output. The `Cells` interface, the `step`
 * dispatcher and the effect-handler surface are all produced by KSP from this
 * file, into `build/generated/ksp/`, which is not committed.
 *
 * The `handle` prototype carries the color and the return type. Every required
 * member the processor emits is stamped from it — no modifiers here means a
 * colorless machine, and adding `suspend` to this one line would make the whole
 * generated surface suspending.
 */
package generated.turnstile

import dev.tabula.CellSpec
import dev.tabula.Kind
import dev.tabula.Machine
import dev.tabula.Row
import dev.tabula.Step

@Machine(
    states = [S.Locked::class, S.Unlocked::class],
    actions = [A.Coin::class, A.Push::class],
    effects = [F.Click::class],
    initial = S.Locked::class,
    name = "Turnstile",
)
//                     Coin                                   Push
@Row(
    S.Locked::class,
    [
        CellSpec(Kind.GO, to = S.Unlocked::class, emit = [F.Click::class]),
        CellSpec(Kind.IGNORE),
    ],
)
@Row(
    S.Unlocked::class,
    [
        CellSpec(Kind.IGNORE),
        CellSpec(Kind.HANDLE),
    ],
)
interface Turnstile {
    fun handle(ctx: Ctx, state: S, action: A): Step<S, F>
}
