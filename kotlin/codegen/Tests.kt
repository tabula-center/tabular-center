package codegen

/**
 * Tests for the validation layer.
 *
 * Every diagnostic in `spec/diagnostics.md` that concerns the *declaration*
 * has a case here, which is the point of [buildDesc] existing at all: these
 * would otherwise live in the KSP processor, which cannot be tested without
 * Maven.
 */

private var failures = 0
private var checks = 0

private fun check(what: String, cond: Boolean) {
    checks++
    if (!cond) {
        failures++
        println("FAIL $what")
    }
}

private fun expectError(what: String, code: String, body: () -> Unit) {
    checks++
    try {
        body()
        failures++
        println("FAIL $what: expected $code, got no error")
    } catch (e: TabulaError) {
        if (e.code != code) {
            failures++
            println("FAIL $what: expected $code, got ${e.code}")
            println("       ${e.message}")
        }
    }
}

private fun raw(
    states: List<Pair<String, Boolean>> = listOf("Idle" to false, "Running" to true),
    actions: List<Pair<String, Boolean>> = listOf("Start" to false, "Tick" to false),
    effects: List<Pair<String, Boolean>> = listOf("Go" to false),
    rows: List<RawRow> = listOf(
        RawRow("Idle", listOf(RawCell("HANDLE"), RawCell("IGNORE"))),
        RawRow("Running", listOf(RawCell("IGNORE"), RawCell("HANDLE"))),
    ),
    initial: String = "Idle",
    children: List<ChildDesc> = emptyList(),
) = RawMachine(
    packageName = "t", machine = "T", stateType = "S", actionType = "A",
    effectType = "F", ctxType = "Ctx", initial = initial,
    states = states, actions = actions, effects = effects, rows = rows, children = children,
)

fun runValidationTests(): Int {
    check("a well-formed machine builds", buildDesc(raw()).rows.size == 2)

    expectError("row with too few cells", "tabula::row-arity") {
        buildDesc(raw(rows = listOf(
            RawRow("Idle", listOf(RawCell("HANDLE"))),
            RawRow("Running", listOf(RawCell("IGNORE"), RawCell("HANDLE"))),
        )))
    }

    expectError("a state with no row", "tabula::missing-row") {
        buildDesc(raw(rows = listOf(RawRow("Idle", listOf(RawCell("HANDLE"), RawCell("IGNORE"))))))
    }

    expectError("rows out of declaration order", "tabula::missing-row") {
        buildDesc(raw(rows = listOf(
            RawRow("Running", listOf(RawCell("IGNORE"), RawCell("HANDLE"))),
            RawRow("Idle", listOf(RawCell("HANDLE"), RawCell("IGNORE"))),
        )))
    }

    expectError("a row for an undeclared state", "tabula::extra-row") {
        buildDesc(raw(rows = listOf(
            RawRow("Idle", listOf(RawCell("HANDLE"), RawCell("IGNORE"))),
            RawRow("Running", listOf(RawCell("IGNORE"), RawCell("HANDLE"))),
            RawRow("Nope", listOf(RawCell("IGNORE"), RawCell("IGNORE"))),
        )))
    }

    expectError("GO to an undeclared state", "tabula::unknown-state") {
        buildDesc(raw(rows = listOf(
            RawRow("Idle", listOf(RawCell("GO", target = "Nope"), RawCell("IGNORE"))),
            RawRow("Running", listOf(RawCell("IGNORE"), RawCell("HANDLE"))),
        )))
    }

    // Rule R3: a GO cell is resolved entirely by the generator, so its target
    // must be constructible without developer code.
    expectError("GO to a payload state with no literal args", "tabula::go-target") {
        buildDesc(raw(rows = listOf(
            RawRow("Idle", listOf(RawCell("GO", target = "Running"), RawCell("IGNORE"))),
            RawRow("Running", listOf(RawCell("IGNORE"), RawCell("HANDLE"))),
        )))
    }

    check(
        "GO to a payload state WITH literal args is fine",
        buildDesc(raw(rows = listOf(
            RawRow("Idle", listOf(RawCell("GO", target = "Running", targetArgs = "(0)"), RawCell("IGNORE"))),
            RawRow("Running", listOf(RawCell("IGNORE"), RawCell("HANDLE"))),
        ))).rows[0][0] is CellDesc.Go
    )

    expectError("emitting an undeclared effect", "tabula::unknown-effect") {
        buildDesc(raw(rows = listOf(
            RawRow("Idle", listOf(RawCell("GO", target = "Idle", effects = listOf("Nope")), RawCell("IGNORE"))),
            RawRow("Running", listOf(RawCell("IGNORE"), RawCell("HANDLE"))),
        )))
    }

    expectError("EMIT with no effects", "tabula::empty-emit") {
        buildDesc(raw(rows = listOf(
            RawRow("Idle", listOf(RawCell("EMIT"), RawCell("IGNORE"))),
            RawRow("Running", listOf(RawCell("IGNORE"), RawCell("HANDLE"))),
        )))
    }

    expectError("DELEGATE to an undeclared child", "tabula::unknown-child") {
        buildDesc(raw(rows = listOf(
            RawRow("Idle", listOf(RawCell("DELEGATE", child = "retry"), RawCell("IGNORE"))),
            RawRow("Running", listOf(RawCell("IGNORE"), RawCell("HANDLE"))),
        )))
    }

    expectError("an unrecognised cell kind", "tabula::unknown-cell") {
        buildDesc(raw(rows = listOf(
            RawRow("Idle", listOf(RawCell("MAYBE"), RawCell("IGNORE"))),
            RawRow("Running", listOf(RawCell("IGNORE"), RawCell("HANDLE"))),
        )))
    }

    expectError("an undeclared initial state", "tabula::unknown-state") {
        buildDesc(raw(initial = "Nope"))
    }

    // The processor's whole job is to produce a RawMachine; this is the proof
    // that a correct one round-trips to the same source the goldens hold.
    check(
        "buildDesc reproduces the timer description",
        emit(buildDesc(timerRaw)) == emit(timerDesc)
    )

    if (failures == 0) println("ok   codegen validation ($checks checks)")
    else println("FAIL codegen validation ($failures of $checks checks failed)")
    return failures
}

/** `timerDesc`, as a KSP processor would hand it over. */
val timerRaw = RawMachine(
    packageName = "generated.timer",
    machine = "Timer",
    stateType = "S", actionType = "A", effectType = "F", ctxType = "Ctx",
    initial = "Idle",
    prototypeModifiers = listOf("suspend"),
    states = listOf("Idle" to false, "Running" to true, "Done" to false),
    actions = listOf("Start" to false, "Tick" to true, "Cancel" to false),
    effects = listOf("StartClock" to false, "StopClock" to false),
    rows = listOf(
        RawRow("Idle", listOf(RawCell("HANDLE"), RawCell("IGNORE"), RawCell("IGNORE"))),
        RawRow("Running", listOf(
            RawCell("IGNORE"),
            RawCell("HANDLE"),
            RawCell("GO", target = "Idle", effects = listOf("StopClock")),
        )),
        RawRow("Done", listOf(
            RawCell("GO", target = "Running", targetArgs = "(0)", effects = listOf("StartClock")),
            RawCell("IGNORE"),
            RawCell("IGNORE"),
        )),
    ),
)
