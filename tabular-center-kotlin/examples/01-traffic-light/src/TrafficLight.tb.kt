// The matrix, in a file of its own: see spec/matrix-files.md. `.editorconfig`
// exempts `*.tb.kt` from the alignment rules, so the rows stay a grid; the
// rest of this example is ordinary Kotlin, formatted normally.
package examples.trafficlight

import dev.tabula.Cell
import dev.tabula.Table

val TABLE = Table(
    machine = "TrafficLight",
    states = listOf("Red", "Green", "Amber"),
    actions = listOf("Advance", "Fault"),
    initial = "Red",
    cells = listOf(
        listOf(Cell.Go("Green"), Cell.Go("Red")),
        listOf(Cell.Go("Amber"), Cell.Go("Red")),
        listOf(Cell.Handle, Cell.Go("Red")),
    ),
)
