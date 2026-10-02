// The happy path, and the ways off it, through the generated dispatcher.
//
// The four cells the `@Path` names are HANDLE in the source and GO in the
// table -- that is the derivation, and the first check below is what proves
// it happened: walking Next four times reaches Placed with no cell member
// for any of those steps.

import center.tabula.Step
import example.compose.CheckoutCells
import example.compose.checkout.A
import example.compose.checkout.Cells
import example.compose.checkout.Ctx
import example.compose.checkout.F
import example.compose.checkout.S
import example.compose.checkout.addressNext
import example.compose.checkout.cartNext
import example.compose.checkout.elvis
import example.compose.checkout.paymentNext
import example.compose.checkout.reviewNext
import example.compose.checkout.step

/**
 * One purchase, stepping the machine itself: each screen takes the event that
 * arrived, the happy path reads straight down, and every way off it is a
 * named, required handler that leaves from here -- `elvis` is `inline`.
 *
 * This is where the narrowed surface belongs: code that owns its stepping.
 * The app's `model()` does not -- `rememberMachine` already dispatches every
 * action and runs every effect, and the narrowed members hand effects BACK,
 * for a caller that runs them itself (spec/happy-paths.md). Here that is this
 * function, which collects them.
 */
fun purchase(cells: Cells, ctx: Ctx, events: Iterator<A>): Pair<String, List<F>> {
    val ran = mutableListOf<F>()
    val address = cells.cartNext(ctx, S.Cart, events.next()).elvis(
        Cart = { return "still in the cart" to ran },
        Abandoned = { return "abandoned" to ran },
    )
    ran += address.effects
    val payment = cells.addressNext(ctx, address.state, events.next()).elvis(
        Cart = { return "back to the cart" to ran },
        Address = { return "still on the address" to ran },
        Abandoned = { return "abandoned" to ran },
    )
    ran += payment.effects
    val review = cells.paymentNext(ctx, payment.state, events.next()).elvis(
        Address = { return "back to the address" to ran },
        Declined = { return "declined: ${it.state.reason}" to ran + it.effects },
        Abandoned = { return "abandoned" to ran },
    )
    ran += review.effects
    val placed = cells.reviewNext(ctx, review.state, events.next()).elvis(
        Payment = { return "back to payment" to ran },
        Declined = { return "declined: ${it.state.reason}" to ran + it.effects },
        Abandoned = { return "abandoned" to ran },
    )
    ran += placed.effects
    return "placed" to ran
}

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

    // The narrowed surface, owning its stepping (see `purchase`).
    Check.eq(
        purchase(cells, ctx, listOf(A.Next, A.Next, A.Next, A.Next).iterator()),
        "placed" to listOf(F.Charge, F.Email),
        "the happy path, straight down, both effects handed back to run",
    )
    Check.eq(
        purchase(cells, ctx, listOf(A.Next, A.Next, A.Decline).iterator()).first,
        "declined: the card was declined",
        "a decline is a named handler, not a fall-through",
    )
    Check.eq(
        purchase(cells, ctx, listOf(A.Next, A.Back).iterator()).first,
        "back to the cart",
        "and so is going back, which the path's `back` derived",
    )
}
