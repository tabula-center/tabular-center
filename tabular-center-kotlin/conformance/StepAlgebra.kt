package conformance

import center.tabula.Step
import center.tabula.flatMap
import center.tabula.map
import center.tabula.zip
import java.io.File

/**
 * Replays spec/conformance/step-algebra.cases against Kotlin's `Step`: each
 * case's input steps are built, the operation applied, and the result written
 * back in the file's spelling and compared as text. The file must also hold
 * every outcome combination for every operation, so losing a case fails
 * rather than passing on less. Format: spec/conformance/README.md.
 */
private enum class Kind { Go, Stay, Ignored }

private sealed interface Target {
    data class Literal(val value: Long) : Target
    data class InputPlus(val offset: Long) : Target
}

private data class Written(val kind: Kind, val targets: List<Target>, val effects: List<String>)

private class CaseError(message: String) : Exception(message)

private fun parseTarget(text: String): Target = when {
    text == "s" -> Target.InputPlus(0)
    text.startsWith("s+") ->
        Target.InputPlus(text.removePrefix("s+").toLongOrNull() ?: throw CaseError("bad target `$text`"))
    else -> Target.Literal(text.toLongOrNull() ?: throw CaseError("bad target `$text`"))
}

private fun parseEffects(text: String): List<String> {
    if (text.isEmpty()) return emptyList()
    if (!text.startsWith("[") || !text.endsWith("]")) throw CaseError("bad effects `$text`")
    val inner = text.substring(1, text.length - 1)
    if (inner.isEmpty()) throw CaseError("write no effects as nothing, not `[]`")
    return inner.split(",")
}

private fun parseStep(text: String): Written = when {
    text.startsWith("ignored") -> {
        if (text != "ignored") throw CaseError("`$text`: an ignored step has no effects")
        Written(Kind.Ignored, emptyList(), emptyList())
    }
    text.startsWith("stay") -> Written(Kind.Stay, emptyList(), parseEffects(text.removePrefix("stay")))
    text.startsWith("go(") -> {
        val rest = text.removePrefix("go(")
        val close = rest.indexOf(')')
        if (close < 0) throw CaseError("`$text`: unclosed target")
        val targets = rest.substring(0, close).split(",").map(::parseTarget)
        Written(Kind.Go, targets, parseEffects(rest.substring(close + 1)))
    }
    else -> throw CaseError("`$text` is not a step")
}

private fun build(written: Written, input: Long): Step<Long, String> = when (written.kind) {
    Kind.Go -> {
        val target = written.targets.singleOrNull()
            ?: throw CaseError("an input step has exactly one target")
        val value = when (target) {
            is Target.Literal -> target.value
            is Target.InputPlus -> input + target.offset
        }
        Step.Go(value, written.effects)
    }
    Kind.Stay -> Step.Stay(written.effects)
    Kind.Ignored -> Step.Ignored
}

private fun <S> render(step: Step<S, String>, target: (S) -> String): String {
    val head = when (step) {
        is Step.Go -> "go(${target(step.next)})"
        is Step.Stay -> "stay"
        is Step.Ignored -> "ignored"
    }
    return if (step.effects.isEmpty()) head else "$head[${step.effects.joinToString(",")}]"
}

private data class Evaluated(val actual: String, val expected: String, val kinds: Triple<String, Kind, Kind>)

private fun evaluate(tokens: List<String>): Evaluated = when {
    tokens.size == 4 && tokens[0] == "map" && tokens[2] == "=>" -> {
        val lhs = parseStep(tokens[1])
        val actual = build(lhs, 0).map { it + 10 }
        Evaluated(render(actual) { it.toString() }, tokens[3], Triple("map", lhs.kind, Kind.Go))
    }
    tokens.size == 6 && tokens[0] == "and_then" && tokens[2] == "then" && tokens[4] == "=>" -> {
        val lhs = parseStep(tokens[1])
        val next = parseStep(tokens[3])
        build(next, 0)
        val actual = build(lhs, 0).flatMap { s -> build(next, s) }
        Evaluated(render(actual) { it.toString() }, tokens[5], Triple("and_then", lhs.kind, next.kind))
    }
    tokens.size == 5 && tokens[0] == "zip" && tokens[3] == "=>" -> {
        val lhs = parseStep(tokens[1])
        val rhs = parseStep(tokens[2])
        val actual = build(lhs, 0).zip(build(rhs, 0))
        Evaluated(render(actual) { "${it.first},${it.second}" }, tokens[4], Triple("zip", lhs.kind, rhs.kind))
    }
    else -> throw CaseError("not a case in the documented shape")
}

private fun required(): Set<Triple<String, Kind, Kind>> = buildSet {
    for (lhs in Kind.entries) {
        add(Triple("map", lhs, Kind.Go))
        for (rhs in Kind.entries) {
            add(Triple("and_then", lhs, rhs))
            add(Triple("zip", lhs, rhs))
        }
    }
}

fun replayStepAlgebra(root: File): Pair<Int, List<String>> {
    val file = File(root, "step-algebra.cases")
    if (!file.isFile) return 0 to listOf("${file.path}: not found")
    val failures = mutableListOf<String>()
    val seen = mutableSetOf<Triple<String, Kind, Kind>>()
    var cases = 0
    file.readLines().forEachIndexed { index, line ->
        val tokens = line.trim().split(Regex("\\s+")).filter { it.isNotEmpty() }
        if (tokens.isEmpty()) return@forEachIndexed
        cases++
        try {
            val result = evaluate(tokens)
            seen += result.kinds
            if (result.actual != result.expected) {
                failures += "line ${index + 1}: `${line.trim()}` gave ${result.actual}, expected ${result.expected}"
            }
        } catch (e: CaseError) {
            failures += "line ${index + 1}: ${e.message}"
        }
    }
    for ((op, lhs, rhs) in required() - seen) {
        failures += "no case for $op with $lhs and $rhs"
    }
    return cases to failures
}
