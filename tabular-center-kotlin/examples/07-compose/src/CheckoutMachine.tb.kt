/**
 * The happy path, and everything that is not it.
 *
 * A checkout: cart, address, payment, review, placed. The `@Path` below is
 * that route, written once and in both directions. Each `HANDLE` on a hop
 * becomes a `GO` to the next state; each `HANDLE` on the hop's far side, under
 * the `back` action, becomes a `GO` to the one before.
 *
 * ## Without the path
 *
 * The same machine, spelled out, needs seven targets where this needs none:
 *
 *     Row(Cart)     GO(Address)   IGNORE
 *     Row(Address)  GO(Payment)   GO(Cart)
 *     Row(Payment)  GO(Review)    GO(Address)
 *     Row(Review)   GO(Placed)    GO(Payment)
 *
 * Both columns are the route, and the second is the route written again
 * BACKWARDS -- where a wrong target looks exactly like a right one, and only
 * a reader walking the wizard in their head can tell. `back = Back::class`
 * says it once instead, and those cells become `HANDLE`s the path fills in.
 *
 * ## What it still does not buy
 *
 * A smaller wizard. Decline, abandon and retry are a third of these
 * twenty-eight cells and no route describes them: they are why this is a
 * matrix and not a list of five screens. What a path removes is the part that
 * was duplicated, which is also the only part that can rot.
 */
package example.compose.checkout

import center.tabula.CellSpec as C
import center.tabula.Kind.GO
import center.tabula.Kind.HANDLE
import center.tabula.Kind.IGNORE
import center.tabula.Machine
import center.tabula.Path
import center.tabula.Row
import center.tabula.Step
import example.compose.checkout.A.Abandon
import example.compose.checkout.A.Back
import example.compose.checkout.A.Decline
import example.compose.checkout.A.Next
import example.compose.checkout.F.Charge
import example.compose.checkout.F.Email
import example.compose.checkout.S.Abandoned
import example.compose.checkout.S.Address
import example.compose.checkout.S.Cart
import example.compose.checkout.S.Declined
import example.compose.checkout.S.Payment
import example.compose.checkout.S.Placed
import example.compose.checkout.S.Review

private const val CARD = "(\"the card was declined\")"
private const val BANK = "(\"the bank refused the charge\")"

@Machine(
    states = [
        Cart::class, Address::class, Payment::class, Review::class,
        Placed::class, Declined::class, Abandoned::class,
    ],
    actions = [Next::class, Back::class, Decline::class, Abandon::class],
    effects = [Charge::class, Email::class],
    initial = Cart::class,
)
@Path(
    "checkout",
    [
        Cart::class, Next::class,
        Address::class, Next::class,
        Payment::class, Next::class,
        Review::class, Next::class,
        Placed::class,
    ],
    back = Back::class,
)
//                      Next                                               Back                        Decline                                   Abandon
@Row(Cart::class,      [C(HANDLE),                                         C(IGNORE),                  C(IGNORE),                                C(GO, to = Abandoned::class)])
@Row(Address::class,   [C(HANDLE),                                         C(HANDLE),                  C(IGNORE),                                C(GO, to = Abandoned::class)])
@Row(Payment::class,   [C(GO, to = Review::class, emit = [Charge::class]), C(HANDLE),                  C(GO, to = Declined::class, args = CARD), C(GO, to = Abandoned::class)])
@Row(Review::class,    [C(GO, to = Placed::class, emit = [Email::class]),  C(HANDLE),                  C(GO, to = Declined::class, args = BANK), C(GO, to = Abandoned::class)])
@Row(Placed::class,    [C(IGNORE),                                         C(IGNORE),                  C(IGNORE),                                C(IGNORE)])
@Row(Declined::class,  [C(HANDLE),                                         C(GO, to = Payment::class), C(IGNORE),                                C(GO, to = Abandoned::class)])
@Row(Abandoned::class, [C(GO, to = Cart::class),                           C(IGNORE),                  C(IGNORE),                                C(IGNORE)])
interface CheckoutSpec {
    fun handle(ctx: Ctx, state: S, action: A): Step<S, F>
}
