// Tests for the validation layer.
//
// Every diagnostic in `spec/diagnostics.md` that concerns the *declaration*
// has a case here, which is the point of [buildDesc] existing at all: these
// would otherwise live in the KSP processor, which cannot be tested without
// Maven.
package center.tabula.codegen

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
    } catch (e: TabularCenterError) {
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

    check(
        "receiver and visibility reach the description",
        buildDesc(raw().copy(prototypeReceiver = "x.Clock", visibility = "internal")).let {
            it.prototypeReceiver == "x.Clock" && it.visibility == "internal"
        },
    )

    expectError("row with too few cells", "tabular-center::row-arity") {
        buildDesc(raw(rows = listOf(
            RawRow("Idle", listOf(RawCell("HANDLE"))),
            RawRow("Running", listOf(RawCell("IGNORE"), RawCell("HANDLE"))),
        )))
    }

    expectError("a state with no row", "tabular-center::missing-row") {
        buildDesc(raw(rows = listOf(RawRow("Idle", listOf(RawCell("HANDLE"), RawCell("IGNORE"))))))
    }

    expectError("rows out of declaration order", "tabular-center::missing-row") {
        buildDesc(raw(rows = listOf(
            RawRow("Running", listOf(RawCell("IGNORE"), RawCell("HANDLE"))),
            RawRow("Idle", listOf(RawCell("HANDLE"), RawCell("IGNORE"))),
        )))
    }

    expectError("a row for an undeclared state", "tabular-center::extra-row") {
        buildDesc(raw(rows = listOf(
            RawRow("Idle", listOf(RawCell("HANDLE"), RawCell("IGNORE"))),
            RawRow("Running", listOf(RawCell("IGNORE"), RawCell("HANDLE"))),
            RawRow("Nope", listOf(RawCell("IGNORE"), RawCell("IGNORE"))),
        )))
    }

    expectError("GO to an undeclared state", "tabular-center::unknown-state") {
        buildDesc(raw(rows = listOf(
            RawRow("Idle", listOf(RawCell("GO", target = "Nope"), RawCell("IGNORE"))),
            RawRow("Running", listOf(RawCell("IGNORE"), RawCell("HANDLE"))),
        )))
    }

    expectError("GO to a payload state with no literal args", "tabular-center::go-target") {
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

    expectError("emitting an undeclared effect", "tabular-center::unknown-effect") {
        buildDesc(raw(rows = listOf(
            RawRow("Idle", listOf(RawCell("GO", target = "Idle", effects = listOf("Nope")), RawCell("IGNORE"))),
            RawRow("Running", listOf(RawCell("IGNORE"), RawCell("HANDLE"))),
        )))
    }

    expectError("EMIT with no effects", "tabular-center::empty-emit") {
        buildDesc(raw(rows = listOf(
            RawRow("Idle", listOf(RawCell("EMIT"), RawCell("IGNORE"))),
            RawRow("Running", listOf(RawCell("IGNORE"), RawCell("HANDLE"))),
        )))
    }

    expectError("DELEGATE to an undeclared child", "tabular-center::unknown-child") {
        buildDesc(raw(rows = listOf(
            RawRow("Idle", listOf(RawCell("DELEGATE", child = "retry"), RawCell("IGNORE"))),
            RawRow("Running", listOf(RawCell("IGNORE"), RawCell("HANDLE"))),
        )))
    }

    expectError("an unrecognised cell kind", "tabular-center::unknown-cell") {
        buildDesc(raw(rows = listOf(
            RawRow("Idle", listOf(RawCell("MAYBE"), RawCell("IGNORE"))),
            RawRow("Running", listOf(RawCell("IGNORE"), RawCell("HANDLE"))),
        )))
    }

    expectError("an undeclared initial state", "tabular-center::unknown-state") {
        buildDesc(raw(initial = "Nope"))
    }

    check(
        "buildDesc reproduces the timer description",
        emit(buildDesc(timerRaw)) == emit(timerDesc)
    )

    check(
        "a field in three states is flagged",
        center.tabula.payloadHoist(
            listOf(
                Triple("Connecting", "retryCount", "Int"),
                Triple("Backoff", "retryCount", "Int"),
                Triple("Backoff", "until", "Long"),
                Triple("Reconnecting", "retryCount", "Int"),
            )
        ).singleOrNull().let {
            it is center.tabula.Finding.PayloadHoist &&
                it.states == listOf("Connecting", "Backoff", "Reconnecting")
        }
    )
    check(
        "two states is a coincidence, not a pattern",
        center.tabula.payloadHoist(listOf(Triple("A", "n", "Int"), Triple("B", "n", "Int"))).isEmpty()
    )
    check(
        "the same name at different types is not the same field",
        center.tabula.payloadHoist(
            listOf(
                Triple("A", "count", "Int"),
                Triple("B", "count", "String"),
                Triple("C", "count", "Int"),
            )
        ).isEmpty()
    )

    runAdditiveTest()
    runRenderTests()
    runChildPackageTest()
    runEffectArgumentTest()
    runPathBackTest()

    if (failures == 0) println("ok   codegen validation ($checks checks)")
    else println("FAIL codegen validation ($failures of $checks checks failed)")
    return failures
}

private fun runAdditiveTest() {
    val quiet = listOf(RawCell("IGNORE"), RawCell("IGNORE"), RawCell("IGNORE"))
    fun conn(rows: List<RawRow>, paths: List<RawPath>) = raw(
        states = listOf(
            RawVariant("Idle"), RawVariant("Connecting"), RawVariant("Live"), RawVariant("Failed"),
        ),
        actions = listOf(RawVariant("Start"), RawVariant("Ready"), RawVariant("Drop")),
        rows = rows,
    ).copy(paths = paths)

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

    val bare = derived.copy(hops = emptyList())
    check("a spine-derived machine equals its longhand twin, hops aside", bare == longhand)
    check("... and emits byte-identical source, TABLE included", emit(bare) == emit(longhand))
    check("the path's two hops are recorded", derived.hops == listOf(HopDesc(0, 0, 1), HopDesc(1, 1, 2)))

    val out = emit(derived).lines()
    check("(Connecting, Ready) can end anywhere: a HANDLE is in its row", hopOutcomes(derived, derived.hops[1]) == listOf(0, 1, 2, 3))
    check(
        "... so its elvis takes every state but Live, and is not infix",
        "inline fun ConnectingReady.elvis(" in out &&
            "    Idle: (ConnectingReady.Idle) -> ConnectingReady.Live," in out &&
            "    Connecting: (ConnectingReady.Connecting) -> ConnectingReady.Live," in out &&
            "    Failed: (ConnectingReady.Failed) -> ConnectingReady.Live," in out &&
            out.none { it.startsWith("    Live: ") }
    )
    check("(Idle, Start) ends in Connecting or stays Idle", hopOutcomes(derived, derived.hops[0]) == listOf(0, 1))
    check("... one alternative, so infix", "inline infix fun IdleStart.elvis(" in out)
    check(
        "the member takes the action that arrived",
        "fun Cells.connectingReady(ctx: Ctx, state: S.Connecting, action: A): ConnectingReady {" in out
    )
    check(
        "a state the row cannot produce is unreachable, not an else",
        out.none { it.trim().startsWith("else") } &&
            "        is S.Live -> error(\"tabular-center: the `Idle` row cannot produce `Live`\")" in out
    )
    check("without the path, the same rows are a different machine", underived != longhand)
    check("a HANDLE no hop names is left alone", derived.rows[1][2] == CellDesc.Handle)
}

private fun runPathBackTest() {
    val states = listOf(
        RawVariant("Cart"), RawVariant("Addr"), RawVariant("Pay"), RawVariant("Done"),
    )
    val actions = listOf(RawVariant("Next"), RawVariant("Back"))

    fun machine(back: String, payBack: RawCell, doneBack: RawCell = RawCell("IGNORE")) = raw(
        states = states,
        actions = actions,
        rows = listOf(
            RawRow("Cart", listOf(RawCell("HANDLE"), RawCell("IGNORE"))),
            RawRow("Addr", listOf(RawCell("HANDLE"), RawCell("HANDLE"))),
            RawRow("Pay", listOf(RawCell("HANDLE"), payBack)),
            RawRow("Done", listOf(RawCell("IGNORE"), doneBack)),
        ),
        initial = "Cart",
    ).copy(
        paths = listOf(
            RawPath(
                "checkout",
                listOf("Cart", "Next", "Addr", "Next", "Pay", "Next", "Done"),
                back = back,
            ),
        ),
    )

    val derived = buildDesc(machine("Back", RawCell("HANDLE")))
    check("a hop's far side goes back one step", derived.rows[1][1] == CellDesc.Go("Cart"))
    check("and the next one goes back to the one before", derived.rows[2][1] == CellDesc.Go("Addr"))
    check("the forward direction still derives", derived.rows[0][0] == CellDesc.Go("Addr"))

    val ending = buildDesc(machine("Back", RawCell("HANDLE"), doneBack = RawCell("HANDLE")))
    check("the path's end may be left by its own back action", ending.rows[3][1] == CellDesc.Go("Pay"))

    val explicit = buildDesc(machine("Back", RawCell("GO", target = "Cart")))
    check("an explicit cell wins", explicit.rows[2][1] == CellDesc.Go("Cart"))

    val plain = buildDesc(machine("", RawCell("HANDLE")))
    check("no back action, no reverse derivation", plain.rows[1][1] == CellDesc.Handle)

    expectError("a path that can still be left", "tabular-center::path-unterminated") {
        buildDesc(machine("", RawCell("HANDLE"), doneBack = RawCell("HANDLE")))
    }

    expectError("a back action the machine does not declare", "tabular-center::path-unknown-state") {
        buildDesc(machine("Backwards", RawCell("HANDLE")))
    }
}

private fun runEffectArgumentTest() {
    val plain = listOf(RawVariant("Idle"), RawVariant("Running"))
    val out = emit(buildDesc(raw(
        states = plain,
        effects = listOf(RawVariant("StartClock"), RawVariant("Halt", hasPayload = true)),
        rows = listOf(
            RawRow("Idle", listOf(RawCell("GO", target = "Running", effects = listOf("""Halt(reason = "x")""")), RawCell("IGNORE"))),
            RawRow("Running", listOf(RawCell("IGNORE"), RawCell("HANDLE"))),
        ),
    )))
    check("the dispatcher constructs the effect", out.contains("""F.Halt(reason = "x")"""))
    check("TABLE records the name without arguments", out.contains("""Cell.Go("Running", listOf("Halt"))"""))

    expectError("an effect reference naming no declared effect", "tabular-center::unknown-effect") {
        buildDesc(raw(
            states = plain,
            rows = listOf(
                RawRow("Idle", listOf(RawCell("GO", target = "Running", effects = listOf("Nope(reason = 1)")), RawCell("IGNORE"))),
                RawRow("Running", listOf(RawCell("IGNORE"), RawCell("HANDLE"))),
            ),
        ))
    }
}

private fun runChildPackageTest() {
    val deep = "com.example.backoff"
    val parent = jobDesc("com.example.job", "retry").copy(
        children = listOf(ChildDesc("retry", deep, "S", "A", "F", "Ctx")),
    )
    val out = emit(parent)
    check("the parent refines the child's Cells through its package", out.contains("$deep.Cells"))
    check("the child's step is called through its package", out.contains("$deep.step("))
    check("the child's types are qualified by its package", out.contains("$deep.S"))
    check("members are still named from the alias", out.contains("fun retryChildState("))
    check(
        "the alias is never used as a package",
        !Regex("""(?<![.\w])retry\.""").containsMatchIn(out),
    )
}

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
    effects = listOf(
        RawVariant("StartClock"),
        RawVariant("StopClock"),
        RawVariant("Halt", hasPayload = true, fields = listOf("reason" to "String")),
    ),
    rows = listOf(
        RawRow("Idle", listOf(RawCell("HANDLE"), RawCell("IGNORE"), RawCell("IGNORE"))),
        RawRow("Running", listOf(
            RawCell("IGNORE"),
            RawCell("HANDLE"),
            RawCell("GO", target = "Idle", effects = listOf("StopClock", """Halt(reason = "cancelled")""")),
        )),
        RawRow("Done", listOf(
            RawCell("GO", target = "Running", targetArgs = "(0)", effects = listOf("StartClock")),
            RawCell("IGNORE"),
            RawCell("IGNORE"),
        )),
    ),
)

private fun runRenderTests() {
    val plain = buildDesc(raw())
    val rendered = buildDesc(raw().copy(render = RenderDesc(listOf("@Composable"))))
    val out = emit(rendered)

    check("the render prototype survives buildDesc", rendered.render == RenderDesc(listOf("@Composable")))
    check("without a render prototype nothing rendering-related is emitted", "Renders" !in emit(plain))
    check(
        "... and the rest of the output is untouched by one",
        emit(plain) == out.substringBefore("\n/**\n * The rendering surface") +
            out.substring(out.indexOf("\n/** The matrix as inert data."))
    )
    for (st in plain.states) {
        check(
            "a renderer for ${st.name}, narrowed, in the prototype's color",
            "    @Composable fun render${st.name}(state: S.${st.name}): Unit" in out
        )
        check("a dispatcher arm for ${st.name}", "    is S.${st.name} -> renders.render${st.name}(state)" in out)
    }
    check("the dispatcher carries the color too", "@Composable fun render(renders: Renders, state: S): Unit" in out)
    val dispatcher = out.substringAfter("fun render(renders: Renders").substringBefore("\n}")
    check("the dispatcher has no else branch", "else" !in dispatcher)
}
