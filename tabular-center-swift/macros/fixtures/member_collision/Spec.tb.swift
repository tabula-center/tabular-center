// swift-format-ignore-file
//
// The rows below are a grid, and swift-format has no per-glob configuration:
// this directive is the entire exemption, which is why it lives in the file
// rather than in a config nobody reads. `swift-format-config` requires it on
// every `.tb.swift`; `swift-matrix-stable` runs the formatter over this file
// and compares the rows.
//~ EXPECT: tabular-center::member-collision
//
// Two cells the generator would give one name: `(logIn, start)` and
// `(log, inStart)` are both `logInStart`. Here it matters most -- neither
// state nor action carries a payload, so both members would be
// `func logInStart(_ ctx: Ctx) -> Step<S, F>`, declared twice: an "invalid
// redeclaration" in generated code, far from this matrix, instead of this.
@Machine
enum MemberCollision {
    enum S { case logIn, log }
    enum A { case start, inStart }
    enum F {}

    final class Ctx {}

    static let initial = S.logIn

    //                          start       inStart
    @Row(.logIn) static let i = [ .handle,  .ignore ]
    @Row(.log)   static let o = [ .ignore,  .handle ]

    func handle(_ ctx: Ctx, _ state: S, _ action: A) -> Step<S, F> { fatalError() }
}
