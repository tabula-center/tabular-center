//~ EXPECT: tabular-center::unknown-child
//
// A DELEGATE cell naming something that is not a machine.
//
// A parent declares one thing about its child -- the class -- and the
// processor reads the rest from it: package, alias, types, context. That only
// works if the class carries `@Machine`, so this is the diagnostic standing
// where the assumption is. It is also what a child from a PREBUILT module
// looks like from here: `@Machine` is `SOURCE`-retention, so nothing is left
// to read, and the message says so rather than leaving a reader to discover
// it.
package fixtures.unknownchild

import dev.tabula.CellSpec
import dev.tabula.Kind
import dev.tabula.Machine
import dev.tabula.Row
import dev.tabula.Step

@Machine(
    states = [S.Idle::class, S.Busy::class],
    actions = [A.Go::class],
    effects = [F.Note::class],
    initial = S.Idle::class,
)
//                       Go
@Row(S.Idle::class,    [CellSpec(Kind.GO, to = S.Busy::class)])
@Row(S.Busy::class,    [CellSpec(Kind.DELEGATE, child = NotAMachine::class)])
interface ParentSpec {
    fun handle(ctx: Ctx, state: S, action: A): Step<S, F>
}
