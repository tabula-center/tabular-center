// swift-tools-version: 5.9
//
// The macro package.
//
// For a long stretch this manifest could not declare a `.macro` target at all:
// nixpkgs' SwiftPM shipped no `CompilerPluginSupport`, so `Package.swift`
// failed to COMPILE -- before dependency resolution, which is why vendoring
// swift-syntax would not have helped and why the fix had to come first.
//
// `tabular-center-swift/nix/swiftpm-plugin-support.nix` builds the module now, rebuilding
// `PackageDescription` alongside it because `CompilerPluginSupport` reaches
// its internals through `@_spi` and nixpkgs ships only a public interface.
// `tools/verify swift-macro-support` reports whether the toolchain in hand has
// it, so this manifest failing again says which problem it is.
//
// It is NOT unblocked yet, and the distance is one fact. The manifest loader
// compiles against the SwiftPM the `swift` driver points at, which is still
// nixpkgs' original --
//
//   -L /nix/store/...-swiftpm-5.10.1/lib/swift/pm/ManifestAPI
//
// -- and not the augmented copy. Putting the augmented package in `swiftPkgs`
// puts its `bin` on PATH; it does not change which ManifestAPI `swift build`
// reaches for. So the `.macro` target stays out until `tools/verify
// swift-macro-support` reports the augmented directory in use. The macro is
// written and waiting in `pending/TabularCenterMacros/`.

import PackageDescription

let package = Package(
    name: "TabularCenterMacros",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "TabularCenterMacroSyntax", targets: ["TabularCenterMacroSyntax"]),
    ],
    dependencies: [
        .package(path: ".."),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "509.0.0"),
    ],
    targets: [
        // The checks. An executable, not a test target: nixpkgs' Swift ships
        // no XCTest, the same constraint the main package records.
        .executableTarget(
            name: "TabularCenterMacroSyntaxCheck",
            // `exclude` is not needed for `pending/` -- it is outside
            // Sources/ -- but the checks READ it, along with SURFACE.md, by
            // relative path from the package root. Both are inputs to a test
            // rather than sources, which is why neither is a target.
            dependencies: [
                "TabularCenterMacroSyntax",
                .product(name: "TabularCenterCodegen", package: "tabular-center-swift"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
            ]
        ),
        // The only target in the repository that links swift-syntax, which is
        // the whole reason this is a separate package: `nix flake check`
        // builds the rest of Swift with no network at all.
        .target(
            name: "TabularCenterMacroSyntax",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                // The generator, already written and already tested. This
                // package's only job is SwiftSyntax -> RawMachine; everything
                // after that is TabularCenterCodegen's.
                .product(name: "TabularCenterCodegen", package: "tabular-center-swift"),
            ]
        )
    ]
)
