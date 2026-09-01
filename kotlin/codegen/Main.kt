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
    states = listOf(Variant("Idle"), Variant("Running", hasPayload = true), Variant("Done")),
    actions = listOf(Variant("Start"), Variant("Tick", hasPayload = true), Variant("Cancel")),
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

private val all = mapOf("timer" to timerDesc, "toggle" to toggleDesc)

fun main(args: Array<String>) {
    if (runValidationTests() > 0) kotlin.system.exitProcess(1)

    val bless = args.contains("--bless")
    val dir = File(args.firstOrNull { !it.startsWith("--") } ?: "codegen/golden")
    dir.mkdirs()

    var failed = 0
    for ((name, desc) in all) {
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
    }

    if (failed > 0) kotlin.system.exitProcess(1)
}
