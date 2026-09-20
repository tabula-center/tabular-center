// swift-format-ignore-file
//
// The rows below are a grid, and swift-format has no per-glob configuration:
// this directive is the entire exemption, which is why it lives in the file
// rather than in a config nobody reads. `swift-format-config` requires it on
// every `.tb.swift`; `swift-matrix-stable` runs the formatter over this file
// and compares the rows.
import Tabula

/// The matrix, in a file of its own.
///
/// `spec/matrix-files.md`: the cells are column-aligned and that alignment is
/// what a reader scans, so the `.tb.` extension exists to tell a
/// general-purpose formatter to keep away. swift-format has no in-file
/// suppression, so the exclusion belongs wherever it is invoked — an extension
/// is what makes that exclusion expressible at all.
///
/// Only the matrix lives here. Splitting it out is the point rather than a
/// side effect: exempting `Turnstile.swift` wholesale would have exempted the
/// handler bodies too, which is the same over-broad exemption the `[*.kt]`
/// block had before it was narrowed.
extension Turnstile {
    //                      Coin                                Push
    static let TABLE = Table(
        machine: "Turnstile",
        states: ["Locked", "Unlocked"],
        actions: ["Coin", "Push"],
        cells: [
            [ .go(target: "Unlocked", effects: []),             .ignore ],
            [ .ignore,                                          .handle ],
        ],
        initial: "Locked"
    )
}
