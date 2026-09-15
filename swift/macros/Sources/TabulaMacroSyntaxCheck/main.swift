// The macro package's checks.
//
// A plain executable with a hand-rolled assertion harness, not a test target,
// for the reason `swift/Package.swift` records: nixpkgs' Swift ships no
// XCTest, and a test framework that has to be resolved is a test framework
// that can stop the tests from running.
//
// ## Why this exists before the thing it tests
//
// `MachineMacro` is SwiftSyntax nodes to a `RawMachine` and nothing else
// (SURFACE.md). That is a function over syntax trees, so it can be exercised
// by parsing a source string with `SwiftParser` and inspecting what comes
// back — no macro expansion, no compiler plugin, no `CompilerPluginSupport`.
//
// Which turns SURFACE.md's two "answerable in an hour with a toolchain that
// can compile a macro" questions into questions a test answers here:
//
//   - whether `@Row` on a `static let` is even parseable as an attribute
//   - whether the nested enums can be read off the attached declaration's
//     members
//
// The first is settled below, and the answer is yes: `SwiftParser` produces an
// `AttributeSyntax` for it regardless of whether any macro is declared, because
// parsing does not resolve attributes. The traversal can therefore be written
// and tested before the `.macro` target is declarable.
import SwiftParser
import SwiftSyntax
import TabulaCodegen
import TabulaMacroSyntax

var failed = 0

func check(_ ok: Bool, _ what: String) {
    if ok {
        print("ok   \(what)")
    } else {
        print("FAIL \(what)")
        failed += 1
    }
}

/// The declaration from SURFACE.md, as a string. Kept here rather than in a
/// fixture file so the checks run from a single built product with no path
/// assumptions — the same call the Kotlin and Rust harnesses make.
let source = """
@Machine
enum Turnstile {
    enum S { case locked, unlocked }
    enum A { case coin, push }
    enum F { case click }

    final class Ctx { var admitted = 0 }

    static let initial = S.locked

    //                        Coin                        Push
    @Row(.locked)   static let l = [ .go(.unlocked, [.click]),  .ignore ]
    @Row(.unlocked) static let u = [ .ignore,                   .handle ]

    func handle(_ ctx: Ctx, _ state: S, _ action: A) -> Step<S, F> { fatalError() }
}
"""

let parsed = Parser.parse(source: source)

check(!parsed.hasError, "the surface from SURFACE.md parses")

let decls = parsed.statements.compactMap { $0.item.as(EnumDeclSyntax.self) }
check(decls.count == 1, "one top-level enum")

if let machine = decls.first {
    check(machine.name.text == "Turnstile", "the machine's name is its declaration's name")

    let members = machine.memberBlock.members.map(\.decl)
    let enums = members.compactMap { $0.as(EnumDeclSyntax.self) }
    check(
        enums.map(\.name.text) == ["S", "A", "F"],
        "the nested enums are readable from the attached declaration's members"
    )

    // Order is meaning (SURFACE.md): the cells of a row line up with the cases
    // of the action enum by position, so a traversal that sorted or used a
    // dictionary would lose the property the library exists for.
    if let actions = enums.first(where: { $0.name.text == "A" }) {
        let cases = actions.memberBlock.members
            .compactMap { $0.decl.as(EnumCaseDeclSyntax.self) }
            .flatMap { $0.elements.map(\.name.text) }
        check(cases == ["coin", "push"], "action cases come back in declaration order")
    } else {
        check(false, "action cases come back in declaration order")
    }

    let rows = members
        .compactMap { $0.as(VariableDeclSyntax.self) }
        .filter { $0.attributes.contains { $0.as(AttributeSyntax.self)?
            .attributeName.trimmedDescription == "Row" } }
    check(rows.count == 2, "@Row on a `static let` parses as an attribute")
}

// MARK: - The traversal

if let machine = decls.first {
    do {
        let raw = try MachineSyntax.read(machine)
        check(raw.machine == "Turnstile", "machine name")
        check(raw.initial == "locked", "initial is the case, not the qualified name")
        check(raw.states.map(\.name) == ["locked", "unlocked"], "states in declaration order")
        check(raw.actions.map(\.name) == ["coin", "push"], "actions in declaration order")
        check(raw.effects.map(\.name) == ["click"], "effects read from F")
        check(raw.rows.map(\.state) == ["locked", "unlocked"], "rows in source order")

        let first = raw.rows.first?.cells ?? []
        check(first.map(\.kind) == ["GO", "IGNORE"], "cells in column order")
        check(first.first?.target == "unlocked", "GO target")
        check(first.first?.effects == ["click"], "GO effects")

        // No validation here, by design: `buildDesc` owns every diagnostic in
        // spec/diagnostics.md, and a second implementation would be two
        // messages for one error drifting apart. So the real check is that the
        // two halves meet.
        let desc = try buildDesc(raw)
        check(desc.machine == "Turnstile", "buildDesc accepts what the traversal produces")
    } catch {
        check(false, "the traversal reads the surface: \(error)")
    }
}

// A shape it cannot read is an error, never a silent drop.
do {
    let bad = Parser.parse(source: """
        @Machine
        enum Broken {
            enum S { case a }
            enum A { case x }
            static let initial = S.a
            @Row(.a) static let r = (x: .ignore)
        }
        """)
    if let decl = bad.statements.first?.item.as(EnumDeclSyntax.self) {
        do {
            _ = try MachineSyntax.read(decl)
            check(false, "a tuple where a row was expected is an error")
        } catch let e as SyntaxError {
            check(
                e.message.contains("array literal") && e.message.contains(".a"),
                "the error names what was found and where: \(e.message)")
        }
    }
}

check(TabulaMacroSyntax.surface == "see SURFACE.md", "the module links")

print("")
print("macro syntax checks: \(failed) failed")
if failed > 0 { exit(1) }
