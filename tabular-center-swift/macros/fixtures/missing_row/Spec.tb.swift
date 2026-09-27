// swift-format-ignore-file
//
// The rows below are a grid, and swift-format has no per-glob configuration:
// this directive is the entire exemption, which is why it lives in the file
// rather than in a config nobody reads. `swift-format-config` requires it on
// every `.tb.swift`; `swift-matrix-stable` runs the formatter over this file
// and compares the rows.
//~ EXPECT: tabular-center::missing-row
//
// Three declared states, two rows. The row left out is the LAST one, so a walk
// that stops when rows run out reports it, while one indexing rows by state
// would accept a truncated table without noticing.
@Machine
enum Missing {
    enum S { case idle, busy, done }
    enum A { case start, stop }
    enum F { case beep }

    final class Ctx {}

    static let initial = S.idle

    //                            start     stop
    @Row(.idle) static let i = [ .handle,  .ignore ]
    @Row(.busy) static let b = [ .ignore,  .handle ]

    func handle(_ ctx: Ctx, _ state: S, _ action: A) -> Step<S, F> { fatalError() }
}
