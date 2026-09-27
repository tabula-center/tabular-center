// swift-format-ignore-file
//
// The rows below are a grid, and swift-format has no per-glob configuration:
// this directive is the entire exemption, which is why it lives in the file
// rather than in a config nobody reads. `swift-format-config` requires it on
// every `.tb.swift`; `swift-matrix-stable` runs the formatter over this file
// and compares the rows.
//~ EXPECT: tabular-center::extra-row
//
// A row for a state `S` never declares.
//
// The mirror of missing_row, and separate for the reason the Rust and Kotlin
// pairs are separate: `buildDesc` walks states and rows together, and the two
// arms that report a mismatch are reached at different points in that walk.
//
// Nothing here has to compile -- the traversal reads syntax -- so `.gone` need
// not exist as a case. That is a difference from the Kotlin fixture, where
// `S.Gone` is a real type the `states` list omits, because KSP sees a resolved
// symbol and this sees a token.
@Machine
enum Extra {
    enum S { case idle, busy }
    enum A { case start, stop }
    enum F { case beep }

    final class Ctx {}

    static let initial = S.idle

    //                            start     stop
    @Row(.idle) static let i = [ .handle,  .ignore ]
    @Row(.busy) static let b = [ .ignore,  .handle ]
    @Row(.gone) static let g = [ .ignore,  .ignore ]

    func handle(_ ctx: Ctx, _ state: S, _ action: A) -> Step<S, F> { fatalError() }
}
