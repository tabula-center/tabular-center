// The happy path, and the ways off it, through the generated dispatcher.
//
// The four cells the `@Path` names are HANDLE in the source and GO in the
// table -- that is the derivation, and the first check below is what proves
// it happened: walking Next four times reaches Placed with no cell member
// for any of those steps.

import dev.tabula.Step
import example.compose.CheckoutCells
import example.compose.checkout.A
import example.compose.checkout.Ctx
import example.compose.checkout.F
import example.compose.checkout.S
import example.compose.checkout.step

fun checkoutChecks() {
    val log = mutableListOf<String>()
    val cells = CheckoutCells { log += it }
    val ctx = Ctx(total = 40)

    // The spine, walked. Each hop is a GO the path derived or a GO written
    // because it emits; none of them is a member of `Cells`.
    Check.eq(step(cells, ctx, S.Cart, A.Next), Step.Go(S.Address), "cart -> address, derived")
    Check.eq(step(cells, ctx, S.Address, A.Next), Step.Go(S.Payment), "address -> payment, derived")
    Check.eq(
        step(cells, ctx, S.Payment, A.Next),
        Step.Go(S.Review, listOf(F.Charge)),
        "payment -> review, charging on the way",
    )
    Check.eq(
        step(cells, ctx, S.Review, A.Next),
        Step.Go(S.Placed, listOf(F.Email)),
        "review -> placed, with a receipt",
    )

    // The path ends where the machine is done: nothing leaves Placed, which
    // is what `tabular-center::path-unterminated` would say if one of them did.
    Check.eq(step(cells, ctx, S.Placed, A.Next), Step.Ignored, "nothing leaves Placed")
    Check.eq(step(cells, ctx, S.Placed, A.Abandon), Step.Ignored, "not even abandoning")

    // Off the path: the half a spine does not describe, and the reason the
    // table is still a table.
    Check.eq(
        step(cells, ctx, S.Payment, A.Decline),
        Step.Go(S.Declined("the card was declined")),
        "declining carries why, as a literal the cell supplied",
    )
    Check.eq(step(cells, ctx, S.Address, A.Back), Step.Go(S.Cart), "back, one step")
    Check.eq(step(cells, ctx, S.Cart, A.Back), Step.Ignored, "and nowhere to go back to from the cart")

    // The one cell left to code decides rather than transitions.
    Check.eq(
        step(cells, ctx, S.Declined("x"), A.Next),
        Step.Go(S.Payment),
        "a retry is worth making when there is something to pay",
    )
    Check.eq(
        step(cells, Ctx(total = 0), S.Declined("x"), A.Next),
        Step.Go(S.Abandoned),
        "and is not when there is not",
    )
}
