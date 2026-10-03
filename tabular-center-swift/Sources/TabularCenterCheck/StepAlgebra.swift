import TabularCenter

/// The laws of `Step`'s composition operations (spec/cells.md 6), checked by
/// exhaustive enumeration: every step over a small domain -- each outcome,
/// with zero, one and two effects -- against continuations that between them
/// return every outcome. The cases all three implementations replay are
/// spec/conformance/step-algebra.cases; these are the laws behind them.
typealias AlgebraStep = Step<Int, Character>

func algebraSteps() -> [AlgebraStep] {
    let effectSets: [[Character]] = [[], ["a"], ["a", "b"]]
    var all: [AlgebraStep] = [.ignored]
    for effects in effectSets {
        for n in 0...2 { all.append(.go(n, effects: effects)) }
        all.append(.stay(effects: effects))
    }
    return all
}

let algebraContinuations: [(Int) -> AlgebraStep] = [
    { n in .go(n + 1, effects: []) },
    { n in .go(n, effects: ["x"]) },
    { _ in .stay(effects: ["y"]) },
    { _ in .stay(effects: []) },
    { _ in .ignored },
    { n in n % 2 == 0 ? .go(n * 2, effects: ["z", "w"]) : .ignored },
]

struct NeverCalled: Error {}

func stepAlgebra() {
    let f = { (x: Int) in x + 3 }
    let g = { (x: Int) in x * 2 }
    for m in algebraSteps() {
        Assert.eq(m.map { $0 }, m, "map preserves identity: \(m)")
        Assert.eq(m.map(f).map(g), m.map { g(f($0)) }, "map composes: \(m)")
        Assert.eq(m.flatMap { .go($0, effects: []) }, m, "right identity: \(m)")
        for k in algebraContinuations {
            for h in algebraContinuations {
                Assert.eq(
                    m.flatMap(k).flatMap(h),
                    m.flatMap { k($0).flatMap(h) },
                    "associativity: \(m)")
            }
        }
        if !m.isTransition {
            let after = try? m.flatMap { (_: Int) throws -> AlgebraStep in throw NeverCalled() }
            Assert.eq(after, m, "short-circuit without calling the continuation: \(m)")
        }
        for n in algebraSteps() {
            let combine = { (x: Int, y: Int) in x * 10 + y }
            Assert.eq(
                m.zip(n, with: combine),
                m.flatMap { x in n.map { y in combine(x, y) } },
                "zip(_:with:) is flatMap over map: \(m), \(n)")
        }
    }
    for a in 0...2 {
        for k in algebraContinuations {
            Assert.eq(AlgebraStep.go(a, effects: []).flatMap(k), k(a), "left identity: \(a)")
        }
    }
    let absorbed = AlgebraStep.go(1, effects: ["a", "b"]).flatMap { _ in AlgebraStep.ignored }
    Assert.eq(absorbed, .ignored, "ignored absorbs, emitting nothing")
    let paired = AlgebraStep.go(1, effects: ["a"]).zip(AlgebraStep.go(2, effects: ["b"]))
    Assert.ok(paired.target.map { $0 == (1, 2) } ?? false, "zip pairs the targets")
    Assert.eq(paired.effects, ["a", "b"], "zip concatenates the effects")
    let dropped = AlgebraStep.stay(effects: ["a"]).zip(AlgebraStep.go(2, effects: ["b"]))
    Assert.ok(!dropped.isTransition && !dropped.isIgnored, "zip stays when the left stays")
    Assert.eq(dropped.effects, ["a"], "zip drops the right effects when the left does not move")
}

enum Door: Equatable { case open, ajar }

enum Signal: Equatable { case chime, buzz }

func enter(_ door: Door) -> Step<Door, Signal> {
    door == .open ? .go(.open, effects: [.chime]) : .go(door, effects: [])
}

func unlock(codeOk: Bool) -> Step<Door, Signal> {
    let decided: Step<Door, Signal> = codeOk ? .go(.open, effects: []) : .stay(effects: [.buzz])
    return decided.flatMap(enter)
}

func openBoth(left: Bool, right: Bool) -> Step<(Door, Door), Signal> {
    unlock(codeOk: left).zip(unlock(codeOk: right))
}

func composingACell() {
    Assert.eq(unlock(codeOk: true), .go(.open, effects: [.chime]), "unlocking opens and chimes")
    Assert.eq(unlock(codeOk: false), .stay(effects: [.buzz]), "a wrong code stays and buzzes")
    let both = openBoth(left: true, right: true)
    Assert.ok(both.target.map { $0 == (.open, .open) } ?? false, "two doors open together")
    Assert.eq(both.effects, [.chime, .chime], "and both chime")
    let half = openBoth(left: false, right: true)
    Assert.ok(!half.isTransition && !half.isIgnored, "one refusal stays")
    Assert.eq(half.effects, [.buzz], "and only the refusal buzzes")
}
