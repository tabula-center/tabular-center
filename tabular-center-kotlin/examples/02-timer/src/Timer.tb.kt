// The matrix, in a file of its own: see spec/matrix-files.md. `.editorconfig`
// exempts `*.tb.kt` from the alignment rules, so the rows stay a grid; the
// rest of this example is ordinary Kotlin, formatted normally.
package examples.timer

import dev.tabularcenter.Cell
import dev.tabularcenter.Table

val TABLE = Table(
    machine = "Timer",
    states = listOf("Idle", "Running", "Done"),
    actions = listOf("Start", "Tick", "Cancel"),
    initial = "Idle",
    cells = listOf(
        listOf(Cell.Handle,                              Cell.Ignore, Cell.Ignore),
        listOf(Cell.Ignore,                              Cell.Handle, Cell.Go("Idle", listOf("StopClock"))),
        listOf(Cell.Go("Running", listOf("StartClock")), Cell.Ignore, Cell.Ignore),
    ),
)
