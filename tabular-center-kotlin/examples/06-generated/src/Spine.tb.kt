// A machine with a happy path. See `spec/happy-paths.md`.
//
// The two cells on the spine are written `HANDLE` and the generator turns them
// into `GO`s -- that is the feature: on the happy path the common case stops
// being typed. `Failed`/`Start` is a HANDLE too and stays one, because no hop
// names it.
//
// The route ends at `Live`, which nothing can leave. A path that ends
// somewhere with a way out is `tabular-center::path-unterminated`.
package generated.spine

import dev.tabularcenter.CellSpec
import dev.tabularcenter.Kind
import dev.tabularcenter.Machine
import dev.tabularcenter.Path
import dev.tabularcenter.Row
import dev.tabularcenter.Step

@Machine(
    states = [S.Idle::class, S.Connecting::class, S.Live::class, S.Failed::class],
    actions = [A.Start::class, A.Ready::class, A.Drop::class],
    effects = [],
    initial = S.Idle::class,
)
@Path("connect", [S.Idle::class, A.Start::class, S.Connecting::class, A.Ready::class, S.Live::class])
//                           Start                    Ready                    Drop
@Row(S.Idle::class,        [CellSpec(Kind.HANDLE),  CellSpec(Kind.IGNORE),   CellSpec(Kind.IGNORE)])
@Row(S.Connecting::class,  [CellSpec(Kind.IGNORE),  CellSpec(Kind.HANDLE),   CellSpec(Kind.GO, to = S.Failed::class)])
@Row(S.Live::class,        [CellSpec(Kind.IGNORE),  CellSpec(Kind.IGNORE),   CellSpec(Kind.IGNORE)])
@Row(S.Failed::class,      [CellSpec(Kind.HANDLE),  CellSpec(Kind.IGNORE),   CellSpec(Kind.IGNORE)])
interface SpineSpec {
    fun handle(ctx: Ctx, state: S, action: A): Step<S, F>
}
