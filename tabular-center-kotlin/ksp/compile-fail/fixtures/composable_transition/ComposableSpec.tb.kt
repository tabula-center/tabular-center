//~ EXPECT: tabular-center::composable-transition
//~ BUILDS
//~ AT: @Composable fun handle
//
// `@Composable` on the TRANSITION prototype: generated as declared, and warned
// about. The one KSP fixture that must build -- `//~ BUILDS` -- because the
// diagnostic is a warning; see spec/diagnostics.md.
//
// It proves a second thing by building at all. The warning's advice is sound
// only if a `@Composable` prototype generates code that compiles, and it did
// not: the processor copied `handle`'s annotations by short name into a file
// that imports only `dev.tabularcenter`, so `@Composable` could not resolve
// there. Copied qualified since Phase 9b, the generated cells below carry
// `@androidx.compose.runtime.Composable` and compile against the stub beside
// this file.
//
// `.tb.kt` because the rows are column-aligned. See `spec/matrix-files.md`.
package fixtures.composabletransition

import androidx.compose.runtime.Composable
import dev.tabularcenter.CellSpec
import dev.tabularcenter.Kind
import dev.tabularcenter.Machine
import dev.tabularcenter.Row
import dev.tabularcenter.Step

@Machine(
    states = [S.Idle::class, S.Busy::class],
    actions = [A.Start::class, A.Stop::class],
    effects = [],
    initial = S.Idle::class,
)
//                    Start                    Stop
@Row(S.Idle::class, [CellSpec(Kind.HANDLE),  CellSpec(Kind.IGNORE)])
@Row(S.Busy::class, [CellSpec(Kind.IGNORE),  CellSpec(Kind.HANDLE)])
interface ComposableSpec {
    @Composable fun handle(ctx: Ctx, state: S, action: A): Step<S, F>
}
