// swift-format-ignore-file
//
// The rows below are a grid, and swift-format has no per-glob configuration:
// this directive is the entire exemption, which is why it lives in the file
// rather than in a config nobody reads. `swift-format-config` requires it on
// every `.tb.swift`; `swift-matrix-stable` runs the formatter over this file
// and compares the rows.
//~ EXPECT: tabula::empty-emit
//
// An EMIT cell naming no effect.
//
// EMIT without effects is IGNORE with extra words, and the diagnostic says so:
// a cell that stays put and does nothing already has a spelling. `F` is
// non-empty on purpose, so the failure is about the cell rather than about a
// machine with nothing to emit.
@Machine
enum Empty {
    enum S { case idle, busy }
    enum A { case start, stop }
    enum F { case beep }

    final class Ctx {}

    static let initial = S.idle

    //                            start        stop
    @Row(.idle) static let i = [ .handle,     .emit([]) ]
    @Row(.busy) static let b = [ .ignore,     .handle ]

    func handle(_ ctx: Ctx, _ state: S, _ action: A) -> Step<S, F> { fatalError() }
}
