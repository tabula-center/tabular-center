//~ EXPECT: no value passed for parameter 'Failed'
//
// THE NARROWED SURFACE HAS THE MATRIX'S GUARANTEE.
//
// Every state the `Connecting` row can produce, other than the happy one, is
// a required parameter of `elvis`. Forgetting `Failed` does not compile --
// which is `elvis` rather than `hadilq/happy`'s `elseIf`, whose generated code
// ends in `result!!` and loses a forgotten case at runtime
// (spec/happy-paths.md).
package generated.connect

fun forgetful(cells: Cells, ctx: Ctx, arrived: A): S.Live {
    val (live, _) = cells.connectingReady(ctx, S.Connecting, arrived).elvis(
        Idle = { return S.Live },
        Connecting = { return S.Live },
    )
    return live
}
