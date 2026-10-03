package harness

import center.tabula.*

/**
 * The laws of `Step`'s composition operations (spec/cells.md 6), checked by
 * exhaustive enumeration: every step over a small domain -- each outcome,
 * with zero, one and two effects -- against continuations that between them
 * return every outcome. The cases all three implementations replay are
 * spec/conformance/step-algebra.cases; these are the laws behind them.
 */
private typealias St = Step<Int, Char>

private fun steps(): List<St> {
    val effectSets = listOf(emptyList(), listOf('a'), listOf('a', 'b'))
    val all = mutableListOf<St>(Step.Ignored)
    for (effects in effectSets) {
        for (n in 0..2) all += Step.Go(n, effects)
        all += Step.Stay(effects)
    }
    return all
}

private val continuations: List<(Int) -> St> = listOf(
    { n -> Step.go(n + 1) },
    { n -> Step.go(n, 'x') },
    { _ -> Step.stay('y') },
    { _ -> Step.stay() },
    { _ -> Step.ignored() },
    { n -> if (n % 2 == 0) Step.go(n * 2, 'z', 'w') else Step.ignored() },
)

fun stepAlgebra() {
    val f = { x: Int -> x + 3 }
    val g = { x: Int -> x * 2 }
    for (m in steps()) {
        Assert.eq(m.map { it }, m, "map preserves identity: $m")
        Assert.eq(m.map(f).map(g), m.map { g(f(it)) }, "map composes: $m")
        Assert.eq(m.mapState { it + 1 }, m.map { it + 1 }, "mapState is map: $m")
        Assert.eq(m.flatMap { Step.go(it) }, m, "right identity: $m")
        for (k in continuations) {
            for (h in continuations) {
                Assert.eq(
                    m.flatMap(k).flatMap(h),
                    m.flatMap { x -> k(x).flatMap(h) },
                    "associativity: $m",
                )
            }
        }
        if (m !is Step.Go) {
            val after = m.flatMap<Int, Int, Char> { error("called on a step with no target") }
            Assert.eq(after, m, "short-circuit without calling the continuation: $m")
        }
        for (n in steps()) {
            val combine = { x: Int, y: Int -> x * 10 + y }
            Assert.eq(
                m.zip(n, combine),
                m.flatMap { x -> n.map { y -> combine(x, y) } },
                "zip is flatMap over map: $m, $n",
            )
        }
    }
    for (a in 0..2) {
        for (k in continuations) {
            Assert.eq(Step.go<Int, Char>(a).flatMap(k), k(a), "left identity: $a")
        }
    }
    val absorbed = Step.go(1, 'a', 'b').flatMap<Int, Int, Char> { Step.ignored() }
    Assert.eq(absorbed, Step.Ignored, "ignored absorbs, emitting nothing")
    Assert.eq(
        Step.go(1, 'a').zip(Step.go(2, 'b')),
        Step.Go(1 to 2, listOf('a', 'b')),
        "zip pairs targets and concatenates effects",
    )
    Assert.eq(
        Step.stay('a').zip(Step.go(2, 'b')),
        Step.Stay(listOf('a')),
        "zip drops the right effects when the left does not move",
    )
}

enum class Door { Open, Ajar }

enum class Signal { Chime, Buzz }

fun enter(door: Door): Step<Door, Signal> =
    if (door == Door.Open) Step.go(Door.Open, Signal.Chime) else Step.go(door)

fun unlock(codeOk: Boolean): Step<Door, Signal> {
    val decided: Step<Door, Signal> = if (codeOk) Step.go(Door.Open) else Step.stay(Signal.Buzz)
    return decided.flatMap(::enter)
}

fun openBoth(leftOk: Boolean, rightOk: Boolean): Step<Pair<Door, Door>, Signal> =
    unlock(leftOk).zip(unlock(rightOk))

fun composingACell() {
    Assert.eq(unlock(true), Step.Go(Door.Open, listOf(Signal.Chime)), "unlocking opens and chimes")
    Assert.eq(unlock(false), Step.Stay(listOf(Signal.Buzz)), "a wrong code stays and buzzes")
    Assert.eq(
        openBoth(true, true),
        Step.Go(Door.Open to Door.Open, listOf(Signal.Chime, Signal.Chime)),
        "two doors open together",
    )
    Assert.eq(openBoth(false, true), Step.Stay(listOf(Signal.Buzz)), "one refusal stays")
}
