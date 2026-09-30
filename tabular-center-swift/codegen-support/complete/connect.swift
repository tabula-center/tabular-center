// The `Connect` machine, implemented, and its narrowed surface at a call site.
//
// Only one cell needs code: `(Connecting, Drop)`, the HANDLE the path does not
// name; the two hops were HANDLEs too, and derivation made them GOs. At the
// call site the happy path reads straight down, each other outcome is a
// required label, and a handler leaves by throwing -- Swift's non-local exit,
// which `rethrows` passes on.
import TabularCenter

final class CompleteConnect: ConnectCells {
    func connectingDrop(_ ctx: Connect.Ctx) -> Step<Connect.S, Connect.F> {
        .go(.failed, effects: [.banner])
    }

    func banner(_ ctx: Connect.Ctx) -> Connect.A? { nil }
}

enum ConnectDetour: Error {
    case stayedIdle
    case backToIdle
    case stillConnecting
    case failed(effectsToRun: Int)
}

func connectHappily(_ cells: ConnectCells, _ ctx: Connect.Ctx, _ arrived: Connect.A) -> String {
    do {
        _ = try Connect.idleStart(cells, ctx, .start).elvis(idle: { _ in throw ConnectDetour.stayedIdle })
        let effects = try Connect.connectingReady(cells, ctx, arrived).elvis(
            idle: { _ in throw ConnectDetour.backToIdle },
            connecting: { _ in throw ConnectDetour.stillConnecting },
            failed: { effects in throw ConnectDetour.failed(effectsToRun: effects.count) }
        )
        return "live, with \(effects.count) effect(s) to run"
    } catch {
        return "\(error)"
    }
}
