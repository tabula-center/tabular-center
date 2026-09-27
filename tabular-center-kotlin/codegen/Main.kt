package codegen

import java.io.File

/**
 * Emits the reference machines for `tools/verify` to compile.
 *
 * Generated code is never committed -- not as source, not as a golden. What
 * a golden diff proved, something else proves here, from source alone:
 *
 * - **That the output is Kotlin, and still enforces the guarantee.**
 *   `tools/verify kotlin-codegen` compiles every emitted machine, a complete
 *   implementation against it, and deliberately incomplete ones that must be
 *   refused. That was always the half that mattered; a golden only ever
 *   proved the characters had not moved.
 * - **That emission is deterministic.** Checked below, by emitting twice.
 * - **That KSP extracts what the annotations say.** [kspTwins] states, by
 *   hand, the description each example machine should extract to;
 *   `tools/verify kotlin-ksp` emits those and diffs them against what KSP just
 *   generated. Both sides are produced at check time. This is what
 *   `tabular-center-kotlin/ksp/golden/` did, with the expected side as reviewable source
 *   instead of committed output.
 *
 * Writes nothing unless given `--emit=<dir>`.
 */

/** `timer.tbl`, as the KSP processor would build it from annotations. */
val timerDesc = MachineDesc(
    packageName = "generated.timer",
    machine = "Timer",
    stateType = "S",
    actionType = "A",
    effectType = "F",
    ctxType = "Ctx",
    initial = "Idle",
    prototypeModifiers = listOf("suspend"),
    states = listOf(
        Variant("Idle"),
        Variant("Running", hasPayload = true, fields = listOf("since" to "Long")),
        Variant("Done"),
    ),
    actions = listOf(
        Variant("Start"),
        Variant("Tick", hasPayload = true, fields = listOf("now" to "Long")),
        Variant("Cancel"),
    ),
    effects = listOf(
        Variant("StartClock"),
        Variant("StopClock"),
        // Carries a payload, and a static cell emits it below: the generated
        // arm writes the constructor call, `TABLE` records the name.
        Variant("Halt", hasPayload = true, fields = listOf("reason" to "String")),
    ),
    rows = listOf(
        listOf(CellDesc.Handle, CellDesc.Ignore, CellDesc.Ignore),
        listOf(
            CellDesc.Ignore,
            CellDesc.Handle,
            CellDesc.Go("Idle", effects = listOf("StopClock", """Halt(reason = "cancelled")""")),
        ),
        listOf(
            CellDesc.Go("Running", "(0)", listOf("StartClock")),
            CellDesc.Ignore,
            CellDesc.Ignore,
        ),
    ),
)

/** `toggle.tbl` — the only coverage for EMIT and UNREACHABLE. */
val toggleDesc = MachineDesc(
    packageName = "generated.toggle",
    machine = "Toggle",
    stateType = "S",
    actionType = "A",
    effectType = "F",
    ctxType = "Ctx",
    initial = "Off",
    states = listOf(Variant("Off"), Variant("On")),
    actions = listOf(Variant("Flip"), Variant("Poke"), Variant("Reset")),
    effects = listOf(Variant("Light"), Variant("Buzz")),
    rows = listOf(
        listOf(CellDesc.Go("On", effects = listOf("Light")), CellDesc.Emit(listOf("Buzz")), CellDesc.Ignore),
        listOf(CellDesc.Go("Off"), CellDesc.Handle, CellDesc.Unreachable),
    ),
)

/**
 * A receiver-colored, internal machine: the two prototype properties the other
 * two leave at their defaults. The same machine as
 * `tabular-center-kotlin/examples/06-generated/src/Stopwatch.tb.kt`, so it doubles as that
 * machine's KSP twin in [kspTwins] -- the processor's extraction and this
 * hand-built description must emit the same characters.
 */
val stopwatchDesc = MachineDesc(
    packageName = "generated.stopwatch",
    machine = "Stopwatch",
    stateType = "S",
    actionType = "A",
    effectType = "F",
    ctxType = "Ctx",
    initial = "Idle",
    prototypeReceiver = "generated.stopwatch.Clock",
    visibility = "internal",
    states = listOf(
        Variant("Idle"),
        Variant("Running", hasPayload = true, fields = listOf("since" to "Long")),
    ),
    actions = listOf(Variant("Start"), Variant("Stop")),
    effects = listOf(Variant("Beep")),
    rows = listOf(
        listOf(CellDesc.Handle, CellDesc.Ignore),
        listOf(CellDesc.Ignore, CellDesc.Handle),
    ),
)

/**
 * The child in `test/Composition.kt`: a retry machine, written knowing nothing
 * about any parent.
 *
 * In an ordinary nested package, and reached by its parent through
 * [ChildDesc.packageName]. Until the audit the emitter reached a child
 * through its alias, so this had to be a root package called `retry`.
 */
fun retryDesc(pkg: String, mods: List<String> = emptyList()) = MachineDesc(
    packageName = pkg,
    machine = "Retry",
    stateType = "S",
    actionType = "A",
    effectType = "F",
    ctxType = "Ctx",
    initial = "Ready",
    states = listOf(
        Variant("Ready"),
        Variant("Waiting", hasPayload = true, fields = listOf("attempt" to "Int")),
        Variant("Exhausted"),
    ),
    actions = listOf(Variant("Attempt"), Variant("Elapsed"), Variant("Abort")),
    effects = listOf(Variant("Sleep"), Variant("GiveUp")),
    rows = listOf(
        listOf(CellDesc.Handle, CellDesc.Ignore, CellDesc.Go("Exhausted")),
        listOf(CellDesc.Ignore, CellDesc.Handle, CellDesc.Go("Exhausted")),
        listOf(CellDesc.Ignore, CellDesc.Ignore, CellDesc.Ignore),
    ),
    prototypeModifiers = mods,
)

/**
 * The parent: its `Retrying` state holds the child's state, and two of its
 * cells delegate to the child.
 */
fun jobDesc(
    pkg: String,
    child: String,
    mods: List<String> = emptyList(),
    // How the child's state type is spelled in the parent's payload. KSP reads
    // a field's type as its SIMPLE name, so the twin says `S` where the
    // hand-built description says `generated.retry.S`. It feeds
    // `tabular-center::payload-hoist` and nothing else.
    childField: String = "generated.$child.S",
) = MachineDesc(
    packageName = pkg,
    machine = "Job",
    stateType = "S",
    actionType = "A",
    effectType = "F",
    ctxType = "Ctx",
    initial = "Idle",
    states = listOf(
        Variant("Idle"),
        Variant("Retrying", hasPayload = true, fields = listOf("child" to childField)),
        Variant("Done"),
    ),
    actions = listOf(Variant("Run"), Variant("Tick"), Variant("Cancel")),
    effects = listOf(Variant("Log")),
    rows = listOf(
        listOf(CellDesc.Handle, CellDesc.Ignore, CellDesc.Ignore),
        listOf(CellDesc.Delegate(child), CellDesc.Delegate(child), CellDesc.Go("Done", effects = listOf("Log"))),
        listOf(CellDesc.Ignore, CellDesc.Ignore, CellDesc.Ignore),
    ),
    prototypeModifiers = mods,
    children = listOf(ChildDesc(child, "generated.$child", "S", "A", "F", "Ctx")),
)

/**
 * Every machine whose emitted source must compile. Composition was emitted
 * by `Emit.kt` from the start and never compiled: nothing built a
 * [ChildDesc], here or in the KSP processor. These four are what compile it.
 */
private val all = mapOf(
    "timer" to timerDesc,
    "toggle" to toggleDesc,
    "stopwatch" to stopwatchDesc,
    "retry" to retryDesc("generated.retry"),
    "retrysuspend" to retryDesc("generated.retrysuspend", listOf("suspend")),
    "job" to jobDesc("generated.job", "retry"),
    // A colorless child in a colored parent: allowed, and compiled.
    "jobsuspend" to jobDesc("generated.jobsuspend", "retry", listOf("suspend")),
)

/**
 * Machines whose emitted source must NOT compile. Written apart, to
 * `refused/`, so `tools/verify` compiles each only with the fixture that
 * names it. A colored child in a colorless parent: color flows one way, and
 * the generated `delegateTo<Child>` carries the parent's color, so kotlinc
 * refuses the child's `suspend` `step` from a plain function.
 */
private val refused = mapOf(
    "jobmixed" to jobDesc("generated.jobmixed", "retrysuspend"),
)

/**
 * What the KSP processor must extract from each machine in
 * `tabular-center-kotlin/examples/06-generated/src`, keyed by the file KSP writes.
 *
 * Stated by hand, deliberately. Extraction is the one step between the
 * annotations and `emit` that nothing else checks: the example compiling
 * proves `Cells` has members `Impl.kt` can override and that `step`
 * type-checks, and nothing about the table. Rows read in the wrong order, an
 * effect dropped from a GO cell, `initial` resolved to the wrong state -- all
 * compile, and `TABLE` is inert data the example never reads.
 *
 * So if `tools/verify kotlin-ksp` reports a diff, the question is which side
 * is wrong. A diff in `TABLE`, `PAYLOADS` or member order is the extraction
 * path drifting -- the failure this exists to catch. Change a twin only when
 * the annotations it restates changed.
 */
val kspTwins: Map<String, MachineDesc> = mapOf(
    "TurnstileGenerated" to MachineDesc(
        packageName = "generated.turnstile",
        machine = "Turnstile",
        stateType = "S",
        actionType = "A",
        effectType = "F",
        ctxType = "Ctx",
        initial = "Locked",
        states = listOf(Variant("Locked"), Variant("Unlocked")),
        actions = listOf(Variant("Coin"), Variant("Push")),
        effects = listOf(Variant("Click")),
        rows = listOf(
            listOf(CellDesc.Go("Unlocked", effects = listOf("Click")), CellDesc.Ignore),
            listOf(CellDesc.Ignore, CellDesc.Handle),
        ),
    ),
    // The machine that proves prototype modifiers are COPIED, not enumerated.
    "GateGenerated" to MachineDesc(
        packageName = "generated.gate",
        machine = "Gate",
        stateType = "S",
        actionType = "A",
        effectType = "F",
        ctxType = "Ctx",
        initial = "Closed",
        states = listOf(Variant("Closed"), Variant("Opening"), Variant("Open")),
        actions = listOf(Variant("Request"), Variant("Arrived")),
        effects = listOf(Variant("Chime", hasPayload = true, fields = listOf("volume" to "Int"))),
        rows = listOf(
            listOf(CellDesc.Handle, CellDesc.Ignore),
            listOf(CellDesc.Ignore, CellDesc.Go("Open", effects = listOf("Chime(volume = 3)"))),
            listOf(CellDesc.Go("Closed"), CellDesc.Ignore),
        ),
        prototypeModifiers = listOf("suspend"),
    ),
    // Through `buildDesc`, as the processor goes: the spine's HANDLEs become
    // GOs there, and the twin must restate the annotations, not the result.
    "SpineGenerated" to buildDesc(
        RawMachine(
            packageName = "generated.spine",
            machine = "Spine",
            stateType = "S",
            actionType = "A",
            effectType = "F",
            ctxType = "Ctx",
            initial = "Idle",
            states = listOf(RawVariant("Idle"), RawVariant("Connecting"), RawVariant("Live"), RawVariant("Failed")),
            actions = listOf(RawVariant("Start"), RawVariant("Ready"), RawVariant("Drop")),
            effects = emptyList(),
            rows = listOf(
                RawRow("Idle", listOf(RawCell("HANDLE"), RawCell("IGNORE"), RawCell("IGNORE"))),
                RawRow("Connecting", listOf(RawCell("IGNORE"), RawCell("HANDLE"), RawCell("GO", target = "Failed"))),
                RawRow("Live", listOf(RawCell("IGNORE"), RawCell("IGNORE"), RawCell("IGNORE"))),
                RawRow("Failed", listOf(RawCell("HANDLE"), RawCell("IGNORE"), RawCell("IGNORE"))),
            ),
            paths = listOf(RawPath("connect", listOf("Idle", "Start", "Connecting", "Ready", "Live"))),
        ),
    ),
    // The same machine as `stopwatchDesc`, reached through KSP: extension
    // receiver and `internal` included. One description, two front-ends.
    "StopwatchGenerated" to stopwatchDesc,
    // Composition through annotations: `Retry.tb.kt` and `Job.tb.kt` in the
    // KSP example declare the same two machines the compile stage above
    // builds by hand, so these twins are those descriptions. If the processor
    // resolves a child differently from `childrenOf`'s contract -- a wrong
    // package, an alias that is not the child's machine name -- the parent's
    // emitted source says so here.
    "RetryGenerated" to retryDesc("generated.retry"),
    "JobGenerated" to jobDesc("generated.job", "retry", childField = "S"),
)

fun main(args: Array<String>) {
    if (runValidationTests() > 0) kotlin.system.exitProcess(1)

    val machines = all + refused + kspTwins

    // Deterministic: the same description emits the same characters. What a
    // golden diff checked implicitly, minus the committed output.
    var failed = 0
    for ((name, desc) in machines) {
        if (emit(desc) == emit(desc)) {
            println("ok   $name emits deterministically")
        } else {
            println("FAIL $name: two emissions of one description differ")
            failed++
        }
    }

    // Emit into a scratch directory for the compile stages that follow, and
    // for kotlin-ksp's comparison. Never into the tree.
    val out = args.firstOrNull { it.startsWith("--emit=") }?.removePrefix("--emit=")
    if (out != null) {
        val dir = File(out).apply { mkdirs() }
        for ((name, desc) in all) File(dir, "$name.kt").writeText(emit(desc))
        val refusedDir = File(dir, "refused").apply { mkdirs() }
        for ((name, desc) in refused) File(refusedDir, "$name.kt").writeText(emit(desc))
        val twinsDir = File(dir, "ksp-twins").apply { mkdirs() }
        for ((name, desc) in kspTwins) File(twinsDir, "$name.kt").writeText(emit(desc))
    }

    if (failed > 0) kotlin.system.exitProcess(1)
}
