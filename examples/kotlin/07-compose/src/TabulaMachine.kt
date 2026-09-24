/**
 * The adapter: a tabula dispatcher, driven from inside `model()`.
 *
 * Everything tabula generates is a pure function -- `step` decides, `perform`
 * carries out one effect and may answer with a follow-up action -- so driving
 * it needs no framework, just somewhere to keep the current state and a queue
 * for follow-ups. That is `remember` and a channel of actions.
 *
 * The loop is deliberately the same shape as `dev.tabula.Driver`: an action
 * produces a step, the step's effects are performed in order, and a follow-up
 * action is ENQUEUED rather than applied by recursing into `step`. A machine
 * that answers its own effect cannot therefore reenter its own transition.
 */
package example.compose

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import dev.tabula.Step

/** The current state, and the one way to change it. */
class Machine<S : Any, A : Any>(
    val state: S,
    val send: (A) -> Unit,
)

/**
 * Remember a machine driven by [step] and [perform].
 *
 * Both are the generated functions, passed as values: this file knows nothing
 * about any particular machine, and nothing about `Cells`.
 */
@Composable
fun <S : Any, A : Any, F : Any> rememberMachine(
    initial: S,
    step: (S, A) -> Step<S, F>,
    perform: (F) -> A?,
): Machine<S, A> {
    var state by remember { mutableStateOf(initial) }

    val send = remember<(A) -> Unit> {
        { first ->
            val queue = ArrayDeque<A>()
            queue.addLast(first)
            while (queue.isNotEmpty()) {
                val decided = step(state, queue.removeFirst())
                if (decided is Step.Go) state = decided.next
                for (effect in decided.effects) {
                    perform(effect)?.let { queue.addLast(it) }
                }
            }
        }
    }

    return Machine(state, send)
}
