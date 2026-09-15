/// The traversal does not live here yet. This file exists so the target has a
/// source and the package builds, which is the point of the restructure in
/// `Package.swift`: until now nothing here could be compiled at all, so
/// "does swift-syntax resolve and link" was an unanswerable question.
///
/// What replaces it is `MachineMacro`, per `SURFACE.md`: SwiftSyntax nodes in,
/// `RawMachine` out, no diagnostics of its own beyond syntax it cannot read.
///
/// Deliberately importing nothing. The first build of this package should fail
/// or succeed on dependency *resolution*, not on an API guess about a version
/// of swift-syntax nobody here has seen.
public enum TabulaMacroSyntax {
    /// Present so the module is not empty. Replaced by the traversal.
    public static let surface = "see SURFACE.md"
}
