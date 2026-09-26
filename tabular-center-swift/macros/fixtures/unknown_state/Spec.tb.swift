// swift-format-ignore-file
//
// The rows below are a grid, and swift-format has no per-glob configuration:
// this directive is the entire exemption, which is why it lives in the file
// rather than in a config nobody reads. `swift-format-config` requires it on
// every `.tb.swift`; `swift-matrix-stable` runs the formatter over this file
// and compares the rows.
//~ EXPECT: tabula::unknown-state
//
// `.go(.parked)` names a case the machine never declares as a state.
//
// The one that would be silent without a check: the emitted `switch` arm would
// compile, and the table would carry a destination with no row. The first
// symptom would be a runtime trap from a dispatcher whose purpose is making
// those impossible.
@Machine
enum Unknown {
    enum S { case idle, busy }
    enum A { case start, stop }
    enum F { case beep }

    final class Ctx {}

    static let initial = S.idle

    //                            start           stop
    @Row(.idle) static let i = [ .go(.parked),   .ignore ]
    @Row(.busy) static let b = [ .ignore,        .handle ]

    func handle(_ ctx: Ctx, _ state: S, _ action: A) -> Step<S, F> { fatalError() }
}
