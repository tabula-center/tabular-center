/// SwiftSyntax nodes to a `RawMachine`, and nothing else.
///
/// That restraint is the design, not modesty. `TabulaCodegen` already turns a
/// `RawMachine` into a `MachineDesc` with every diagnostic in
/// `spec/diagnostics.md` and emits the source, and all of it runs without
/// swift-syntax. So the piece that needs swift-syntax is kept as small and as
/// dumb as possible: it reads syntax into strings and stops.
///
/// Which means **every rule is checked exactly once, and not here**. Row
/// arity, unknown states, `GO` targets that name nothing — `buildDesc` owns
/// all of them, produces the normative text from `spec/diagnostics.md`, and is
/// covered by `TabulaCodegenCheck`.
///
/// One owner per rule is not an unchecked path, and the two read alike from a
/// distance while behaving nothing alike. A rule checked in two places is a
/// rule with two messages that drift, and the drift is found by a user hitting
/// the stale one. So the handover is asserted rather than described:
/// `TabulaMacroSyntaxCheck` runs `buildDesc` on what this file produces and
/// requires the diagnostics to still fire, with their normative codes.
///
/// The errors below are the one category `buildDesc` cannot see — syntax that
/// cannot be read at all. By the time it holds a `RawMachine`, whatever was
/// unreadable is already gone.
///
/// The surface this reads is `SURFACE.md`, which is normative for it.
import SwiftSyntax
import TabulaCodegen

public enum MachineSyntax {
    /// Read an `@Machine`-attached enum into a `RawMachine`.
    ///
    /// Produces whatever the source says, including machines `buildDesc` will
    /// reject. That is the contract: reading and judging are separate steps, so
    /// judging can be tested without a toolchain that can expand macros.
    public static func read(_ decl: EnumDeclSyntax) throws -> RawMachine {
        let machine = decl.name.text
        let members = decl.memberBlock.members.map(\.decl)

        let enums = members.compactMap { $0.as(EnumDeclSyntax.self) }
        // Every type the machine's enum declares. A payload field naming one
        // is qualified by the machine -- see `qualified(_:machine:nested:)`.
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

        // Happy paths, read the same way rows are. See `spec/happy-paths.md`.
        //
        // Attached to the same declaration `@Machine` is, so they come off
        // `decl.attributes` rather than out of the members -- `@Row` hangs on
        // a stored property because a row belongs to one state, and a path
        // belongs to the machine.
        //
        // No validation. `buildDesc` owns all four `path-*` codes, so a route
        // naming a state that does not exist is rejected there with the
        // normative message rather than twice with two.
        // Bound with an explicit type, which is not decoration.
        //
        // `decl.attributes.compactMap { $0.as(AttributeSyntax.self) }` on its
        // own infers `[AttributeSyntax]` -- `row()` below does exactly that and
        // compiles -- but chaining `.filter` and `.compactMap` straight onto it
        // gives the inferencer enough room to keep the element optional:
        //
        //   error: value of optional type 'AttributeSyntax?' must be unwrapped
        //   to refer to member 'attributeName'
        //
        // Naming the type ends the argument in one line rather than sprinkling
        // `?` through a chain that was already correct.
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
                // `back:` is the third argument and labelled, so every
                // `@Path("name", [..])` already written stays valid.
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

    /// The names of the types a machine's enum declares inside itself.
    ///
    /// `S`, `A`, `F` and `Ctx` among them, and anything else the developer
    /// nests: `enum Reason`, `struct Running`, a `typealias`.
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

    /// `type` as written, with every reference to a type nested in the
    /// machine qualified by the machine's name.
    ///
    /// Why this is needed: the generated cell protocol sits at FILE scope, so
    /// a parent can refine it (`protocol JobCells: RetryCells`), and an effect
    /// handler's parameter type is copied into it. Inside `enum Timer`,
    /// `case stopClock(reason: Reason)` resolves `Reason` to `Timer.Reason`;
    /// copied verbatim into `protocol TimerCells`, it resolves to nothing.
    ///
    /// Why here: this is the only place that can answer "is `Reason` nested in
    /// this machine?". The emitter sees strings, and a string cannot tell a
    /// nested `Reason` from a module-level one.
    ///
    /// Every unqualified type reference is an `IdentifierTypeSyntax` -- inside
    /// `[Reason]`, `Reason?`, `Result<Reason, E>`, and as the base of
    /// `Reason.Kind` -- while an already-qualified `Timer.Reason` has `Timer`
    /// as its base, which is not nested and so is left alone. Qualifying
    /// exactly those nodes, by byte offset, rewrites nothing else about how
    /// the developer wrote the type.
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

    /// The text of a plain string literal, or nil if it is not one.
    ///
    /// `representedLiteralValue` does this in one call and is swift-syntax 510;
    /// `tabular-center-swift/nix/swift-lock.json` pins 509.1.1, so the segments are read directly.
    ///
    /// Returning nil for an interpolated literal is the correct answer rather
    /// than a limitation. `@Path("connect", ...)` names a path, and a name
    /// assembled at run time cannot be one -- the generator emits a member
    /// called after it, at compile time. A literal is the only thing that can
    /// work, so anything else is not a path this file can read.
    static func literalText(_ lit: StringLiteralExprSyntax) -> String? {
        var out = ""
        for segment in lit.segments {
            guard let piece = segment.as(StringSegmentSyntax.self) else { return nil }
            out += piece.content.text
        }
        return out
    }

    // MARK: - Pieces

    /// Cases in **declaration order**, with their associated values.
    ///
    /// Order is meaning: a row's cells line up with these by position, which is
    /// what makes a matrix reviewable and what `tabula::row-arity` checks. A
    /// traversal that sorted, or that used a dictionary anywhere on this path,
    /// would lose the property the library exists for.
    ///
    /// Field types are qualified against the machine: see
    /// `qualified(_:machine:nested:)`.
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
            return array.elements.compactMap { effectRef($0.expression) }
        }
        return effectRef(expr).map { [$0] } ?? []
    }

    /// One effect as a static cell names it, ARGUMENTS INCLUDED:
    /// `stopClock`, or `stopClock(reason: .cancelled)`.
    ///
    /// A payload-carrying effect is written as a call, so it parses as a
    /// `FunctionCallExprSyntax` wrapping the member access. Matching only the
    /// member access -- which this did until September 2026 -- made every such
    /// effect vanish from the machine silently: not a diagnostic, not a
    /// malformed cell, just a GO that emits nothing.
    ///
    /// The text is kept as the developer wrote it, so the dispatcher can emit
    /// the call verbatim. `effectName` takes the part before `(` where only
    /// the name is wanted -- validation, and `TABLE`, which is inert data
    /// about which effect a cell emits and not with what.
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
