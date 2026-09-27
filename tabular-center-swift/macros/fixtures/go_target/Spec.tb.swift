// swift-format-ignore-file
//
// The rows below are a grid, and swift-format has no per-glob configuration:
// this directive is the entire exemption, which is why it lives in the file
// rather than in a config nobody reads. `swift-format-config` requires it on
// every `.tb.swift`; `swift-matrix-stable` runs the formatter over this file
// and compares the rows.
//~ EXPECT: tabular-center::go-target
//
// GO to a state that carries a payload, with no arguments given.
//
// Rule R3, and the one diagnostic here that exists to stop a shortcut rather
// than catch a typo. Without it GO becomes the lazy option: every payload
// fills with zero values chosen to avoid writing a cell, and the machine's
// types stop meaning anything. `.handle`, or `.go(.running(since: 0))`, are
// the two honest answers and the message names both.
@Machine
enum GoTarget {
    enum S { case idle, running(since: Int) }
    enum A { case start, stop }
    enum F { case beep }

    final class Ctx {}

    static let initial = S.idle

    //                            start           stop
    @Row(.idle)    static let i = [ .go(.running),  .ignore ]
    @Row(.running) static let r = [ .ignore,        .handle ]

    func handle(_ ctx: Ctx, _ state: S, _ action: A) -> Step<S, F> { fatalError() }
}
