import Tabula

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// The same assertions as the Rust and Kotlin references.
///
/// Deliberately the same: the three implementations agreeing is what
/// `spec/conformance` checks for fixtures, and it is where every
/// cross-language finding so far has come from.

// MARK: - Transitions

func transitions() {
    let cells = Timer()

    Assert.eq(
        step(cells, Ctx(limit: 3), .idle, .start),
        .go(.running(since: 0), effects: [.startClock]),
        "HANDLE cell runs developer code"
    )

    Assert.eq(
        step(cells, Ctx(limit: 3), .running(since: 3), .cancel),
        .go(.idle, effects: [.stopClock(reason: .cancelled)]),
        "static GO cell needs no developer code"
    )

    let inapplicable: [(S, A)] = [
        (.idle, .tick(now: 1)),
        (.idle, .cancel),
        (.running(since: 0), .start),
        (.done, .tick(now: 1)),
        (.done, .cancel),
    ]
    for (s, a) in inapplicable {
        Assert.ok(step(cells, Ctx(limit: 3), s, a).isIgnored, "IGNORE cell: \(s) x \(a)")
    }

    let stayed = step(cells, Ctx(limit: 100), .running(since: 0), .tick(now: 1))
    Assert.eq(stayed, .stay(effects: []), "a tick below the limit stays")
    Assert.ok(!stayed.isIgnored, "a tick while running is meaningful, not ignored")

    // Narrowed payloads: `runningTick` takes Running and Tick directly, so
    // `state.since` and `action.now` are plain fields.
    let ctx = Ctx(limit: 3)
    Assert.eq(
        cells.runningTick(ctx, Running(since: 2), Tick(now: 20)),
        .go(.done, effects: [.stopClock(reason: .elapsed)]),
        "cell receives narrowed, destructured payloads"
    )
    Assert.eq(ctx.ticksSeen, 1, "context outlives the transition")
}

// MARK: - Effect surface

func effectSurface() {
    let ctx = Ctx(limit: 1)
    Assert.ok(perform(Timer(), ctx, .stopClock(reason: .elapsed)) == nil, "perform dispatches")
    Assert.eq(ctx.log, ["stop:elapsed"], "effect handler receives a narrowed payload")
}

// MARK: - Table, lints, export

func tableAndLints() {
    let c = TIMER_TABLE.coverage()
    Assert.eq(c.total, 9, "table covers every cell")
    Assert.eq(c.handle, 2, "two HANDLE cells")
    Assert.eq(c.ignore, 5, "five IGNORE cells")
    Assert.eq(c.go, 2, "two static GO cells")
    Assert.eq(c.requiredMembers, 2, "exactly the two cell members on TimerCells")

    Assert.ok(!TIMER_TABLE.isFullyStatic(), "a HANDLE cell makes reachability unknowable")
    // Same tightening as Rust and Kotlin: no-static-entry stays silent once
    // any cell is dynamic, or it fires on nearly every healthy machine.
    let quiet = lint(TIMER_TABLE).allSatisfy {
        if case .noStaticEntry = $0 { return false } else { return true }
    }
    Assert.ok(quiet, "no-static-entry is silent on a machine with HANDLE cells")

    // The golden .grid files in spec/conformance are shared across languages,
    // so the renderers must agree byte for byte — including the trimming.
    let grid = Export.toGrid(TIMER_TABLE)
    let untrimmed = grid.split(separator: "\n", omittingEmptySubsequences: false)
        .contains { $0.hasSuffix(" ") }
    Assert.ok(!untrimmed, "grid lines are right-trimmed")
    Assert.ok(grid.contains("GO(Idle, StopClock)"), "grid renders GO with effects")
    Assert.ok(grid.contains("HANDLE"), "grid renders HANDLE")

    let mermaid = Export.toMermaid(TIMER_TABLE)
    Assert.ok(mermaid.contains("[*] --> Idle"), "mermaid marks the initial state")
    Assert.ok(
        mermaid.contains("Running --> Idle: Cancel / StopClock"),
        "mermaid draws static transitions"
    )
    // A HANDLE cell's target is not knowable at build time, so it is a
    // self-loop rather than an invented edge.
    Assert.ok(mermaid.contains("Idle --> Idle: Start / ?handle"), "HANDLE cells are self-loops")

    let dot = Export.toDot(TIMER_TABLE)
    Assert.ok(dot.hasPrefix("digraph Timer {"), "dot names the machine")
    Assert.ok(
        dot.contains(#"Idle -> Idle [label="Start / ?handle", style=dashed];"#),
        "dot dashes dynamic edges"
    )
    Assert.ok(
        dot.contains(#"Running -> Idle [label="Cancel / StopClock"];"#),
        "dot leaves static edges solid"
    )

    let puml = Export.toPlantuml(TIMER_TABLE)
    Assert.ok(puml.hasPrefix("@startuml\n"), "plantuml opens")
    Assert.ok(puml.hasSuffix("@enduml\n"), "plantuml closes")
    Assert.ok(puml.contains("[*] --> Idle"), "plantuml marks the initial state")
    Assert.ok(
        puml.contains("Running --> Idle : Cancel / StopClock"),
        "plantuml draws static transitions"
    )

    // The three formats share one walk, so they must list the same edges in
    // the same order. They did not always: mermaid was rendered in two passes
    // for a while, every GO edge before every self-loop, while Kotlin
    // interleaved them in cell order. Nothing compares diagram output across
    // languages, so nothing failed.
    //
    // Tokenised rather than string-replaced because this target imports no
    // Foundation -- no trimmingCharacters, no replacingOccurrences. Splitting
    // on spaces drops the indentation for free, which is the only reason the
    // two formats needed normalising at all.
    func edgeOrder(_ s: String) -> [String] {
        s.split(separator: "\n").compactMap { raw -> String? in
            let parts = raw.split(separator: " ").map(String.init)
            guard parts.count >= 3, parts[1] == "-->", parts[0] != "[*]" else { return nil }
            // mermaid writes `To: label`, plantuml writes `To : label`.
            var to = parts[2]
            if to.hasSuffix(":") { to.removeLast() }
            var rest = parts.dropFirst(3).joined(separator: " ")
            if rest.hasPrefix(": ") { rest = String(rest.dropFirst(2)) }
            return "\(parts[0])->\(to)|\(rest)"
        }
    }
    Assert.eq(
        edgeOrder(mermaid), edgeOrder(puml),
        "mermaid and plantuml agree on edge order"
    )
}

func lintRules() {
    let dead = Table(
        machine: "Dead",
        states: ["A", "B"],
        actions: ["X", "Y"],
        cells: [[.ignore, .ignore], [.ignore, .ignore]],
        initial: "A"
    )
    let f = lint(dead)
    Assert.ok(f.contains(.deadRow(state: "A")), "a wholly ignoring row is dead")
    Assert.ok(f.contains(.deadColumn(action: "X")), "a column nothing responds to is dead")
    Assert.ok(f.contains(.noStaticEntry(state: "B")), "unreachable in a fully static matrix")
    Assert.ok(f.contains(.ignoreHeavy(percent: 100)), "100% IGNORE is flagged")
    // Two warnings for one problem is how a lint earns a reputation for noise.
    let noExit = f.contains { if case .noStaticExit = $0 { return true } else { return false } }
    Assert.ok(!noExit, "dead-row subsumes no-static-exit")

    Assert.eq(
        payloadHoist([
            (state: "Connecting", field: "retryCount", type: "Int"),
            (state: "Backoff", field: "retryCount", type: "Int"),
            (state: "Backoff", field: "until", type: "Int64"),
            (state: "Reconnecting", field: "retryCount", type: "Int"),
        ]),
        [.payloadHoist(
            // Canonical, not "Int". See spec/diagnostics.md.
            field: "retryCount",
            type: "int",
            states: ["Connecting", "Backoff", "Reconnecting"]
        )],
        "a field in three states is flagged"
    )
    Assert.eq(
        payloadHoist([
            (state: "A", field: "n", type: "Int"),
            (state: "B", field: "n", type: "Int64"),
            (state: "C", field: "n", type: "UInt8"),
        ]),
        [.payloadHoist(field: "n", type: "int", states: ["A", "B", "C"])],
        "widths of the same primitive are one field"
    )
    Assert.eq(
        payloadHoist([
            (state: "A", field: "amount", type: "Money"),
            (state: "B", field: "amount", type: "Money"),
            (state: "C", field: "amount", type: "Money"),
        ]),
        [.payloadHoist(field: "amount", type: "Money", states: ["A", "B", "C"])],
        "an unrecognised type passes through unchanged"
    )
    Assert.ok(
        payloadHoist([
            (state: "A", field: "n", type: "Int"),
            (state: "B", field: "n", type: "Int"),
        ]).isEmpty,
        "two states is a coincidence, not a pattern"
    )
    Assert.ok(
        payloadHoist([
            (state: "A", field: "count", type: "Int"),
            (state: "B", field: "count", type: "String"),
            (state: "C", field: "count", type: "Int"),
        ]).isEmpty,
        "the same name at different types is not the same field"
    )
}

// MARK: - Driver

func drivers() {
    // An effect handler returning an action: the whole reason `step` is
    // non-reentrant. The follow-up is queued, not recursed.
    let ctx = Ctx(limit: 1)
    let cells = Timer()
    let driver = Driver<S, A, F>(initial: .idle)
    var seen: [F] = []

    do {
        let p = try driver.dispatch(
            .start,
            step: { s, a in step(cells, ctx, s, a) },
            perform: { f in
                seen.append(f)
                if case .startClock = f { return .tick(now: 99) }
                return nil
            }
        )
        Assert.eq(p.steps, 2, "the start, then the queued tick")
        Assert.eq(p.followUps, 1, "one follow-up, through the mailbox")
        Assert.eq(driver.state, .done, "the queued tick was stepped")
        Assert.eq(seen.count, 2, "both effects reached the handler")
    } catch {
        Assert.ok(false, "driver threw: \(error)")
    }

    // A handler inspecting state must see where the machine has gone, not
    // where it was.
    let ctx2 = Ctx(limit: 100)
    let d2 = Driver<S, A, F>(initial: .idle)
    var observed: [S] = []
    do {
        _ = try d2.dispatch(
            .start,
            step: { s, a in step(Timer(), ctx2, s, a) },
            perform: { _ in observed.append(d2.state); return nil }
        )
        Assert.eq(observed, [.running(since: 0)], "the outcome is applied before effects run")
    } catch {
        Assert.ok(false, "driver threw: \(error)")
    }

    let small = Driver<S, A, F>(initial: .idle, capacity: 1)
    Assert.throwsError("overflow names its capacity rather than growing") {
        try small.enqueue(.start)
        try small.enqueue(.start)
    }
}

// MARK: - Stores

func stores() {
    // A Store is a Driver with its two closures bound once. The behaviour it
    // inherits is not re-checked here; what is checked is that binding them
    // once really does mean the same loop runs.
    let ctx = Ctx(limit: 1)
    let cells = Timer()
    var seen: [F] = []
    let store = Store<S, A, F>(
        initial: .idle,
        step: { s, a in step(cells, ctx, s, a) },
        perform: { f in
            seen.append(f)
            if case .startClock = f { return .tick(now: 99) }
            return nil
        }
    )

    do {
        let p = try store.send(.start)
        Assert.eq(p.steps, 2, "store: the start, then the queued tick")
        Assert.eq(p.followUps, 1, "store: one follow-up, through the mailbox")
        Assert.eq(store.state, .done, "store: the queued tick was stepped")
        Assert.eq(seen.count, 2, "store: both effects reached the handler")
    } catch {
        Assert.ok(false, "store threw: \(error)")
    }

    // enqueue-then-drain is not send-twice. Both actions are in the mailbox
    // before either is stepped, so the first one's follow-up lands behind the
    // second -- which is what FIFO means and what a caller batching input
    // depends on.
    let d = Store<S, A, F>(
        initial: .idle,
        step: { s, a in step(Timer(), Ctx(limit: 100), s, a) },
        perform: { _ in nil }
    )
    do {
        try d.enqueue(.start)
        try d.enqueue(.tick(now: 1))
        Assert.eq(d.pending, 2, "store: enqueue does not drain")
        let p = try d.drain()
        Assert.eq(p.steps, 2, "store: drain steps everything queued")
        Assert.eq(d.pending, 0, "store: drain empties the mailbox")
    } catch {
        Assert.ok(false, "store threw: \(error)")
    }

    let small = Store<S, A, F>(
        initial: .idle, capacity: 1,
        step: { s, a in step(Timer(), Ctx(limit: 1), s, a) },
        perform: { _ in nil }
    )
    Assert.throwsError("store: overflow names its capacity rather than growing") {
        try small.enqueue(.start)
        try small.enqueue(.start)
    }
}

/// The async half.
///
/// `AsyncDriver` had no check at all before this: sixty lines of duplicated
/// loop, documented in `swift/README.md`, exercised by nothing. Duplicated
/// code that nothing runs is the pair most likely to drift, and it is the same
/// blind spot the conformance goldens kept turning up -- something that exists
/// in one place and is compared against nothing.
func asyncStores() async {
    let cells = Timer()
    let ctx = Ctx(limit: 1)
    let store = AsyncStore<S, A, F>(
        initial: .idle,
        step: { s, a in step(cells, ctx, s, a) },
        perform: { f in
            if case .startClock = f { return .tick(now: 99) }
            return nil
        }
    )

    do {
        let p = try await store.send(.start)
        Assert.eq(p.steps, 2, "async store: the start, then the queued tick")
        Assert.eq(p.followUps, 1, "async store: one follow-up, through the mailbox")
        let state = await store.state
        Assert.eq(state, .done, "async store: the queued tick was stepped")
    } catch {
        Assert.ok(false, "async store threw: \(error)")
    }

    // The colored loop must agree with the colorless one, since it is the same
    // loop written twice. Same machine, same input, same Progress.
    let sync = Store<S, A, F>(
        initial: .idle,
        step: { s, a in step(Timer(), Ctx(limit: 1), s, a) },
        perform: { f in
            if case .startClock = f { return .tick(now: 99) }
            return nil
        }
    )
    do {
        let a = try sync.send(.start)
        let b = try await AsyncStore<S, A, F>(
            initial: .idle,
            step: { s, x in step(Timer(), Ctx(limit: 1), s, x) },
            perform: { f in
                if case .startClock = f { return .tick(now: 99) }
                return nil
            }
        ).send(.start)
        Assert.eq(a, b, "the two colors of the loop report the same progress")
    } catch {
        Assert.ok(false, "store threw: \(error)")
    }
}

/// The observable store.
///
/// `@MainActor`, so it is called with `await` from the async top level rather
/// than from the synchronous checks -- a MainActor method cannot be called
/// from a nonisolated synchronous function at all.
///
/// Guarded to match the type: `os(...)` because `ObservableStore` is Darwin
/// only -- it exists to be watched by SwiftUI -- and `#available` because the
/// package has no platforms clause and so still builds for older targets.
@MainActor
func observableStores() async {
    #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
        guard #available(macOS 14, iOS 17, tvOS 17, watchOS 10, *) else {
            Assert.ok(true, "observable store: skipped, needs macOS 14")
            return
        }
        let cells = Timer()
        let ctx = Ctx(limit: 1)
        let store = ObservableStore<S, A, F>(
            initial: .idle,
            step: { s, a in step(cells, ctx, s, a) },
            perform: { f in
                if case .startClock = f { return .tick(now: 99) }
                return nil
            }
        )
        Assert.eq(store.state, .idle, "observable store: starts where it was told")

        do {
            let p = try store.send(.start)
            Assert.eq(p.steps, 2, "observable store: the start, then the queued tick")
            // The mirror is the whole point of the type. If `state` were a
            // computed property forwarding to the driver, @Observable would
            // track nothing and a SwiftUI view would never update -- so the
            // check that matters is that the mirror actually moved.
            Assert.eq(store.state, .done, "observable store: state mirrors the driver")
        } catch {
            Assert.ok(false, "observable store threw: \(error)")
        }

        // enqueue does not drain, so the mirror must not move either: a view
        // showing a state the machine has not reached is the failure this
        // type invites.
        let d = ObservableStore<S, A, F>(
            initial: .idle,
            step: { s, a in step(Timer(), Ctx(limit: 100), s, a) },
            perform: { _ in nil }
        )
        do {
            try d.enqueue(.start)
            Assert.eq(d.state, .idle, "observable store: enqueue leaves the mirror alone")
            try d.drain()
            Assert.eq(d.state, .running(since: 0), "observable store: drain moves it")
        } catch {
            Assert.ok(false, "observable store threw: \(error)")
        }
    #endif
}

// MARK: - Entry point

transitions()
effectSurface()
tableAndLints()
lintRules()
drivers()
stores()
await asyncStores()
await observableStores()

let failures = Assert.report("swift reference")
if failures > 0 {
    // `exit`, not `fatalError`. stdout is block-buffered when piped, and
    // `fatalError` traps without flushing -- the conformance runner reported a
    // failure count with every diagnostic line swallowed before this was
    // fixed. `exit` flushes stdio on the way out.
    //
    // The earlier worry about importing a C module was reasonable when nothing
    // compiled; it does now, and losing the diagnostics is the worse failure.
    exit(1)
}
