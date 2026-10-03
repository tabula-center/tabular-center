/// SwiftSyntax nodes to a `RawMachine`, and nothing else.
///
/// That restraint is the design, not modesty. `TabularCenterCodegen` already turns a
/// `RawMachine` into a `MachineDesc` with every diagnostic in
/// `spec/diagnostics.md` and emits the source, and all of it runs without
/// swift-syntax. So the piece that needs swift-syntax is kept as small and as
/// dumb as possible: it reads syntax into strings and stops.
///
/// Which means **every rule is checked exactly once, and not here**. Row
/// arity, unknown states, `GO` targets that name nothing — `buildDesc` owns
/// all of them, produces the normative text from `spec/diagnostics.md`, and is
/// covered by `TabularCenterCodegenCheck`.
///
/// One owner per rule is not an unchecked path, and the two read alike from a
/// distance while behaving nothing alike. A rule checked in two places is a
/// rule with two messages that drift, and the drift is found by a user hitting
/// the stale one. So the handover is asserted rather than described:
/// `TabularCenterMacroSyntaxCheck` runs `buildDesc` on what this file produces and
/// requires the diagnostics to still fire, with their normative codes.
///
/// The errors below are the one category `buildDesc` cannot see — syntax that
/// cannot be read at all. By the time it holds a `RawMachine`, whatever was
/// unreadable is already gone.
///
/// The surface this reads is `SURFACE.md`, which is normative for it.
import SwiftSyntax
import TabularCenterCodegen

public enum MachineSyntax {
    public static func read(_ decl: EnumDeclSyntax) throws -> RawMachine {
        let machine = decl.name.text
        let members = decl.memberBlock.members.map(\.decl)

        let enums = members.compactMap { $0.as(EnumDeclSyntax.self) }
        let nested = nestedTypeNames(members)
        func cases(of e: EnumDeclSyntax) -> [RawVariant] {
            Self.cases(of: e, machine: machine, nested: nested)
        }
        func variants(_ name: String) throws -> [RawVariant] {
            guard let e = enums.first(where: { $0.name.text == name }) else {
                throw SyntaxError(
                    "@Machine: `\(machine)` has no nested `enum \(name)`; "
                        + "states, actions and effects are read from `S`, `A` and `F`")
            }
            return cases(of: e)
        }

        let states = try variants("S")
        let actions = try variants("A")
        let effects = enums.first(where: { $0.name.text == "F" }).map(cases(of:)) ?? []

        guard let initial = initialState(members) else {
            throw SyntaxError(
                "@Machine: `\(machine)` has no `static let initial`; the macro "
                    + "cannot guess which state a machine starts in")
        }

        let rows = try members
            .compactMap { $0.as(VariableDeclSyntax.self) }
            .compactMap { try row($0, machine: machine) }

        let prototype = members
            .compactMap { $0.as(FunctionDeclSyntax.self) }
            .first { $0.name.text == "handle" }
        let modifiers = prototype.map(prototypeModifiers(of:)) ?? []

        let attrs: [AttributeSyntax] = decl.attributes.compactMap {
            $0.as(AttributeSyntax.self)
        }
        let paths = attrs
            .filter { $0.attributeName.trimmedDescription == "Path" }
            .compactMap { attr -> RawPath? in
                guard case let .argumentList(args)? = attr.arguments,
                    args.count >= 2,
                    let name = args.first?.expression
                        .as(StringLiteralExprSyntax.self)
                        .flatMap(literalText),
                    let list = Array(args)[1].expression.as(ArrayExprSyntax.self)
                else { return nil }
                let back = Array(args)
                    .first { $0.label?.text == "back" }?
                    .expression.as(MemberAccessExprSyntax.self)?
                    .declName.baseName.text

                return RawPath(
                    name: name,
                    elements: list.elements.compactMap {
                        $0.expression.as(MemberAccessExprSyntax.self)?
                            .declName.baseName.text
                    },
                    back: back ?? "")
            }

        return RawMachine(
            machine: machine,
            initial: initial,
            states: states,
            actions: actions,
            effects: effects,
            rows: rows,
            prototypeModifiers: modifiers,
            children: children(rows),
            paths: paths
        )
    }

    static func nestedTypeNames(_ members: [DeclSyntax]) -> Set<String> {
        var out: Set<String> = []
        for m in members {
            if let d = m.as(EnumDeclSyntax.self) { out.insert(d.name.text) }
            else if let d = m.as(StructDeclSyntax.self) { out.insert(d.name.text) }
            else if let d = m.as(ClassDeclSyntax.self) { out.insert(d.name.text) }
            else if let d = m.as(ActorDeclSyntax.self) { out.insert(d.name.text) }
            else if let d = m.as(TypeAliasDeclSyntax.self) { out.insert(d.name.text) }
            else if let d = m.as(ProtocolDeclSyntax.self) { out.insert(d.name.text) }
        }
        return out
    }

    static func qualified(_ type: TypeSyntax, machine: String, nested: Set<String>) -> String {
        let finder = NestedReferences(nested)
        finder.walk(type)
        let start = type.positionAfterSkippingLeadingTrivia.utf8Offset
        var bytes = Array(type.trimmedDescription.utf8)
        let prefix = Array("\(machine).".utf8)
        for offset in finder.offsets.sorted(by: >) {
            bytes.insert(contentsOf: prefix, at: offset - start)
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    static func literalText(_ lit: StringLiteralExprSyntax) -> String? {
        var out = ""
        for segment in lit.segments {
            guard let piece = segment.as(StringSegmentSyntax.self) else { return nil }
            out += piece.content.text
        }
        return out
    }

    static func cases(of e: EnumDeclSyntax, machine: String, nested: Set<String>) -> [RawVariant] {
        e.memberBlock.members
            .compactMap { $0.decl.as(EnumCaseDeclSyntax.self) }
            .flatMap { $0.elements }
            .map { element in
                let params = element.parameterClause?.parameters.map { p in
                    (
                        name: p.firstName?.text ?? "",
                        type: qualified(p.type, machine: machine, nested: nested)
                    )
                } ?? []
                return RawVariant(
                    element.name.text,
                    hasPayload: !params.isEmpty,
                    fields: params
                )
            }
    }

    static func initialState(_ members: [DeclSyntax]) -> String? {
        for v in members.compactMap({ $0.as(VariableDeclSyntax.self) }) {
            for binding in v.bindings
            where binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "initial" {
                guard let value = binding.initializer?.value else { continue }
                if let member = value.as(MemberAccessExprSyntax.self) {
                    return member.declName.baseName.text
                }
                if let call = value.as(FunctionCallExprSyntax.self),
                    let member = call.calledExpression.as(MemberAccessExprSyntax.self) {
                    return member.declName.baseName.text
                }
            }
        }
        return nil
    }

    static func row(_ v: VariableDeclSyntax, machine: String) throws -> RawRow? {
        guard let attr = v.attributes.compactMap({ $0.as(AttributeSyntax.self) })
            .first(where: { $0.attributeName.trimmedDescription == "Row" })
        else { return nil }

        guard case let .argumentList(args)? = attr.arguments,
            let first = args.first?.expression.as(MemberAccessExprSyntax.self)
        else {
            throw SyntaxError(
                "@Row: expected the state it belongs to, as in `@Row(.locked)`, "
                    + "found `\(attr.trimmedDescription)`")
        }
        let state = first.declName.baseName.text

        guard let array = v.bindings.first?.initializer?.value.as(ArrayExprSyntax.self) else {
            let found = v.bindings.first?.initializer?.value.trimmedDescription ?? "nothing"
            throw SyntaxError(
                "@Row(.\(state)): expected an array literal of cells, found `\(found)`")
        }

        let cells = try array.elements.map { try cell($0.expression, state: state) }
        return RawRow(state, cells)
    }

    static func cell(_ expr: ExprSyntax, state: String) throws -> RawCell {
        if let member = expr.as(MemberAccessExprSyntax.self) {
            switch member.declName.baseName.text {
            case "ignore": return RawCell("IGNORE")
            case "handle": return RawCell("HANDLE")
            case "unreachable": return RawCell("UNREACHABLE")
            case let other:
                throw SyntaxError(
                    "@Row(.\(state)): `.\(other)` is not a cell; expected one of "
                        + "`.ignore`, `.handle`, `.unreachable`, `.go`, `.emit`, `.delegate`")
            }
        }

        guard let call = expr.as(FunctionCallExprSyntax.self),
            let callee = call.calledExpression.as(MemberAccessExprSyntax.self)
        else {
            throw SyntaxError(
                "@Row(.\(state)): expected a cell, found `\(expr.trimmedDescription)`")
        }

        let args = Array(call.arguments)
        switch callee.declName.baseName.text {
        case "go":
            guard let target = args.first?.expression else {
                throw SyntaxError("@Row(.\(state)): `.go` needs the state to go to")
            }
            let (name, payload) = targetAndArgs(target)
            return RawCell(
                "GO", target: name, args: payload,
                effects: args.count > 1 ? effectNames(args[1].expression) : [])
        case "emit":
            guard let list = args.first?.expression else {
                throw SyntaxError("@Row(.\(state)): `.emit` needs at least one effect")
            }
            return RawCell("EMIT", effects: effectNames(list))
        case "delegate":
            guard let child = args.first?.expression.as(MemberAccessExprSyntax.self) else {
                throw SyntaxError("@Row(.\(state)): `.delegate` needs the child machine")
            }
            return RawCell("DELEGATE", child: child.declName.baseName.text)
        case let other:
            throw SyntaxError(
                "@Row(.\(state)): `.\(other)` is not a cell; expected one of "
                    + "`.ignore`, `.handle`, `.unreachable`, `.go`, `.emit`, `.delegate`")
        }
    }

    static func targetAndArgs(_ expr: ExprSyntax) -> (String, String) {
        if let member = expr.as(MemberAccessExprSyntax.self) {
            return (member.declName.baseName.text, "")
        }
        if let call = expr.as(FunctionCallExprSyntax.self),
            let member = call.calledExpression.as(MemberAccessExprSyntax.self) {
            let inner = call.arguments.map(\.trimmedDescription).joined(separator: ", ")
            return (member.declName.baseName.text, "(\(inner))")
        }
        return (expr.trimmedDescription, "")
    }

    static func effectNames(_ expr: ExprSyntax) -> [String] {
        if let array = expr.as(ArrayExprSyntax.self) {
            return array.elements.compactMap { effectRef($0.expression) }
        }
        return effectRef(expr).map { [$0] } ?? []
    }

    static func effectRef(_ expr: ExprSyntax) -> String? {
        if let member = expr.as(MemberAccessExprSyntax.self) {
            return member.declName.baseName.text
        }
        if let call = expr.as(FunctionCallExprSyntax.self),
            let member = call.calledExpression.as(MemberAccessExprSyntax.self)
        {
            let args = call.arguments.map(\.trimmedDescription).joined(separator: ", ")
            return "\(member.declName.baseName.text)(\(args))"
        }
        return nil
    }

    static func prototypeModifiers(of f: FunctionDeclSyntax) -> [String] {
        var out = f.attributes.compactMap {
            $0.as(AttributeSyntax.self).map { "@" + $0.attributeName.trimmedDescription }
        }
        out += f.modifiers.map(\.name.text)
        if let effects = f.signature.effectSpecifiers {
            if let asyncKeyword = effects.asyncSpecifier { out.append(asyncKeyword.text) }
            if let throwsKeyword = effects.throwsSpecifier { out.append(throwsKeyword.text) }
        }
        return out
    }

    static func children(_ rows: [RawRow]) -> [ChildDesc] {
        var seen: [String] = []
        for row in rows {
            for cell in row.cells where cell.kind == "DELEGATE" && !seen.contains(cell.child) {
                seen.append(cell.child)
            }
        }
        return seen.map {
            ChildDesc(
                alias: $0, stateType: "S", actionType: "A",
                effectType: "F", ctxType: "Ctx")
        }
    }
}

/// Syntax this file cannot read, never a rule it could have checked.
///
/// The bar, from `SURFACE.md` and `spec/diagnostics.md`: name what was found,
/// where, and what was expected instead. `tabular-center-kotlin/ksp` learned the other half
/// the hard way — its `classes()` used `filterIsInstance`, so an unrecognised
/// shape was dropped silently and produced a machine with no states and no
/// error.
public struct SyntaxError: Error, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

/// Where, in a type, the references to machine-nested types start.
private final class NestedReferences: SyntaxVisitor {
    let nested: Set<String>
    var offsets: [Int] = []

    init(_ nested: Set<String>) {
        self.nested = nested
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        if nested.contains(node.name.text) {
            offsets.append(node.positionAfterSkippingLeadingTrivia.utf8Offset)
        }
        return .visitChildren
    }
}
