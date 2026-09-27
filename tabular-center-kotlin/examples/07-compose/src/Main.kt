// The window. Three lines of wiring: the machine produces a model, the UI
// renders it.
package example.compose

import androidx.compose.ui.window.Window
import androidx.compose.ui.window.application

fun main() = application {
    // The nested one: a session containing a connection. The flat screen is
    // `ConnectionStateMachine`, which the checks drive directly.
    val machine = SessionStateMachine(log = ::println)
    var tick = 0
    Window(onCloseRequest = ::exitApplication, title = "tabular-center :: session") {
        SessionUi(machine.model(SessionProps(now = { ++tick })))
    }
}
