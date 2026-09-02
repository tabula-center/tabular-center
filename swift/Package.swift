// swift-tools-version: 5.7
//
// 5.7, not the latest. nixpkgs 25.05 ships Swift 5.8, and a tools-version
// above the toolchain is a hard refusal rather than a warning. Nothing here
// needs anything newer: conditional conformance is 4.2, async closures are
// 5.5. Raise it when TabulaMacros lands, since macros genuinely need 5.9 --
// and that will need a newer toolchain than the pinned nixpkgs provides.
import PackageDescription

// Three products, matching RELEASING.md. `Tabula` is the runtime and has no
// dependencies at all; `TabulaMacros` (the generator) and `TabulaTesting` (the
// fixture harness) are separate so a machine in production carries neither.
//
// TabulaMacros is not here yet: it needs swift-syntax, which is a build-time
// dependency, and adding it before the core compiles would make a first
// failure ambiguous between the two.
let package = Package(
    name: "Tabula",
    products: [
        .library(name: "Tabula", targets: ["Tabula"])
    ],
    targets: [
        .target(name: "Tabula"),
        .testTarget(name: "TabulaTests", dependencies: ["Tabula"]),
    ]
)
