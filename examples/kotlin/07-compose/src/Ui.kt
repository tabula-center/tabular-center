// The UI layer: renders a model, sends nothing it was not given.
//
// Note what it cannot do. It has no state type, no actions, no matrix -- only
// strings and callbacks the machine produced. A button that "should not be
// pressed now" is not a concern here, because pressing it sends an action the
// table has already decided about: usually IGNORE.
package example.compose

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.material.Button
import androidx.compose.material.MaterialTheme
import androidx.compose.material.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun ConnectionUi(model: ConnectionModel) {
    MaterialTheme {
        Column(
            modifier = Modifier.padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(model.status, style = MaterialTheme.typography.h5)
            Text(model.detail)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for (button in model.buttons) {
                    Button(onClick = button.onClick) { Text(button.label) }
                }
            }
            // The machine on screen, rendered from the same TABLE the
            // dispatcher uses -- as the iced example's window does.
            Text("The matrix this screen is running:")
            Text(model.grid, fontFamily = FontFamily.Monospace, fontSize = 12.sp)
        }
    }
}
