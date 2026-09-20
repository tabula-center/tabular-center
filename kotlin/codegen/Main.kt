package codegen

import java.io.File

/**
 * Emits the reference machines and checks them against committed golden files.
 *
 * `--bless` rewrites the goldens after an intended change.
 *
 * The golden diff is only half the test. `tools/verify kotlin-codegen` then
 * **compiles** the emitted source, and compiles a deliberately incomplete
 * implementation against it, so what is verified is not "the emitter produces
 * the expected characters" but "the emitter produces valid Kotlin that still
 * enforces the guarantee".
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
    effects = listOf(Variant("StartClock"), Variant("StopClock")),
    rows = listOf(
        listOf(CellDesc.Handle, CellDesc.Ignore, CellDesc.Ignore),
        listOf(CellDesc.Ignore, CellDesc.Handle, CellDesc.Go("Idle", effects = listOf("StopClock"))),
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
 * `examples/kotlin/06-generated/src/Stopwatch.tb.kt`, so this golden and
 * `ksp/golden/StopwatchGenerated.kt.golden` are byte-identical -- the
 * processor's extraction and this hand-built description must agree.
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
 * Its package is a ROOT package named like the alias a parent delegates
 * through, because the emitter reaches a child as `<alias>.Cells` and
 * `<alias>.step` -- fully qualified names, with no import. So the alias is
 * both an identifier and a package, and `retry` has to be both.
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
fun jobDesc(pkg: String, child: String, mods: List<String> = emptyList()) = MachineDesc(
    packageName = pkg,
    machine = "Job",
    stateType = "S",
    actionType = "A",
    effectType = "F",
    ctxType = "Ctx",
    initial = "Idle",
    states = listOf(
        Variant("Idle"),
        Variant("Retrying", hasPayload = true, fields = listOf("child" to "$child.S")),
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
    children = listOf(ChildDesc(child, child, "S", "A", "F", "Ctx")),
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
    "retry" to retryDesc("retry"),
    "retrysuspend" to retryDesc("retrysuspend", listOf("suspend")),
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

fun main(args: Array<String>) {
    if (runValidationTests() > 0) kotlin.system.exitProcess(1)

    val bless = args.contains("--bless")
    val dir = File(args.firstOrNull { !it.startsWith("--") } ?: "codegen/golden")
    dir.mkdirs()

    var failed = 0
    for ((name, desc) in all + refused) {
        val got = emit(desc)
        val golden = File(dir, "$name.kt.golden")
        if (bless) {
            golden.writeText(got)
            println("blessed $name")
            continue
        }
        if (!golden.exists()) {
            println("FAIL $name: no golden at ${golden.path}; run with --bless")
            failed++
            continue
        }
        val want = golden.readText()
        if (got == want) {
            println("ok   $name")
        } else {
            println("FAIL $name: emitted source differs from ${golden.path}")
            got.lines().zip(want.lines()).forEachIndexed { n, (g, w) ->
                if (g != w) {
                    println("       line $n: got    |$g|")
                    println("       line $n: golden |$w|")
                }
            }
            failed++
        }
    }

    // Emit into a scratch directory for the compile step that follows.
    val outDir = File(args.firstOrNull { it.startsWith("--emit=") }?.removePrefix("--emit=") ?: "")
    if (outDir.path.isNotEmpty()) {
        outDir.mkdirs()
        for ((name, desc) in all) File(outDir, "$name.kt").writeText(emit(desc))
        val refusedDir = File(outDir, "refused").apply { mkdirs() }
        for ((name, desc) in refused) File(refusedDir, "$name.kt").writeText(emit(desc))
    }

    if (failed > 0) kotlin.system.exitProcess(1)
}
