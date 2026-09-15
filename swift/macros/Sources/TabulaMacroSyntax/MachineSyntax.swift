/// SwiftSyntax nodes to a `RawMachine`, and nothing else.
///
/// That restraint is the design, not modesty. `TabulaCodegen` already turns a
/// `RawMachine` into a `MachineDesc` with every diagnostic in
/// `spec/diagnostics.md` and emits the source, and all of it runs without
/// swift-syntax. So the piece that needs swift-syntax is kept as small and as
/// dumb as possible: it reads syntax into strings and stops.
///
/// Which means **no validation here**. Row arity, unknown states, `GO` targets
/// that name nothing — none of it. `buildDesc` produces the normative text for
/// all of those, and a second implementation would be two messages for one
/// error, drifting apart. The errors below are only about syntax that cannot
/// be read at all.
///
/// The surface this reads is `SURFACE.md`, which is normative for it.
import SwiftSyntax
import TabulaCodegen

public enum MachineSyntax {
    /// Read an `@Machine`-attached enum into a `RawMachine`.
    public static func read(_ decl: EnumDeclSyntax) throws -> RawMachine {
        let machine = decl.name.text
        let members = decl.memberBlock.members.map(\.decl)

        let enums = members.compactMap { $0.as(EnumDeclSyntax.self) }
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
        // `F` is optional: a machine with no effects is legal, and
        // `effects-never` plus `payload-hoist` both exercise it.
        let effects = enums.first(where: { $0.name.text == "F" }).map(cases(of:)) ?? []

        guard let initial = initialState(members) else {
            throw SyntaxError(
                "@Machine: `\(machine)` has no `static let initial`; the macro "
                    + "cannot guess which state a machine starts in")
        }

        let rows = try members
            .compactMap { $0.as(VariableDeclSyntax.self) }
            .compactMap { try row($0, machine: machine) }

        // Copied verbatim, never interpreted. `async`, `throws`, `@MainActor`,
        // anything a future Swift ships — the generator stamps whatever is
        // here onto every emitted member, which is how a colored machine stays
        // colored end to end. Deciding which modifiers are meaningful is
        // exactly the judgement this file must not make.
        let prototype = members
            .compactMap { $0.as(FunctionDeclSyntax.self) }
            .first { $0.name.text == "handle" }
        let modifiers = prototype.map(prototypeModifiers(of:)) ?? []

        return RawMachine(
            machine: machine,
            initial: initial,
            states: states,
            actions: actions,
            effects: effects,
            rows: rows,
            prototypeModifiers: modifiers,
            children: children(rows)
        )
    }

    // MARK: - Pieces

    /// Cases in **declaration order**, with their associated values.
    ///
    /// Order is meaning: a row's cells line up with these by position, which is
    /// what makes a matrix reviewable and what `tabula::row-arity` checks. A
    /// traversal that sorted, or that used a dictionary anywhere on this path,
    /// would lose the property the library exists for.
    static func cases(of e: EnumDeclSyntax) -> [RawVariant] {
        e.memberBlock.members
            .compactMap { $0.decl.as(EnumCaseDeclSyntax.self) }
            .flatMap { $0.elements }
            .map { element in
                let params = element.parameterClause?.parameters.map { p in
                    (
                        name: p.firstName?.text ?? "",
                        type: p.type.trimmedDescription
                    )
                } ?? []
                return RawVariant(
                    element.name.text,
                    hasPayload: !params.isEmpty,
                    fields: params
                )
            }
    }

    /// `static let initial = S.locked` — the case name, not the qualified one.
    static func initialState(_ members: [DeclSyntax]) -> String? {
        for v in members.compactMap({ $0.as(VariableDeclSyntax.self) }) {
            for binding in v.bindings
            where binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "initial" {
                guard let value = binding.initializer?.value else { continue }
                if let member = value.as(MemberAccessExprSyntax.self) {
                    return member.declName.baseName.text
                }
                // `S.running(since: 0)` — the case, discarding the payload.
                // Which state a machine starts in is a name; what it starts
                // holding is the caller's business.
                if let call = value.as(FunctionCallExprSyntax.self),
                    let member = call.calledExpression.as(MemberAccessExprSyntax.self) {
                    return member.declName.baseName.text
                }
            }
        }
        return nil
    }

    /// One `@Row(.state) static let x = [ ... ]`, or nil if not a row at all.
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

    /// One cell. `.ignore`, `.go(.x, [.e])`, `.delegate(.child)`, and so on.
    static func cell(_ expr: ExprSyntax, state: String) throws -> RawCell {
        // Bare: `.ignore`, `.handle`, `.unreachable`.
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

    /// `.unlocked` → `("unlocked", "")`; `.running(since: 0)` → the arguments
    /// kept as written, because the generator pastes them into a constructor
    /// call and never reads them.
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

    /// `[.click, .buzz]` → `["click", "buzz"]`. A bare `.click` is accepted
    /// too, because writing brackets around one effect is noise nobody thanks
    /// you for.
    static func effectNames(_ expr: ExprSyntax) -> [String] {
        if let array = expr.as(ArrayExprSyntax.self) {
            return array.elements.compactMap {
                $0.expression.as(MemberAccessExprSyntax.self)?.declName.baseName.text
            }
        }
        if let member = expr.as(MemberAccessExprSyntax.self) {
            return [member.declName.baseName.text]
        }
        return []
    }

    /// Every modifier and effect specifier on `handle`, in source order.
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

    /// Distinct `DELEGATE` targets, in first-seen order.
    static func children(_ rows: [RawRow]) -> [ChildDesc] {
        var seen: [String] = []
        for row in rows {
            for cell in row.cells where cell.kind == "DELEGATE" && !seen.contains(cell.child) {
                seen.append(cell.child)
            }
        }
        // The child's type names follow the same defaults the parent's do.
        // A child whose types are spelled differently is a real case and not
        // this one: `SURFACE.md` has no syntax for saying so yet, and
        // inventing one here rather than there would put the surface in the
        // traversal.
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
/// where, and what was expected instead. `kotlin/ksp` learned the other half
/// the hard way — its `classes()` used `filterIsInstance`, so an unrecognised
/// shape was dropped silently and produced a machine with no states and no
/// error.
public struct SyntaxError: Error, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}
