// `Table`, a machine's matrix as data, and `Coverage`, its counts by cell
// kind: what the generated `TABLE` constant is, and what every renderer and
// lint reads.
package center.tabula

/**
 * A machine's transition matrix, emitted alongside the dispatcher.
 *
 * Rows are states, columns are actions, both in declaration order — which is
 * what lets diagram export and the conformance runner agree on cell identity
 * across languages.
 *
 * - `cell`: The cell at `(stateIndex, actionIndex)`.
 * - `stateIndex`: Row index of a state variant by name.
 * - `actionIndex`: Column index of an action variant by name.
 * - `coverage`: Counts by cell kind.
 * - `staticallyUnreached`: States no cell can statically transition into, excluding the initial one.
 * - `isFullyStatic`: Whether every cell is static, i.e.
 */
data class Table(
    val machine: String,
    val states: List<String>,
    val actions: List<String>,
    val cells: List<List<Cell>>,
    val initial: String? = null,
) {
    fun cell(state: Int, action: Int): Cell = cells[state][action]

    fun stateIndex(name: String): Int = states.indexOf(name)

    fun actionIndex(name: String): Int = actions.indexOf(name)

    fun coverage(): Coverage {
        val flat = cells.flatten()
        return Coverage(
            ignore = flat.count { it is Cell.Ignore },
            go = flat.count { it is Cell.Go },
            emit = flat.count { it is Cell.Emit },
            handle = flat.count { it is Cell.Handle },
            delegate = flat.count { it is Cell.Delegate },
            unreachable = flat.count { it is Cell.Unreachable },
        )
    }

    fun staticallyUnreached(): List<String> =
        states.filter { s ->
            s != initial && cells.flatten().none { it.staticTarget == s }
        }

    fun isFullyStatic(): Boolean = cells.flatten().all { it.isStatic }
}

/**
 * Counts by cell kind, for the build-time coverage report.
 *
 * - `total`: Total cells, i.e.
 * - `requiredMembers`: Cells the developer must implement.
 * - `ignorePercent`: Proportion of the matrix that is `IGNORE`, in percent.
 * - `unreachablePercent`: Proportion of the matrix that is `UNREACHABLE`, in percent.
 */
data class Coverage(
    val ignore: Int,
    val go: Int,
    val emit: Int,
    val handle: Int,
    val delegate: Int,
    val unreachable: Int,
) {
    val total: Int get() = ignore + go + emit + handle + delegate + unreachable

    val requiredMembers: Int get() = handle + delegate

    val ignorePercent: Int get() = if (total == 0) 0 else ignore * 100 / total

    val unreachablePercent: Int get() = if (total == 0) 0 else unreachable * 100 / total
}
