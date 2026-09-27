/**
 * The matrix, in a file of its own, and rectangular: see `spec/matrix-files.md`.
 *
 * A connection: idle until asked, connecting until it is live or fails, and
 * retryable from failure. Sixteen cells, all sixteen decided here.
 *
 * The imports are aliases, and they are what keeps the grid a grid --
 * `C(GO, to = Failed::class)` fits in a column where
 * `CellSpec(Kind.GO, to = S.Failed::class)` does not. `.editorconfig` exempts
 * `*.tb.kt` from the formatter's wrapping and alignment rules so the columns
 * survive `ktlint --format`, which `kotlin-matrix-stable` checks on every run.
 */
package example.compose.connection

import dev.tabularcenter.CellSpec as C
import dev.tabularcenter.Kind.GO
import dev.tabularcenter.Kind.HANDLE
import dev.tabularcenter.Kind.IGNORE
import dev.tabularcenter.Machine
import dev.tabularcenter.Row
import dev.tabularcenter.Step
import example.compose.connection.A.Ready
import example.compose.connection.A.Retry
import example.compose.connection.A.Start
import example.compose.connection.F.Dial
import example.compose.connection.F.Hangup
import example.compose.connection.S.Connecting
import example.compose.connection.S.Failed
import example.compose.connection.S.Idle
import example.compose.connection.S.Live

@Machine(
    states = [Idle::class, Connecting::class, Live::class, Failed::class],
    actions = [Start::class, Ready::class, A.Drop::class, Retry::class],
    effects = [Dial::class, Hangup::class],
    initial = Idle::class,
)
//                       Start                                                Ready      Drop                                             Retry
@Row(Idle::class,       [C(GO, to = Connecting::class, emit = [Dial::class]), C(IGNORE), C(IGNORE),                                       C(IGNORE)])
@Row(Connecting::class, [C(IGNORE),                                           C(HANDLE), C(GO, to = Failed::class),                       C(IGNORE)])
@Row(Live::class,       [C(IGNORE),                                           C(IGNORE), C(GO, to = Idle::class, emit = [Hangup::class]), C(IGNORE)])
@Row(Failed::class,     [C(IGNORE),                                           C(IGNORE), C(IGNORE),                                       C(GO, to = Connecting::class, emit = [Dial::class])])
interface ConnectionSpec {
    fun handle(ctx: Ctx, state: S, action: A): Step<S, F>
}
