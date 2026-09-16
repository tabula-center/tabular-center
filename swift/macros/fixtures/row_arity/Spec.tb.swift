//~ EXPECT: tabula::row-arity
//
// A row with two cells against three actions.
//
// `.tb.swift` because the rows are column-aligned; see spec/matrix-files.md.
@Machine
enum Arity {
    enum S { case idle, busy }
    enum A { case start, stop, poke }
    enum F { case beep }

    final class Ctx {}

    static let initial = S.idle

    //                            start     stop      poke
    @Row(.idle) static let i = [ .handle,  .ignore ]
    @Row(.busy) static let b = [ .ignore,  .handle,  .ignore ]

    func handle(_ ctx: Ctx, _ state: S, _ action: A) -> Step<S, F> { fatalError() }
}
