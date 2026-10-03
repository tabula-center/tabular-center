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
import TabularCenterCodegen
import TabularCenterMacroSyntax

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

        let rendered = Parser.parse(source: emit(desc))
        return rendered.statements.compactMap { stmt -> DeclSyntax? in
            guard let d = stmt.item.as(DeclSyntax.self) else { return nil }
            if d.is(ImportDeclSyntax.self) { return nil }
            return d
        }
    }
}

@main
struct TabularCenterPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [MachineMacro.self]
}
