// One cell, and it is the one OFF the spine.
//
// `Idle`/`Start` and `Connecting`/`Ready` are written `HANDLE` in the matrix
// and do not appear here: the path named them, so the generator wrote them.
// That is the whole feature -- the ordinary route costs a declaration, and
// what is left to implement is the retry.
package generated.spine

import center.tabula.Step

class SpineImpl : Cells {
    override fun failedStart(ctx: Ctx, state: S.Failed, action: A.Start): Step<S, F> =
        Step.Go(S.Connecting)
}
