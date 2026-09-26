/// The macro, at last.
///
/// Three pieces that already existed, wired together for the first time:
/// `MachineSyntax.read` turns the attached enum into a `RawMachine`,
/// `buildDesc` validates it into a `MachineDesc`, and `emit` renders the
/// dispatcher. This file adds no rules and no rendering — it is the seam.
///
/// It could not exist until now. A `.macro` target needs
/// `CompilerPluginSupport`, which nixpkgs' SwiftPM did not ship;
/// `tabular-center-swift/nix/swiftpm-plugin-support.nix` builds it, and `tools/verify
/// swift-macro-support` reports whether the toolchain in use has it.
import SwiftCompilerPlugin
import SwiftParser
import SwiftSyntax
import SwiftSyntaxMacros
import TabulaCodegen
import TabulaMacroSyntax

public struct MachineMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let decl = declaration.as(EnumDeclSyntax.self) else {
            throw SyntaxError(
                "@Machine attaches to an `enum`; see tabular-center-swift/macros/SURFACE.md")
        }

        let raw = try MachineSyntax.read(decl)
        let desc = try buildDesc(raw)

        // `emit` renders a FILE — package line, imports, then declarations —
        // because the Kotlin and Rust generators write files and one emitter
        // serves all three. A member macro may only contribute members, so the
        // rendered source is parsed back and its top-level declarations taken.
        //
        // Parsing rather than string-slicing: the boundary between the header
        // and the first declaration is a question about Swift syntax, and
        // there is a parser right here that answers it. A `hasPrefix("import")`
        // scan would work until an import appeared in a doc comment.
        let rendered = Parser.parse(source: emit(desc))
        return rendered.statements.compactMap { stmt -> DeclSyntax? in
            guard let d = stmt.item.as(DeclSyntax.self) else { return nil }
            if d.is(ImportDeclSyntax.self) { return nil }
            return d
        }
    }
}

@main
struct TabulaPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [MachineMacro.self]
}
