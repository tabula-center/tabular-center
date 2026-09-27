/**
 * A child machine, written knowing nothing about any parent.
 *
 * That is the whole claim composition rests on: this file has no idea it is
 * delegated to. The parent in `Job.tb.kt` names it with one `CellSpec`, and
 * everything else -- its package, its types, its context -- the processor
 * reads from here.
 *
 * Named `Retry.tb.kt` per `spec/matrix-files.md`.
 */
package generated.retry

import dev.tabularcenter.CellSpec
import dev.tabularcenter.Kind
import dev.tabularcenter.Machine
import dev.tabularcenter.Row
import dev.tabularcenter.Step

@Machine(
    states = [S.Ready::class, S.Waiting::class, S.Exhausted::class],
    actions = [A.Attempt::class, A.Elapsed::class, A.Abort::class],
    effects = [F.Sleep::class, F.GiveUp::class],
    initial = S.Ready::class,
)
//                          Attempt                  Elapsed                  Abort
@Row(S.Ready::class,      [CellSpec(Kind.HANDLE),   CellSpec(Kind.IGNORE),   CellSpec(Kind.GO, to = S.Exhausted::class)])
@Row(S.Waiting::class,    [CellSpec(Kind.IGNORE),   CellSpec(Kind.HANDLE),   CellSpec(Kind.GO, to = S.Exhausted::class)])
@Row(S.Exhausted::class,  [CellSpec(Kind.IGNORE),   CellSpec(Kind.IGNORE),   CellSpec(Kind.IGNORE)])
interface RetrySpec {
    fun handle(ctx: Ctx, state: S, action: A): Step<S, F>
}
