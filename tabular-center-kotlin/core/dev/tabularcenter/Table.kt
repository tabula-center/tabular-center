package dev.tabularcenter

/**
 * A machine's transition matrix, emitted alongside the dispatcher.
 *
 * Rows are states, columns are actions, both in declaration order — which is
 * what lets diagram export and the conformance runner agree on cell identity
 * across languages.
 */
data class Table(
    val machine: String,
    val states: List<String>,
    val actions: List<String>,
    val cells: List<List<Cell>>,
    val initial: String? = null,
) {
    /** The cell at `(stateIndex, actionIndex)`. */
    fun cell(state: Int, action: Int): Cell = cells[state][action]

    /** Row index of a state variant by name. */
    fun stateIndex(name: String): Int = states.indexOf(name)

    /** Column index of an action variant by name. */
    fun actionIndex(name: String): Int = actions.indexOf(name)

    /** Counts by cell kind. */
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

    /**
     * States no cell can statically transition into, excluding the initial one.
     *
     * Only static targets are knowable at build time, so a state reached solely
     * from a `HANDLE` cell appears here. That is why the reachability lint is
     * gated on [isFullyStatic].
     */
    fun staticallyUnreached(): List<String> =
        states.filter { s ->
            s != initial && cells.flatten().none { it.staticTarget == s }
        }

    /** Whether every cell is static, i.e. whether reachability is knowable. */
    fun isFullyStatic(): Boolean = cells.flatten().all { it.isStatic }
}

/** Counts by cell kind, for the build-time coverage report. */
data class Coverage(
    val ignore: Int,
    val go: Int,
    val emit: Int,
    val handle: Int,
    val delegate: Int,
    val unreachable: Int,
) {
    /** Total cells, i.e. states x actions. */
    val total: Int get() = ignore + go + emit + handle + delegate + unreachable

    /**
     * Cells the developer must implement.
     *
     * `unreachable` is excluded: writing `UNREACHABLE` *is* the implementation.
     */
    val requiredMembers: Int get() = handle + delegate

    /** Proportion of the matrix that is `IGNORE`, in percent. */
    val ignorePercent: Int get() = if (total == 0) 0 else ignore * 100 / total

    /** Proportion of the matrix that is `UNREACHABLE`, in percent. */
    val unreachablePercent: Int get() = if (total == 0) 0 else unreachable * 100 / total
}
