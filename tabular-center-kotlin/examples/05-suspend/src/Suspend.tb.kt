// The matrix, in a file of its own: see spec/matrix-files.md. `.editorconfig`
// exempts `*.tb.kt` from the alignment rules, so the rows stay a grid; the
// rest of this example is ordinary Kotlin, formatted normally.
package examples.suspending

import center.tabula.Cell
import center.tabula.Table

//            Start    Arrived   Give
// Idle       HANDLE   IGNORE    IGNORE
// Loading    IGNORE   HANDLE    GO(Loaded)
// Loaded     IGNORE   IGNORE    IGNORE
val TABLE = Table(
    machine = "Fetch",
    states = listOf("Idle", "Loading", "Loaded"),
    actions = listOf("Start", "Arrived", "Give"),
    initial = "Idle",
    cells = listOf(
        listOf(Cell.Handle, Cell.Ignore, Cell.Ignore),
        listOf(Cell.Ignore, Cell.Handle, Cell.Go("Loaded")),
        listOf(Cell.Ignore, Cell.Ignore, Cell.Ignore),
    ),
)
