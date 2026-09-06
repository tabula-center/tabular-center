// swift-tools-version: 5.7
//
// 5.7, not the latest. Nothing in the core needs newer — conditional
// conformance is 4.2, async closures are 5.5 — and a low tools-version works
// on any toolchain above it. Raise it when TabulaMacros lands; macros need 5.9.
import PackageDescription

// Products match RELEASING.md. `Tabula` is the runtime and has no dependencies
// at all; `TabulaMacros` (the generator) and `TabulaTesting` (the fixture
// harness) will be separate so a machine in production carries neither.
//
// ## Why the checks are an executable and not a test target
//
// nixpkgs' Swift does not ship XCTest:
//
//     error: no such module 'XCTest'
//
// Rather than depend on a framework the toolchain may not have, the checks are
// a plain executable with a thirty-line assertion harness — exactly what the
// Kotlin side does, and for the same reason: a test framework that has to be
// resolved is a test framework that can stop the tests from running at all.
//
// The cost is no `swift test` integration and no per-test isolation. Worth it
// for a library whose whole point is that its guarantees are checkable
// anywhere.
let package = Package(
    name: "Tabula",
    products: [
        .library(name: "Tabula", targets: ["Tabula"]),
        .library(name: "TabulaTesting", targets: ["TabulaTesting"]),
        .executable(name: "tabula-check", targets: ["TabulaCheck"]),
        .executable(name: "tabula-conformance", targets: ["TabulaConformance"]),
        .executable(name: "tabula-codegen-check", targets: ["TabulaCodegenCheck"]),
    ],
    targets: [
        .target(name: "Tabula"),
        // Depends on Tabula and nothing else -- no Foundation. A published
        // library should not put the whole of Foundation on a consumer's link
        // line in order to trim a string.
        .target(name: "TabulaTesting", dependencies: ["Tabula"]),
        // The generator's logic, with NO swift-syntax and no network. A Swift
        // macro implementation must link swift-syntax, which is a remote
        // package; `nix flake check` builds offline, so putting it in this
        // package would break every Swift check rather than only the macro's.
        // The macro, when it lands, parses syntax into a RawMachine and calls
        // buildDesc + emit from here.
        .target(name: "TabulaCodegen"),
        .executableTarget(name: "TabulaCodegenCheck", dependencies: ["TabulaCodegen"]),
        .executableTarget(name: "TabulaCheck", dependencies: ["Tabula"]),
        .executableTarget(
            name: "TabulaConformance",
            dependencies: ["Tabula", "TabulaTesting"]
        ),
    ]
)
