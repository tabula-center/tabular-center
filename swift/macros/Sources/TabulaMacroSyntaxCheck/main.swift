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
import Foundation
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

/// The declaration from `SURFACE.md`, read **out of `SURFACE.md`**.
///
/// It was a copy of that block pasted here, and a copy is a drift path: the
/// normative description of the surface and the only thing checking the
/// surface could disagree, and the check would go on passing against a
/// declaration nobody writes any more. The same shape as every other gap this
/// repository has closed — a green light over a question nobody asked.
///
/// So the document is executable. Edit the fenced block in `SURFACE.md` and
/// this runs against the edit; edit it into something the traversal cannot
/// read and this goes red, which is the only way a specification stays true.
///
/// Foundation is fine here, unlike in `TabulaCheck`: this target already links
/// swift-syntax, so the argument for a dependency-free check does not apply.
func surfaceDeclaration() -> String {
    let path = "SURFACE.md"
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        print("FAIL could not read \(path) (run from swift/macros)")
        exit(1)
    }
    // The first ```swift fence. That file has one declaration and its later
    // fences are diagnostics, so "first" is a fact about the document rather
    // than a guess.
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    guard let open = lines.firstIndex(where: { $0.hasPrefix("```swift") }) else {
        print("FAIL \(path) has no ```swift block; the surface must stay documented")
        exit(1)
    }
    guard let close = lines[(open + 1)...].firstIndex(where: { $0.hasPrefix("```") }) else {
        print("FAIL \(path)'s ```swift block is unterminated")
        exit(1)
    }
    return lines[(open + 1)..<close].joined(separator: "\n")
}

let source = surfaceDeclaration()

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

// MARK: - The handover is checked, not assumed
//
// `MachineSyntax` checks no rules: `buildDesc` owns every one in
// spec/diagnostics.md so that each has a single message rather than two that
// drift. "One owner" is only true if the owner actually runs on what the
// traversal produces, so it is asserted here rather than described in a
// comment.
do {
    let bad = Parser.parse(source: """
        @Machine
        enum Arity {
            enum S { case a, b }
            enum A { case x, y }
            static let initial = S.a
            @Row(.a) static let ra = [ .handle, .ignore ]
            @Row(.b) static let rb = [ .handle ]
        }
        """)
    if let decl = bad.statements.first?.item.as(EnumDeclSyntax.self) {
        let raw = try? MachineSyntax.read(decl)
        check(raw != nil, "the traversal reads a machine buildDesc will reject")
        if let raw {
            do {
                _ = try buildDesc(raw)
                check(false, "a short row is rejected by buildDesc")
            } catch let e as TabulaError {
                check(e.code == "tabula::row-arity", "and with the normative code: \(e.code)")
            } catch {
                check(false, "a short row is rejected by buildDesc: \(error)")
            }
        }
    }
}

// MARK: - pending/Machine.swift
//
// Compiled by nothing. It holds the `@Machine` declaration, moved out of the
// build when the manifest had to drop its `.macro` target (see
// `Package.swift`), and it goes back when a SwiftPM ships
// `CompilerPluginSupport`.
//
// Which makes it the single most rot-prone file here: excluded from the build,
// so no compiler reads it, and not due back for months. The restore was going
// to find whatever state it had drifted into, at the moment someone was
// already busy with a toolchain upgrade.
//
// Parsing is not compiling and does not pretend to be. It catches the failure
// that actually happens to an unbuilt file -- an edit that leaves it
// syntactically broken -- and it checks the one fact the restore depends on:
// that `#externalMacro` still names the module `Package.swift` will declare.
do {
    let path = "pending/Machine.swift"
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        check(false, "\(path) is readable")
        exit(1)
    }
    let tree = Parser.parse(source: text)
    check(!tree.hasError, "\(path) is still valid Swift")
    check(
        text.contains(#"#externalMacro(module: "TabulaMacros""#),
        "\(path) still names the module Package.swift will declare")
}

// MARK: - The diagnostics, as fixtures
//
// Swift's half of PLAN's "every diagnostic gets a UI test", and worth being
// exact about what it does and does not reach.
//
// `swift-macro-testing` asserts on macro EXPANSION, which needs a `.macro`
// target, which needs `CompilerPluginSupport`, which this SwiftPM does not
// ship. That is the blocked part and it stays blocked.
//
// What was never blocked is everything underneath it. A macro's job here is
// `SwiftParser` -> `MachineSyntax` -> `buildDesc`, and a malformed matrix is
// rejected by the third step regardless of who called it. So these fixtures
// run the same pipeline the macro would and assert the same diagnostic, in the
// same `//~ EXPECT:` form as `tools/compile-fail` and the KSP harness.
//
// The one property this cannot check is the one expansion adds: that the error
// arrives attached to a source position. The Kotlin harness checks exactly
// that and this cannot, which is the honest size of the remaining gap -- one
// property, not the whole item.
do {
    let dir = "fixtures"
    let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).sorted()
    check(!names.isEmpty, "there are diagnostic fixtures")

    for name in names {
        let path = "\(dir)/\(name)/Spec.tb.swift"
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            check(false, "\(name): Spec.tb.swift is readable")
            continue
        }
        guard let expect = text.split(separator: "\n")
            .first(where: { $0.hasPrefix("//~ EXPECT: ") })
            .map({ String($0.dropFirst("//~ EXPECT: ".count)) })
        else {
            check(false, "\(name): has a '//~ EXPECT:' line")
            continue
        }

        let tree = Parser.parse(source: text)
        guard let decl = tree.statements.compactMap({
            $0.item.as(EnumDeclSyntax.self)
        }).first else {
            check(false, "\(name): declares an enum")
            continue
        }

        do {
            let raw = try MachineSyntax.read(decl)
            _ = try buildDesc(raw)
            check(false, "\(name): expected \(expect), but the machine was accepted")
        } catch let e as TabulaError {
            check(e.code == expect, "\(name): \(e.code)")
        } catch {
            // A SyntaxError here means the fixture cannot be READ, which is a
            // broken fixture rather than a diagnostic -- the traversal is not
            // where these rules live.
            check(false, "\(name): expected \(expect), got \(error)")
        }
    }
}

// MARK: - A spine that works
//
// Every fixture in `fixtures/` is a REJECTION, so none of them reaches
// `derive` -- the check that turns a HANDLE named by a hop into a GO. Swift's
// half of that was written with nothing exercising it, which is the blind spot
// Kotlin had until KSP's Spine output was compared against a stated twin.
//
// Asserted through `emit` rather than by matching on `CellDesc`: what a reader
// cares about is that the cell stopped being a required member, and the
// emitted surface says so in a way that does not depend on the shape of an
// enum this file has no other reason to know.
do {
    let source = """
        @Machine
        @Path("connect", [.idle, .start, .connecting, .ready, .live])
        enum Spine {
            enum S { case idle, connecting, live, failed }
            enum A { case start, ready, drop }
            enum F {}

            final class Ctx {}

            static let initial = S.idle

            //                                  start     ready     drop
            @Row(.idle)       static let i = [ .handle,  .ignore,  .ignore ]
            @Row(.connecting) static let c = [ .ignore,  .handle,  .go(.failed) ]
            @Row(.live)       static let l = [ .ignore,  .ignore,  .ignore ]
            @Row(.failed)     static let f = [ .handle,  .ignore,  .ignore ]

            func handle(_ ctx: Ctx, _ state: S, _ action: A) -> Step<S, F> { fatalError() }
        }
        """
    let tree = Parser.parse(source: source)
    if let decl = tree.statements.compactMap({ $0.item.as(EnumDeclSyntax.self) }).first {
        do {
            let desc = try buildDesc(MachineSyntax.read(decl))
            let out = emit(desc)
            // On the spine: written HANDLE, generated GO, so no member.
            check(!out.contains("idleStart"), "a hop's HANDLE stops being a cell member")
            check(!out.contains("connectingReady"), "and so does the second hop's")
            // Off the spine: no hop names it, so it stays a member. Without
            // this the check would pass if `derive` rewrote everything.
            check(out.contains("failedStart"), "a HANDLE no hop names stays a member")
        } catch {
            check(false, "the spine machine is accepted: \(error)")
        }
    } else {
        check(false, "the spine machine parses")
    }
}

// MARK: - Nested payload types are qualified
//
// The generated cell protocol sits at file scope, and an effect handler's
// parameter type is copied into it. `Reason` declared inside `enum Timer`
// resolves there as written and nowhere else, so `MachineSyntax` qualifies
// every reference to a type the machine nests. What must be left alone is as
// much the test as what must change: a module type, an already-qualified
// type, and `Timer` itself.
do {
    let source = """
        @Machine
        enum Timer {
            enum S { case idle, running(since: Instant) }
            enum A { case start, stop }
            enum F {
                case stopClock(reason: Reason)
                case log(lines: [Reason], kind: Reason.Kind, count: Swift.Int, again: Timer.Reason)
            }
            enum Reason { case cancelled; enum Kind { case soft } }
            struct Instant {}
            final class Ctx {}
            static let initial = S.idle

            //                             start     stop
            @Row(.idle)    static let i = [ .ignore,  .ignore ]
            @Row(.running) static let r = [ .ignore,  .ignore ]

            func handle(_ ctx: Ctx, _ state: S, _ action: A) -> Step<S, F> { fatalError() }
        }
        """
    let tree = Parser.parse(source: source)
    if let decl = tree.statements.compactMap({ $0.item.as(EnumDeclSyntax.self) }).first {
        do {
            let raw = try MachineSyntax.read(decl)
            let types = raw.effects.flatMap { $0.fields.map(\.type) }
            let want = ["Timer.Reason", "[Timer.Reason]", "Timer.Reason.Kind", "Swift.Int", "Timer.Reason"]
            check(types == want, "effect payload types are qualified exactly where nested: got \(types)")
            check(
                raw.states.count > 1 && raw.states[1].fields.first?.type == "Timer.Instant",
                "a state payload's nested type is qualified too")
            let out = emit(try buildDesc(raw))
            check(
                out.contains("_ effect: Timer.Reason)"),
                "the file-scope protocol names the qualified type")
        } catch {
            check(false, "the nested-type machine is accepted: \(error)")
        }
    } else {
        check(false, "the nested-type machine parses")
    }
}

check(TabulaMacroSyntax.surface == "see SURFACE.md", "the module links")

print("")
print("macro syntax checks: \(failed) failed")
if failed > 0 { exit(1) }
