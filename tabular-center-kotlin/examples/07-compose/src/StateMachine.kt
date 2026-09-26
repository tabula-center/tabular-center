/**
 * The architecture this example is written in, which is not tabula's.
 *
 * Bitkey's (`proto-at-block/bitkey`, `app/libs/state-machine`): a state
 * machine is a `@Composable fun model(props): Model`, using the Compose
 * runtime -- not Compose UI -- to hold state and produce a model the UI
 * renders. Machines compose by a parent calling a child's `model()` inside
 * its own.
 *
 * It is reproduced here, in eight lines, because the interesting question is
 * whether tabula fits an architecture someone already has. tabula does not
 * ship this interface and does not want to: it decides what a machine does,
 * and this decides where the machine lives.
 */
package example.compose

import androidx.compose.runtime.Composable

interface StateMachine<in PropsT : Any, out ModelT : Any> {
    @Composable
    fun model(props: PropsT): ModelT
}
