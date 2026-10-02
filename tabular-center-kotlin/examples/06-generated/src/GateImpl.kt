// The one cell a developer writes, and the one effect handler.
package generated.gate

import center.tabula.Step

class GateImpl : Cells {
    override suspend fun closedRequest(ctx: Ctx, state: S.Closed, action: A.Request): Step<S, F> =
        Step.Go(S.Opening)

    /**
     * Returns the follow-up action, or null. Null here: `Chime` fires on
     * `Opening --Arrived--> Open` and asks for nothing further, which is what
     * `GateTest` asserts -- one dispatch, one step. Returning an action would
     * queue it through the driver's mailbox rather than re-entering `step`.
     */
    override suspend fun chime(ctx: Ctx, effect: F.Chime): A? = null
}
