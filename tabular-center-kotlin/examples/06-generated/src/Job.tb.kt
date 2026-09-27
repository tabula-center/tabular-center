/**
 * A parent machine, delegating to `generated.retry` through annotations.
 *
 * `CellSpec(Kind.DELEGATE, child = RetrySpec::class)` is the entire
 * declaration. The processor reads the rest off that class: the package its
 * generated code lands in, the alias the parent's members are named from
 * (`retryChildState`, `delegateToRetry`), its `S` / `A` / `F`, and its `Ctx`.
 *
 * A child must be compiled with its parent: `@Machine` is `SOURCE`-retention,
 * so a child from a prebuilt module has no annotation left to read, and is
 * refused as `tabular-center::unknown-child`.
 *
 * Named `Job.tb.kt` per `spec/matrix-files.md`.
 */
package generated.job

import dev.tabula.CellSpec
import dev.tabula.Kind
import dev.tabula.Machine
import dev.tabula.Row
import dev.tabula.Step
import generated.retry.RetrySpec

@Machine(
    states = [S.Idle::class, S.Retrying::class, S.Done::class],
    actions = [A.Run::class, A.Tick::class, A.Cancel::class],
    effects = [F.Log::class],
    initial = S.Idle::class,
)
//                          Run                                              Tick                                             Cancel
@Row(S.Idle::class,       [CellSpec(Kind.HANDLE),                           CellSpec(Kind.IGNORE),                           CellSpec(Kind.IGNORE)])
@Row(S.Retrying::class,   [CellSpec(Kind.DELEGATE, child = RetrySpec::class), CellSpec(Kind.DELEGATE, child = RetrySpec::class), CellSpec(Kind.GO, to = S.Done::class, emit = [F.Log::class])])
@Row(S.Done::class,       [CellSpec(Kind.IGNORE),                           CellSpec(Kind.IGNORE),                           CellSpec(Kind.IGNORE)])
interface JobSpec {
    fun handle(ctx: Ctx, state: S, action: A): Step<S, F>
}
