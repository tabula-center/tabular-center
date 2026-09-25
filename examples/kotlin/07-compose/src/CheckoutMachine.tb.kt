/**
 * The happy path, and everything that is not it.
 *
 * A checkout: cart, address, payment, review, placed. The `@Path` below is
 * that route, written once. Each `HANDLE` it names becomes a `GO` to the next
 * state at generation time, so no target is written twice and no two places
 * can disagree about where a step goes.
 *
 * ## Without the path
 *
 * The same machine, spelled out, differs only in the first column -- and that
 * is the whole of what a spine buys:
 *
 * ```
 * //                      Next                        Back                     ...
 * @Row(Cart::class,      [C(GO, to = Address::class), C(IGNORE),               ...
 * @Row(Address::class,   [C(GO, to = Payment::class), C(GO, to = Cart::class), ...
 * @Row(Declined::class,  [C(HANDLE),                  ...
 * ```
 *
 * Four targets instead of four `HANDLE`s: shorter by a few words, and that is
 * not the point. The point is that the route then exists in four places
 * rather than one, in an order only the row order implies, and moving a step
 * means editing two cells and hoping. With the path, the route is one line
 * that `tabula::path-broken` holds to the table: change a row without changing
 * the path and the build says so, by name, before anything runs.
 *
 * ## What it does not buy
 *
 * Conciseness, mostly. The spine removes four cell bodies from a table of
 * twenty-eight, and the grid below is exactly as wide either way -- because
 * every other cell is a decision a wizard has to make anyway, and a list of
 * five screens cannot hold them. The rows are wide because Kotlin's annotation
 * surface is verbose, not because the machine is: Rust's `transition_matrix!`
 * writes the same matrix in half the characters.
 */
package example.compose.checkout

import dev.tabula.CellSpec as C
import dev.tabula.Kind.GO
import dev.tabula.Kind.HANDLE
import dev.tabula.Kind.IGNORE
import dev.tabula.Machine
import dev.tabula.Path
import dev.tabula.Row
import dev.tabula.Step
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

/** Why a card was refused. A `const val`, so a cell may name it. */
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
// The route, once. Every HANDLE it names becomes a GO to the next state.
@Path(
    "checkout",
    [
        Cart::class, Next::class,
        Address::class, Next::class,
        Payment::class, Next::class,
        Review::class, Next::class,
        Placed::class,
    ],
)
//                      Next                                               Back                        Decline                                   Abandon
@Row(Cart::class,      [C(HANDLE),                                         C(IGNORE),                  C(IGNORE),                                C(GO, to = Abandoned::class)])
@Row(Address::class,   [C(HANDLE),                                         C(GO, to = Cart::class),    C(IGNORE),                                C(GO, to = Abandoned::class)])
@Row(Payment::class,   [C(GO, to = Review::class, emit = [Charge::class]), C(GO, to = Address::class), C(GO, to = Declined::class, args = CARD), C(GO, to = Abandoned::class)])
@Row(Review::class,    [C(GO, to = Placed::class, emit = [Email::class]),  C(GO, to = Payment::class), C(GO, to = Declined::class, args = BANK), C(GO, to = Abandoned::class)])
@Row(Placed::class,    [C(IGNORE),                                         C(IGNORE),                  C(IGNORE),                                C(IGNORE)])
@Row(Declined::class,  [C(HANDLE),                                         C(GO, to = Payment::class), C(IGNORE),                                C(GO, to = Abandoned::class)])
@Row(Abandoned::class, [C(GO, to = Cart::class),                           C(IGNORE),                  C(IGNORE),                                C(IGNORE)])
interface CheckoutSpec {
    fun handle(ctx: Ctx, state: S, action: A): Step<S, F>
}
