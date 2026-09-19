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
    states: List<RawVariant> = listOf(RawVariant("Idle"), RawVariant("Running", hasPayload = true)),
    actions: List<RawVariant> = listOf(RawVariant("Start"), RawVariant("Tick")),
    effects: List<RawVariant> = listOf(RawVariant("Go")),
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

    // Carried, not interpreted: buildDesc owns no rule about either, and
    // dropping one here would emit a public, uncolored surface with no error.
    check(
        "receiver and visibility reach the description",
        buildDesc(raw().copy(prototypeReceiver = "x.Clock", visibility = "internal")).let {
            it.prototypeReceiver == "x.Clock" && it.visibility == "internal"
        },
    )

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

    // payload-hoist: rule R4, asked as a question.
    check(
        "a field in three states is flagged",
        dev.tabula.payloadHoist(
            listOf(
                Triple("Connecting", "retryCount", "Int"),
                Triple("Backoff", "retryCount", "Int"),
                Triple("Backoff", "until", "Long"),
                Triple("Reconnecting", "retryCount", "Int"),
            )
        ).singleOrNull().let {
            it is dev.tabula.Finding.PayloadHoist &&
                it.states == listOf("Connecting", "Backoff", "Reconnecting")
        }
    )
    check(
        "two states is a coincidence, not a pattern",
        dev.tabula.payloadHoist(listOf(Triple("A", "n", "Int"), Triple("B", "n", "Int"))).isEmpty()
    )
    check(
        "the same name at different types is not the same field",
        dev.tabula.payloadHoist(
            listOf(
                Triple("A", "count", "Int"),
                Triple("B", "count", "String"),
                Triple("C", "count", "Int"),
            )
        ).isEmpty()
    )

    runAdditiveTest()

    if (failures == 0) println("ok   codegen validation ($checks checks)")
    else println("FAIL codegen validation ($failures of $checks checks failed)")
    return failures
}

/**
 * The additive test from `spec/happy-paths.md`, checked rather than stated.
 *
 * A machine whose `HANDLE` cells are turned into `GO`s by a spine, and the same
 * machine with those `GO`s written out by hand, must be indistinguishable to
 * everything downstream. Comparing the whole [MachineDesc] and the whole emitted
 * file is stronger than comparing `TABLE` alone: `TABLE` is a literal inside
 * that file, and `.grid`, `.lint`, `.cov` and `.mmd` are pure functions of it,
 * so equal source means equal goldens.
 *
 * `Swift`'s twin is in `TabulaCodegenCheck/main.swift`, on the same machine.
 */
private fun runAdditiveTest() {
    val quiet = listOf(RawCell("IGNORE"), RawCell("IGNORE"), RawCell("IGNORE"))
    fun conn(rows: List<RawRow>, paths: List<RawPath>) = raw(
        states = listOf(
            RawVariant("Idle"), RawVariant("Connecting"), RawVariant("Live"), RawVariant("Failed"),
        ),
        actions = listOf(RawVariant("Start"), RawVariant("Ready"), RawVariant("Drop")),
        rows = rows,
    ).copy(paths = paths)

    // Idle -Start-> Connecting -Ready-> Live, and Live is terminal. Drop from
    // Connecting is a HANDLE the spine does not name, so it must survive.
    val connect = RawPath("connect", listOf("Idle", "Start", "Connecting", "Ready", "Live"))
    val spineRows = listOf(
        RawRow("Idle", listOf(RawCell("HANDLE"), RawCell("IGNORE"), RawCell("IGNORE"))),
        RawRow("Connecting", listOf(RawCell("IGNORE"), RawCell("HANDLE"), RawCell("HANDLE"))),
        RawRow("Live", quiet),
        RawRow("Failed", quiet),
    )
    val longhandRows = listOf(
        RawRow("Idle", listOf(RawCell("GO", target = "Connecting"), RawCell("IGNORE"), RawCell("IGNORE"))),
        RawRow("Connecting", listOf(RawCell("IGNORE"), RawCell("GO", target = "Live"), RawCell("HANDLE"))),
        RawRow("Live", quiet),
        RawRow("Failed", quiet),
    )

    val derived = buildDesc(conn(spineRows, listOf(connect)))
    val longhand = buildDesc(conn(longhandRows, emptyList()))
    val underived = buildDesc(conn(spineRows, emptyList()))

    check("a spine-derived machine equals its longhand twin", derived == longhand)
    check("... and emits byte-identical source, TABLE included", emit(derived) == emit(longhand))
    // The control. Without it, a `derive` that did nothing would still pass
    // the two checks above whenever the longhand twin was written wrong.
    check("without the path, the same rows are a different machine", underived != longhand)
    check("a HANDLE no hop names is left alone", derived.rows[1][2] == CellDesc.Handle)
}

/** `timerDesc`, as a KSP processor would hand it over. */
val timerRaw = RawMachine(
    packageName = "generated.timer",
    machine = "Timer",
    stateType = "S", actionType = "A", effectType = "F", ctxType = "Ctx",
    initial = "Idle",
    prototypeModifiers = listOf("suspend"),
    states = listOf(
        RawVariant("Idle"),
        RawVariant("Running", hasPayload = true, fields = listOf("since" to "Long")),
        RawVariant("Done"),
    ),
    actions = listOf(
        RawVariant("Start"),
        RawVariant("Tick", hasPayload = true, fields = listOf("now" to "Long")),
        RawVariant("Cancel"),
    ),
    effects = listOf(RawVariant("StartClock"), RawVariant("StopClock")),
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
