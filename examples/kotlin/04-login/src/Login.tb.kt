// The matrix, in a file of its own: see spec/matrix-files.md. `.editorconfig`
// exempts `*.tb.kt` from the alignment rules, so the rows stay a grid; the
// rest of this example is ordinary Kotlin, formatted normally.
//
// Top-level rather than inside `object auth` and `object session`, because an
// object cannot span files. Each object keeps `val TABLE = ...`, so callers
// still write `session.TABLE`.
package examples.login

import dev.tabula.Cell
import dev.tabula.Table

val AUTH_TABLE = Table(
    machine = "Auth",
    states = listOf("AwaitingCredentials", "Authenticated", "LockedOut"),
    actions = listOf("Submit", "Reset"),
    initial = "AwaitingCredentials",
    cells = listOf(
        listOf(Cell.Handle, Cell.Go("AwaitingCredentials", listOf("Prompt"))),
        listOf(Cell.Ignore, Cell.Go("AwaitingCredentials", listOf("Prompt"))),
        listOf(Cell.Ignore, Cell.Ignore),
    ),
)

val SESSION_TABLE = Table(
    machine = "Session",
    states = listOf("LoggedOut", "Active", "Banned"),
    actions = listOf("Credentials", "StartOver", "Logout"),
    initial = "LoggedOut",
    cells = listOf(
        listOf(Cell.Delegate("auth"), Cell.Delegate("auth"), Cell.Ignore),
        listOf(Cell.Ignore, Cell.Ignore, Cell.Go("Banned", listOf("Audit"))),
        listOf(Cell.Ignore, Cell.Ignore, Cell.Ignore),
    ),
)
