// The macro package's checks.
//
// A plain executable with a hand-rolled assertion harness, not a test target,
// for the reason `tabular-center-swift/Package.swift` records: nixpkgs' Swift ships no
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
import TabularCenterCodegen
import TabularCenterMacroSyntax

func containsText(_ haystack: some StringProtocol, _ needle: some StringProtocol) -> Bool {
    if needle.isEmpty { return true }
    var rest = Substring(haystack)
    while !rest.isEmpty {
        if rest.starts(with: needle) { return true }
        rest = rest.dropFirst()
    }
    return false
}

var failed = 0

func check(_ ok: Bool, _ what: String) {
    if ok {
        print("ok   \(what)")
    } else {
        print("FAIL \(what)")
        failed += 1
    }
}

func surfaceDeclaration() -> String {
    let path = "SURFACE.md"
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        print("FAIL could not read \(path) (run from tabular-center-swift/macros)")
        exit(1)
    }
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

        let desc = try buildDesc(raw)
        check(desc.machine == "Turnstile", "buildDesc accepts what the traversal produces")
    } catch {
        check(false, "the traversal reads the surface: \(error)")
    }
}

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
                containsText(e.message, "array literal") && containsText(e.message, ".a"),
                "the error names what was found and where: \(e.message)")
        }
    }
}

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
            } catch let e as TabularCenterError {
                check(e.code == "tabular-center::row-arity", "and with the normative code: \(e.code)")
            } catch {
                check(false, "a short row is rejected by buildDesc: \(error)")
            }
        }
    }
}

do {
    let path = "pending/Machine.swift"
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        check(false, "\(path) is readable")
        exit(1)
    }
    let tree = Parser.parse(source: text)
    check(!tree.hasError, "\(path) is still valid Swift")
    check(
        containsText(text, #"#externalMacro(module: "TabularCenterMacros""#),
        "\(path) still names the module Package.swift will declare")
}

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
        } catch let e as TabularCenterError {
            check(e.code == expect, "\(name): \(e.code)")
        } catch {
            check(false, "\(name): expected \(expect), got \(error)")
        }
    }
}

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
            check(!containsText(out, "func idleStart(_ ctx"), "a hop's HANDLE stops being a cell member")
            check(!containsText(out, "func connectingReady(_ ctx"), "and so does the second hop's")
            check(containsText(out, "static func idleStart(_ cells"), "the hop gets its narrowed member instead")
            check(containsText(out, "func failedStart(_ ctx"), "a HANDLE no hop names stays a member")
        } catch {
            check(false, "the spine machine is accepted: \(error)")
        }
    } else {
        check(false, "the spine machine parses")
    }
}

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
                containsText(out, "_ effect: Timer.Reason)"),
                "the file-scope protocol names the qualified type")
        } catch {
            check(false, "the nested-type machine is accepted: \(error)")
        }
    } else {
        check(false, "the nested-type machine parses")
    }
}

do {
    let source = """
        @Machine
        enum Gate {
            enum S { case shut, open }
            enum A { case push }
            enum F { case chime, log(line: String) }
            final class Ctx {}
            static let initial = S.shut

            //                          push
            @Row(.shut) static let a = [ .go(.open, effects: [.chime, .log(line: "x")]) ]
            @Row(.open) static let b = [ .emit([.log(line: "y")]) ]

            func handle(_ ctx: Ctx, _ state: S, _ action: A) -> Step<S, F> { fatalError() }
        }
        """
    let tree = Parser.parse(source: source)
    if let decl = tree.statements.compactMap({ $0.item.as(EnumDeclSyntax.self) }).first {
        do {
            let raw = try MachineSyntax.read(decl)
            let goCell = raw.rows[0].cells[0]
            let emitCell = raw.rows[1].cells[0]
            check(
                goCell.effects == ["chime", "log(line: \"x\")"],
                "a GO keeps its effect arguments: got \(goCell.effects)")
            check(
                emitCell.effects == ["log(line: \"y\")"],
                "an EMIT keeps its effect arguments: got \(emitCell.effects)")
            let out = emit(try buildDesc(raw))
            check(
                containsText(out, ".log(line: \"x\")"),
                "the dispatcher emits the call verbatim")
            check(
                containsText(out, "effects: [\"chime\", \"log\"]"),
                "TABLE records the effect name without its arguments")
        } catch {
            check(false, "the machine with effect arguments is accepted: \(error)")
        }
    } else {
        check(false, "the machine with effect arguments parses")
    }
}

do {
    let source = """
        @Machine
        @Path("checkout", [.cart, .next, .addr, .next, .done], back: .back)
        enum Checkout {
            enum S { case cart, addr, done }
            enum A { case next, back }
            enum F {}

            final class Ctx {}

            static let initial = S.cart

            //                            next      back
            @Row(.cart) static let c = [ .handle,  .ignore ]
            @Row(.addr) static let a = [ .handle,  .handle ]
            @Row(.done) static let d = [ .ignore,  .handle ]

            func handle(_ ctx: Ctx, _ state: S, _ action: A) -> Step<S, F> { fatalError() }
        }
        """
    let tree = Parser.parse(source: source)
    if let decl = tree.statements.compactMap({ $0.item.as(EnumDeclSyntax.self) }).first {
        do {
            let raw = try MachineSyntax.read(decl)
            check(raw.paths.first?.back == "back", "the back action is read from the attribute")

            let out = emit(try buildDesc(raw))
            check(!containsText(out, "func addrBack(_ ctx"), "a hop's far side stops being a cell member")
            check(!containsText(out, "func cartNext(_ ctx"), "and the forward direction still does")
            check(containsText(out, "static func cartNext(_ cells"), "the forward hop gets its narrowed member")
            check(!containsText(out, "addrBack(_ cells"), "a backward hop gets none yet")
            check(!containsText(out, "doneBack"), "the end's back cell derives rather than demanding code")
        } catch {
            check(false, "the machine with a back action is accepted: \(error)")
        }
    } else {
        check(false, "the machine with a back action parses")
    }
}

check(TabularCenterMacroSyntax.surface == "see SURFACE.md", "the module links")

print("")
print("macro syntax checks: \(failed) failed")
if failed > 0 { exit(1) }
