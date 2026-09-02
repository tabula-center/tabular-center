import XCTest
@testable import Tabula

/// The same assertions as the Rust and Kotlin references.
///
/// Deliberately the same: the three implementations agreeing is what
/// `spec/conformance` checks for fixtures, and it is where every cross-language
/// finding so far has come from.
final class ReferenceTimerTests: XCTestCase {

    func testHandleCellRunsDeveloperCode() {
        let ctx = Ctx(limit: 3)
        let out = step(Timer(), ctx, .idle, .start)
        XCTAssertEqual(out, .go(.running(since: 0), effects: [.startClock]))
    }

    func testStaticGoCellNeedsNoDeveloperCode() {
        let ctx = Ctx(limit: 3)
        let out = step(Timer(), ctx, .running(since: 3), .cancel)
        XCTAssertEqual(out, .go(.idle, effects: [.stopClock(reason: .cancelled)]))
    }

    func testIgnoreCellsReportIgnoredNotStay() {
        let ctx = Ctx(limit: 3)
        let pairs: [(S, A)] = [
            (.idle, .tick(now: 1)),
            (.idle, .cancel),
            (.running(since: 0), .start),
            (.done, .tick(now: 1)),
            (.done, .cancel),
        ]
        for (s, a) in pairs {
            XCTAssertTrue(step(Timer(), ctx, s, a).isIgnored, "\(s) x \(a)")
        }
    }

    func testStayIsDistinctFromIgnored() {
        let ctx = Ctx(limit: 100)
        let out = step(Timer(), ctx, .running(since: 0), .tick(now: 1))
        XCTAssertEqual(out, .stay(effects: []))
        XCTAssertFalse(out.isIgnored, "a tick while running is meaningful")
    }

    func testCellReceivesNarrowedDestructuredPayloads() {
        let ctx = Ctx(limit: 3)
        let out = Timer().runningTick(ctx, Running(since: 2), Tick(now: 20))
        XCTAssertEqual(out, .go(.done, effects: [.stopClock(reason: .elapsed)]))
        XCTAssertEqual(ctx.ticksSeen, 1, "context outlives the transition")
    }

    func testEffectHandlerReceivesNarrowedPayload() {
        let ctx = Ctx(limit: 1)
        XCTAssertNil(perform(Timer(), ctx, .stopClock(reason: .elapsed)))
        XCTAssertEqual(ctx.log, ["stop:elapsed"])
    }

    func testTableMatchesTheDispatcher() {
        let c = TIMER_TABLE.coverage()
        XCTAssertEqual(c.total, 9)
        XCTAssertEqual(c.handle, 2)
        XCTAssertEqual(c.ignore, 5)
        XCTAssertEqual(c.go, 2)
        // Exactly the two cell members on TimerCells.
        XCTAssertEqual(c.requiredMembers, 2)
    }

    func testHandleCellsMakeReachabilityUnknowable() {
        XCTAssertFalse(TIMER_TABLE.isFullyStatic())
        // Same tightening as Rust and Kotlin: no-static-entry stays silent
        // once any cell is dynamic, or it fires on nearly every healthy
        // machine.
        let findings = lint(TIMER_TABLE)
        XCTAssertFalse(findings.contains { if case .noStaticEntry = $0 { return true } else { return false } })
    }

    func testGridIsRightTrimmedAndRendersEveryKind() {
        // The golden .grid files in spec/conformance are shared across
        // languages, so the renderers must agree byte for byte.
        let grid = Export.toGrid(TIMER_TABLE)
        for line in grid.split(separator: "\n", omittingEmptySubsequences: false) {
            XCTAssertFalse(line.hasSuffix(" "), "trailing padding in |\(line)|")
        }
        XCTAssertTrue(grid.contains("GO(Idle, StopClock)"))
        XCTAssertTrue(grid.contains("HANDLE"))
    }

    func testMermaidDrawsHandleCellsAsSelfLoops() {
        let m = Export.toMermaid(TIMER_TABLE)
        XCTAssertTrue(m.contains("[*] --> Idle"))
        XCTAssertTrue(m.contains("Running --> Idle: Cancel / StopClock"))
        // A HANDLE cell's target is not knowable at build time, so it is a
        // self-loop rather than an invented edge.
        XCTAssertTrue(m.contains("Idle --> Idle: Start / ?handle"))
    }
}

final class DriverTests: XCTestCase {

    func testFollowUpActionsGoThroughTheMailbox() throws {
        // An effect handler that returns an action: the whole reason `step` is
        // non-reentrant. The follow-up is queued, not recursed.
        let ctx = Ctx(limit: 1)
        let cells = Timer()
        let driver = Driver<S, A, F>(initial: .idle)

        var seen: [F] = []
        let p = try driver.dispatch(
            .start,
            step: { s, a in step(cells, ctx, s, a) },
            perform: { f in
                seen.append(f)
                if case .startClock = f { return .tick(now: 99) }
                return nil
            }
        )

        XCTAssertEqual(p.steps, 2, "the start, then the queued tick")
        XCTAssertEqual(p.followUps, 1)
        XCTAssertEqual(driver.state, .done)
        XCTAssertEqual(seen.count, 2)
    }

    func testOutcomeIsAppliedBeforeEffectsArePerformed() throws {
        // A handler inspecting state must see where the machine has gone, not
        // where it was.
        let ctx = Ctx(limit: 100)
        let cells = Timer()
        let driver = Driver<S, A, F>(initial: .idle)
        var observed: [S] = []

        try driver.dispatch(
            .start,
            step: { s, a in step(cells, ctx, s, a) },
            perform: { _ in
                observed.append(driver.state)
                return nil
            }
        )
        XCTAssertEqual(observed, [.running(since: 0)])
    }

    func testOverflowNamesItsCapacityRatherThanGrowing() {
        let driver = Driver<S, A, F>(initial: .idle, capacity: 1)
        XCTAssertNoThrow(try driver.enqueue(.start))
        XCTAssertThrowsError(try driver.enqueue(.start)) { error in
            XCTAssertEqual(error as? DriverError, .queueFull(capacity: 1))
        }
    }

    func testIgnoredActionsLeaveTheStateAlone() throws {
        let ctx = Ctx(limit: 3)
        let cells = Timer()
        let driver = Driver<S, A, F>(initial: .idle)
        let p = try driver.dispatch(
            .cancel,
            step: { s, a in step(cells, ctx, s, a) },
            perform: { _ in nil }
        )
        XCTAssertEqual(driver.state, .idle)
        XCTAssertEqual(p.ignored, 1)
        XCTAssertEqual(p.transitions, 0)
    }
}

final class LintTests: XCTestCase {

    private let dead = Table(
        machine: "Dead",
        states: ["A", "B"],
        actions: ["X", "Y"],
        cells: [[.ignore, .ignore], [.ignore, .ignore]],
        initial: "A"
    )

    func testAWhollyIgnoringMachineIsAllFindings() {
        let f = lint(dead)
        XCTAssertTrue(f.contains(.deadRow(state: "A")))
        XCTAssertTrue(f.contains(.deadColumn(action: "X")))
        XCTAssertTrue(f.contains(.noStaticEntry(state: "B")))
        XCTAssertTrue(f.contains(.ignoreHeavy(percent: 100)))
    }

    func testDeadRowSubsumesNoStaticExit() {
        // Two warnings for one problem is how a lint earns a reputation for
        // noise and gets switched off.
        let f = lint(dead)
        XCTAssertFalse(f.contains { if case .noStaticExit = $0 { return true } else { return false } })
    }

    func testAFieldInThreeStatesIsFlagged() {
        let findings = payloadHoist([
            (state: "Connecting", field: "retryCount", type: "Int"),
            (state: "Backoff", field: "retryCount", type: "Int"),
            (state: "Backoff", field: "until", type: "Int64"),
            (state: "Reconnecting", field: "retryCount", type: "Int"),
        ])
        XCTAssertEqual(
            findings,
            [.payloadHoist(
                field: "retryCount",
                type: "Int",
                states: ["Connecting", "Backoff", "Reconnecting"]
            )]
        )
    }

    func testTwoStatesIsACoincidenceNotAPattern() {
        let findings = payloadHoist([
            (state: "A", field: "n", type: "Int"),
            (state: "B", field: "n", type: "Int"),
        ])
        XCTAssertTrue(findings.isEmpty)
    }

    func testSameNameDifferentTypeIsNotTheSameField() {
        let findings = payloadHoist([
            (state: "A", field: "count", type: "Int"),
            (state: "B", field: "count", type: "String"),
            (state: "C", field: "count", type: "Int"),
        ])
        XCTAssertTrue(findings.isEmpty)
    }
}
