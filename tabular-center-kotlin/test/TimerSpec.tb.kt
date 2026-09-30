/**
 * The reference machine's matrix, and nothing else.
 *
 * Split out of `ReferenceTimer.kt` per `spec/matrix-files.md`. The rule there
 * is that a matrix earns its own file because a matrix is column-aligned on
 * purpose and a general-purpose formatter exists to collapse exactly that
 * padding. `.editorconfig` disables `no-multi-spaces`, `annotation`,
 * `argument-list-wrapping` and `indent` for `[*.tb.kt]` — a narrow exemption
 * for a narrow problem, which only works if the matrix is actually in such a
 * file.
 *
 * It was not, until now: `kotlin-matrix-stable` is gated on ktlint being
 * present and on `has.kotlin`, and both were false everywhere, so the check
 * that guards this had never executed. That is the second half of the same
 * finding — a guard nothing runs protects nothing.
 *
 * This file holds the declaration and the prototype. Nothing here wants
 * formatting, which is the test `spec/matrix-files.md` sets for what belongs
 * in a `.tb.` file: the handler bodies stay in `ReferenceTimer.kt` and are
 * formatted normally.
 */
package reference

import dev.tabularcenter.CellSpec
import dev.tabularcenter.Kind
import dev.tabularcenter.Machine
import dev.tabularcenter.Row
import dev.tabularcenter.Step

@Machine(
    states = [S.Idle::class, S.Running::class, S.Done::class],
    actions = [A.Start::class, A.Tick::class, A.Cancel::class],
    effects = [F.StartClock::class, F.StopClock::class],
    initial = S.Idle::class,
)
//                       Start                                                                   Tick                     Cancel
@Row(S.Idle::class,    [CellSpec(Kind.HANDLE),                                                  CellSpec(Kind.IGNORE),   CellSpec(Kind.IGNORE)])
@Row(S.Running::class, [CellSpec(Kind.IGNORE),                                                  CellSpec(Kind.HANDLE),   CellSpec(Kind.GO, to = S.Idle::class, emit = [F.StopClock::class])])
@Row(S.Done::class,    [CellSpec(Kind.GO, to = S.Running::class, emit = [F.StartClock::class]), CellSpec(Kind.IGNORE),   CellSpec(Kind.IGNORE)])
interface TimerSpec {
    /**
     * The prototype. Whatever modifiers appear here are copied onto every
     * generated cell member — `suspend` below, but equally a context receiver,
     * an annotation, or anything a future Kotlin version ships. The library
     * never enumerates colors; it copies.
     */
    suspend fun handle(ctx: Ctx, state: S, action: A): Step<S, F>
}
