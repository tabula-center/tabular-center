// swift-format-ignore-file
//
// The rows below are a grid, and swift-format has no per-glob configuration:
// this directive is the entire exemption, which is why it lives in the file
// rather than in a config nobody reads. `swift-format-config` requires it on
// every `.tb.swift`; `swift-matrix-stable` runs the formatter over this file
// and compares the rows.
//~ EXPECT: tabular-center::unknown-effect
//
// A cell emitting an effect the machine never declared.
//
// `effects` is not documentation: it is what the generated `perform` switches
// over, so an effect outside it has no handler and no arm. Declaring `beep`
// and emitting `whirr` is the shape a rename leaves behind.
@Machine
enum UnknownEffect {
    enum S { case idle, busy }
    enum A { case start, stop }
    enum F { case beep }

    final class Ctx {}

    static let initial = S.idle

    //                            start              stop
    @Row(.idle) static let i = [ .emit([.whirr]),   .ignore ]
    @Row(.busy) static let b = [ .ignore,           .handle ]

    func handle(_ ctx: Ctx, _ state: S, _ action: A) -> Step<S, F> { fatalError() }
}
