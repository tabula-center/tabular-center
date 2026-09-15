package conformance

import dev.tabula.Export
import dev.tabula.testing.*
import dev.tabula.report
import java.io.File

/**
 * Runs the shared `spec/conformance` fixtures against the Kotlin
 * implementation.
 *
 * Three things are compared, and the third is the one that only exists because
 * there are now two implementations:
 *
 * 1. **Table** — the generated matrix, cell by cell.
 * 2. **Traces** — outcomes and effects, step by step.
 * 3. **Golden grid** — byte for byte against the same `.grid` file the Rust
 *    harness writes. Two renderers that disagree by a space would otherwise
 *    drift silently until someone diffed a snapshot by hand.
 */
fun main(args: Array<String>) {
    val root = File(args.getOrElse(0) { "../spec/conformance" })
    if (!root.isDirectory) {
        System.err.println("no spec/conformance at ${root.absolutePath}")
        kotlin.system.exitProcess(2)
    }

    var failed = 0
    var steps = 0

    for (adapter in adapters) {
        val name = adapter.name
        val errs = mutableListOf<String>()

        val spec = try {
            parseSpec(File(root, "$name.tbl").readText(), "$name.tbl")
        } catch (e: Exception) {
            println("FAIL $name: ${e.message}")
            failed++
            continue
        }
        val traces = parseTraces(File(root, "traces/$name.trace").readText(), "$name.trace")

        errs += checkTable(adapter.table, spec)
        errs += checkGolden(root, name, "grid", Export.toGrid(adapter.table))
        // The lints carry the most per-language logic there is -- thresholds,
        // the dead-row/no-static-exit subsumption, the fully-static gate on
        // reachability -- and nothing compared them across languages until now.
        errs += checkGolden(root, name, "mmd", Export.toMermaid(adapter.table))
        errs += checkGolden(root, name, "lint", report(adapter.table, adapter.payloads))
        // The diagram. Two renderers agreeing on edge ORDER, not just on the
        // edge set -- which is the thing that had already drifted.
        errs += checkGolden(root, name, "cov", Export.toCoverageReport(adapter.table))

        for (t in traces) {
            steps += t.steps.size
            val observed = try {
                adapter.replay(t)
            } catch (e: Exception) {
                errs.add("${t.name}: ${e.message}")
                continue
            }
            t.steps.zip(observed).forEachIndexed { i, (want, got) ->
                val at = "${t.name}[$i] ${want.action}"
                if (want.expect != got.expect) {
                    errs.add("$at: got `${got.expect}`, want `${want.expect}`")
                }
                val gotEff = got.effects.map(::lastSegment)
                val wantEff = want.effects.map(::lastSegment)
                if (gotEff != wantEff) {
                    errs.add("$at: effects got $gotEff, want $wantEff")
                }
            }
        }

        if (errs.isEmpty()) {
            println("ok   $name  (${spec.states.size} states x ${spec.actions.size} actions, ${traces.size} traces)")
            // Lints are advisory and indented, never counted as failures.
            report(adapter.table, adapter.payloads).lines()
                .filter { it.isNotBlank() }
                .forEach { println("       $it") }
        } else {
            println("FAIL $name")
            errs.forEach { println("       $it") }
            failed++
        }
    }

    println()
    println("conformance (kotlin): ${adapters.size} tables, $steps trace steps, $failed failed")

    // A fixture with no adapter is skipped, not passed. Swift will start with
    // everything skipped and that has to be visible.
    val declared = root.listFiles { f -> f.name.endsWith(".tbl") }?.size ?: 0
    if (declared > adapters.size) {
        println("       ${declared - adapters.size} fixture(s) have no Kotlin adapter (skipped)")
    }

    if (failed > 0) kotlin.system.exitProcess(1)
}

/**
 * Compare a generated artifact against its committed golden file.
 *
 * Never blesses: the Rust harness owns `--bless`, so a Kotlin renderer or lint
 * that drifts fails here rather than quietly rewriting the shared snapshot.
 */
private fun checkGolden(root: File, name: String, ext: String, got: String): List<String> {
    val golden = File(root, "$name.$ext")
    if (!golden.exists()) return listOf("no golden $ext at ${golden.path}")
    val want = golden.readText()
    if (got == want) return emptyList()

    val errs = mutableListOf("$ext differs from ${golden.path}:")
    got.lines().zip(want.lines()).forEachIndexed { n, (g, w) ->
        if (g != w) {
            errs.add("  line $n: kotlin |$g|")
            errs.add("  line $n: golden |$w|")
        }
    }
    return errs
}
