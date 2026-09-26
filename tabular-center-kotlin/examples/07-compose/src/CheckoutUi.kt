// The checkout screen. Buttons and text, as every other screen here: what is
// different is the machine behind it, not this file.
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
fun CheckoutUi(model: CheckoutModel) {
    MaterialTheme {
        Column(
            modifier = Modifier.padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(model.step, style = MaterialTheme.typography.h5)
            Text(model.detail)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for (button in model.buttons) {
                    Button(onClick = button.onClick) { Text(button.label) }
                }
            }
            Text("The happy path is the diagonal; everything else is a way off it:")
            Text(model.grid, fontFamily = FontFamily.Monospace, fontSize = 12.sp)
            if (model.log.isNotEmpty()) {
                Text("Effects performed:")
                Text(model.log.joinToString("\n"), fontFamily = FontFamily.Monospace, fontSize = 12.sp)
            }
        }
    }
}
