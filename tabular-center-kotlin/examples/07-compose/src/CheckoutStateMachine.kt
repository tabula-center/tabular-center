/**
 * The checkout screen: a wizard whose route is declared once, as a path.
 *
 * Four of its cells are hops the spine derives, two are hops written as GOs
 * because they emit, and the rest -- back, decline, abandon, retry -- are the
 * table's. One member here, because one cell was left to code.
 */
package example.compose

import androidx.compose.runtime.Composable
import center.tabula.Export
import center.tabula.Step
import example.compose.checkout.A
import example.compose.checkout.Cells
import example.compose.checkout.Ctx
import example.compose.checkout.F
import example.compose.checkout.S
import example.compose.checkout.TABLE
import example.compose.checkout.perform
import example.compose.checkout.step

data class CheckoutModel(
    val step: String,
    val detail: String,
    val buttons: List<Button>,
    val log: List<String>,
    val grid: String,
) {
    data class Button(val label: String, val onClick: () -> Unit)
}

data class CheckoutProps(val total: Int)

class CheckoutCells(private val log: (String) -> Unit) : Cells {

    override fun declinedNext(ctx: Ctx, state: S.Declined, action: A.Next): Step<S, F> =
        if (ctx.total > 0) Step.Go(S.Payment) else Step.Go(S.Abandoned)

    override fun charge(ctx: Ctx, effect: F.Charge): A? {
        log("charging ${ctx.total}")
        return null
    }

    override fun email(ctx: Ctx, effect: F.Email): A? {
        log("emailing the receipt")
        return null
    }
}

class CheckoutStateMachine(private val log: (String) -> Unit = {}) :
    StateMachine<CheckoutProps, CheckoutModel> {

    @Composable
    override fun model(props: CheckoutProps): CheckoutModel {
        val lines = remembering()
        val ctx = Ctx(total = props.total)
        val cells = CheckoutCells { lines.add(it) }
        val machine = rememberMachine<S, A, F>(
            initial = S.Cart,
            step = { s, a -> step(cells, ctx, s, a) },
            perform = { f -> perform(cells, ctx, f) },
        )

        val (name, detail) = when (val s = machine.state) {
            is S.Cart -> "Cart" to "${props.total} to pay."
            is S.Address -> "Address" to "Where is it going?"
            is S.Payment -> "Payment" to "How are you paying?"
            is S.Review -> "Review" to "Everything look right?"
            is S.Placed -> "Placed" to "Thank you."
            is S.Declined -> "Declined" to s.reason
            is S.Abandoned -> "Abandoned" to "Nothing was charged."
        }

        return CheckoutModel(
            step = name,
            detail = detail,
            buttons = listOf(
                CheckoutModel.Button("Next") { machine.send(A.Next) },
                CheckoutModel.Button("Back") { machine.send(A.Back) },
                CheckoutModel.Button("Decline") { machine.send(A.Decline) },
                CheckoutModel.Button("Abandon") { machine.send(A.Abandon) },
            ),
            log = lines.toList(),
            grid = Export.toGrid(TABLE),
        )
    }
}
