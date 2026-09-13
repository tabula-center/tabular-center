// swift-tools-version: 5.9
//
// UNVERIFIED: this package cannot be built where there is no network, which is
// the entire reason it is a separate package. See README.md.
import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "TabulaMacros",
    platforms: [.macOS(.v13)],
    products: [
        // What a user imports. The implementation is an implementation detail
        // and is deliberately not a product.
        .library(name: "TabulaMacroDecl", targets: ["TabulaMacroDecl"])
    ],
    dependencies: [
        .package(path: ".."),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "509.0.0"),
    ],
    targets: [
        // The compiler plugin. This is the only target in the repository that
        // links swift-syntax, and keeping it alone in its own package is what
        // lets `nix flake check` build the rest of Swift with no network.
        .macro(
            name: "TabulaMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                // The generator, already written and already tested. This
                // package's only job is SwiftSyntax -> RawMachine; everything
                // after that is TabulaCodegen's.
                .product(name: "TabulaCodegen", package: "swift"),
            ]
        ),
        .target(name: "TabulaMacroDecl", dependencies: ["TabulaMacros"]),
    ]
)
