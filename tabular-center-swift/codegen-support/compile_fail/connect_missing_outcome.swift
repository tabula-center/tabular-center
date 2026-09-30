//~ EXPECT: missing argument for parameter 'failed'
//
// The narrowed surface has the matrix's guarantee: every state the
// `Connecting` row can produce, other than the happy one, is a required
// label of `elvis`. Forgetting `failed:` does not compile. The Kotlin twin is
// `tabular-center-kotlin/codegen/compile_fail/connect_missing_outcome.kt`.
import TabularCenter

func forgetful(_ cells: ConnectCells, _ ctx: Connect.Ctx, _ arrived: Connect.A) throws -> [Connect.F] {
    try Connect.connectingReady(cells, ctx, arrived).elvis(
        idle: { effects in effects },
        connecting: { effects in effects }
    )
}
