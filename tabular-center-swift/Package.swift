// swift-tools-version: 5.9
//
// Raised from 5.7. The floor was kept low deliberately — nothing in the core
// needs newer, and a low tools-version works on any toolchain above it — and
// it was always going to move once, for a reason, rather than twice. The
// reason is 5.9: both `@Observable` and macros need it, so `ObservableStore`
// and `TabularCenterMacros` are one decision, not two.
//
// There is still **no `platforms:` clause**, and that is the part worth
// keeping. A deployment target here is a floor for every consumer, and a
// consumer using `Store` on an older OS should not pay for a type they never
// import. `ObservableStore` carries `@available` instead, so it is the only
// thing in the package that needs macOS 14 / iOS 17.
//
// The pinned toolchain is 5.10.1 (`nixpkgs-swift`, tracking nixos-unstable),
// so 5.9 is below it rather than at it.
//
// Products match RELEASING.md. `TabularCenter` is the runtime and has no dependencies
// at all; `TabularCenterMacros` (the generator) and `TabularCenterTesting` (the fixture
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
import PackageDescription

let package = Package(
    name: "TabularCenter",
    products: [
        .library(name: "TabularCenter", targets: ["TabularCenter"]),
        .library(name: "TabularCenterTesting", targets: ["TabularCenterTesting"]),
        .library(name: "TabularCenterCodegen", targets: ["TabularCenterCodegen"]),
        .executable(name: "tabular-center-check", targets: ["TabularCenterCheck"]),
        .executable(name: "tabular-center-conformance", targets: ["TabularCenterConformance"]),
        .executable(name: "tabular-center-codegen-check", targets: ["TabularCenterCodegenCheck"]),
    ],
    targets: [
        .target(name: "TabularCenter"),
        .target(name: "TabularCenterTesting", dependencies: ["TabularCenter"]),
        .target(name: "TabularCenterCodegen"),
        .executableTarget(name: "TabularCenterCodegenCheck", dependencies: ["TabularCenterCodegen"]),
        .executableTarget(name: "TabularCenterCheck", dependencies: ["TabularCenter"]),
        .executableTarget(
            name: "TabularCenterConformance",
            dependencies: ["TabularCenter", "TabularCenterTesting"]
        ),
    ]
)
