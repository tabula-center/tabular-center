// swift-tools-version: 5.9
//
// No `import CompilerPluginSupport`, and no `.macro` target. That is not a
// simplification — it is the only shape that compiles here.
//
// nixpkgs' swiftpm 5.10.1 does not ship `CompilerPluginSupport` in its
// ManifestAPI, so the manifest that declared a `.macro` target failed to
// *compile*, before dependency resolution was attempted:
//
//     error: 'macros': Invalid manifest
//     Package.swift:5:8: error: no such module 'CompilerPluginSupport'
//
// A vendored swift-syntax would not have helped: nothing had got far enough to
// want a dependency. The manifest has to build before the dependency question
// is even askable, which is why this change comes before `tools/swift-lock`.
//
// ## What this costs
//
// `TabulaMacroDecl` is gone from the build, and with it the `@Machine`
// declaration — `#externalMacro` names a module that SwiftPM only wires up for
// a `.macro` target, so declaring it without one produces a macro nobody can
// apply. The file is kept in `pending/`; restoring it is adding the target
// back, on a SwiftPM that ships the module.
//
// ## What it buys, which is most of it
//
// `MachineMacro`'s job is SwiftSyntax nodes to a `RawMachine` and nothing else
// (SURFACE.md). That traversal is an ordinary function over syntax trees: it
// can be written, built and unit-tested here by parsing source with
// `SwiftParser` and feeding it the result. Macro *expansion* is the only part
// that needs the plugin wiring, and it is the part with no logic in it.
//
// So the two questions SURFACE.md left open — whether `@Row` can attach to a
// stored property, and whether nested enums can be read from the attached
// declaration's members — become answerable by a test rather than by a
// toolchain upgrade. That is the reason to do it this way round rather than
// wait.
import PackageDescription

let package = Package(
    name: "TabulaMacros",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "TabulaMacroSyntax", targets: ["TabulaMacroSyntax"])
    ],
    dependencies: [
        .package(path: ".."),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "509.0.0"),
    ],
    targets: [
        // The checks. An executable, not a test target: nixpkgs' Swift ships
        // no XCTest, the same constraint the main package records.
        .executableTarget(
            name: "TabulaMacroSyntaxCheck",
            // `exclude` is not needed for `pending/` -- it is outside
            // Sources/ -- but the checks READ it, along with SURFACE.md, by
            // relative path from the package root. Both are inputs to a test
            // rather than sources, which is why neither is a target.
            dependencies: [
                "TabulaMacroSyntax",
                .product(name: "TabulaCodegen", package: "swift"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
            ]
        ),
        // The only target in the repository that links swift-syntax, which is
        // the whole reason this is a separate package: `nix flake check`
        // builds the rest of Swift with no network at all.
        .target(
            name: "TabulaMacroSyntax",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                // The generator, already written and already tested. This
                // package's only job is SwiftSyntax -> RawMachine; everything
                // after that is TabulaCodegen's.
                .product(name: "TabulaCodegen", package: "swift"),
            ]
        )
    ]
)
