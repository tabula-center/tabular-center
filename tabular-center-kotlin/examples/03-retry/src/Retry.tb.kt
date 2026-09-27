// The matrix, in a file of its own: see spec/matrix-files.md. `.editorconfig`
// exempts `*.tb.kt` from the alignment rules, so the rows stay a grid; the
// rest of this example is ordinary Kotlin, formatted normally.
package examples.retry

import dev.tabularcenter.Cell
import dev.tabularcenter.Table

val TABLE = Table(
    machine = "Retry",
    states = listOf("Ready", "Waiting", "Exhausted"),
    actions = listOf("Attempt", "Elapsed", "Abort"),
    initial = "Ready",
    cells = listOf(
        listOf(Cell.Handle, Cell.Ignore, Cell.Go("Exhausted")),
        listOf(Cell.Ignore, Cell.Handle, Cell.Go("Exhausted")),
        listOf(Cell.Ignore, Cell.Ignore, Cell.Ignore),
    ),
)
