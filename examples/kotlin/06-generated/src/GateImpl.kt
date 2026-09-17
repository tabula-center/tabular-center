// The one cell a developer writes, and the one effect handler.
package generated.gate

import dev.tabula.Step

class GateImpl : Cells {
    override suspend fun closedRequest(ctx: Ctx, state: S.Closed, action: A.Request): Step<S, F> =
        Step.Go(S.Opening)

    /**
     * Returns the follow-up action, or null. `Arrived` is what turns the
     * effect into the next step, so the driver drains `Request -> Opening ->
     * Chime -> Arrived -> Open` from a single dispatch.
     */
    override suspend fun chime(ctx: Ctx, effect: F.Chime): A? = null
}
