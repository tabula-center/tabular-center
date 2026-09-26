// The nested UI: the parent's chrome, with the child's screen inside it. The
// child's model arrived from the child's machine; this file does not know
// which machine produced it.
package example.compose

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.material.Button
import androidx.compose.material.Divider
import androidx.compose.material.MaterialTheme
import androidx.compose.material.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun SessionUi(model: SessionModel) {
    MaterialTheme {
        Column(
            modifier = Modifier.padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(model.status, style = MaterialTheme.typography.h5)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for (button in model.buttons) {
                    Button(onClick = button.onClick) { Text(button.label) }
                }
            }
            Text("The session's matrix (the connection's is below):")
            Text(model.grid, fontFamily = FontFamily.Monospace, fontSize = 12.sp)
            model.connection?.let { child ->
                Divider()
                ConnectionUi(child)
            }
        }
    }
}
