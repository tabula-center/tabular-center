/// The `@Machine` declaration.
///
/// Here rather than in `Tabula`, and that placement is the packaging decision
/// rather than an accident. `#externalMacro` names the implementation module,
/// so whichever module declares this acquires a dependency on the macro target
/// and therefore on swift-syntax. Declaring it in `Tabula` would give the whole
/// library a remote dependency to serve users who want one attribute.
///
/// A user who wants the macro depends on this package. A user who does not
/// pays nothing, and `Tabula` keeps its no-dependencies claim without an
/// asterisk.
@attached(member, names: arbitrary)
@attached(extension, conformances: Sendable)
public macro Machine() = #externalMacro(module: "TabulaMacros", type: "MachineMacro")
