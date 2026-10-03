// The one cell a developer writes, and the one effect handler.
package generated.gate

import center.tabula.Step

class GateImpl : Cells {
    override suspend fun closedRequest(ctx: Ctx, state: S.Closed, action: A.Request): Step<S, F> =
        Step.Go(S.Opening)

    override suspend fun chime(ctx: Ctx, effect: F.Chime): A? = null
}
