// Runs the shared `spec/conformance` fixtures against the Kotlin
// implementation.
//
// Three things are compared, and the third is the one that only exists because
// there are now two implementations:
//
// 1. **Table** — the generated matrix, cell by cell.
// 2. **Traces** — outcomes and effects, step by step.
// 3. **Golden grid** — byte for byte against the same `.grid` file the Rust
//    harness writes. Two renderers that disagree by a space would otherwise
//    drift silently until someone diffed a snapshot by hand.
package conformance

import center.tabula.Export
import center.tabula.testing.*
import center.tabula.report
import java.io.File

fun main(args: Array<String>) {
    val root = File(args.firstOrNull { !it.startsWith("--") } ?: "../spec/conformance")
    val emitDir = args.firstOrNull { it.startsWith("--emit=") }
        ?.removePrefix("--emit=")
        ?.let { File(it).apply { mkdirs() } }
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
        emit(emitDir, name, "grid", Export.toGrid(adapter.table))
        emit(emitDir, name, "mmd", Export.toMermaid(adapter.table))
        emit(emitDir, name, "lint", report(adapter.table, adapter.payloads))
        emit(emitDir, name, "cov", Export.toCoverageReport(adapter.table))

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
            report(adapter.table, adapter.payloads).lines()
                .filter { it.isNotBlank() }
                .forEach { println("       $it") }
        } else {
            println("FAIL $name")
            errs.forEach { println("       $it") }
            failed++
        }
    }

    val (cases, algebraFailures) = replayStepAlgebra(root)
    if (algebraFailures.isEmpty()) {
        println("ok   step-algebra ($cases cases)")
    } else {
        println("FAIL step-algebra")
        algebraFailures.forEach { println("       $it") }
        failed++
    }

    println()
    println("conformance (kotlin): ${adapters.size} tables, $steps trace steps, $failed failed")

    val declared = root.listFiles { f -> f.name.endsWith(".tbl") }
        ?.map { it.name.removeSuffix(".tbl") }?.sorted() ?: emptyList()
    val covered = adapters.map { it.name }.toSet()
    for (name in declared.filter { it !in covered }) {
        println("skip $name (no Kotlin adapter)")
    }

    if (failed > 0) kotlin.system.exitProcess(1)
}

private fun emit(dir: File?, name: String, ext: String, got: String) {
    if (dir != null) File(dir, "$name.$ext").writeText(got)
}
