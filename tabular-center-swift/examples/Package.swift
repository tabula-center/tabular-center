// swift-tools-version: 5.7
//
// A separate package that depends on TabularCenter BY PATH, the way a user would —
// the same reason the Rust examples sit outside the cargo workspace. It is the
// only place the public API is exercised from outside.
//
// ## Why this directory is not called `swift`
//
// SwiftPM derives a path dependency's *identity* from its directory basename.
// With the library at `swift/` (as it was before the tabular-center rename)
// and these examples at `examples/swift/`, both resolved to the identity
// `swift`, and SwiftPM reported
//
//     cyclic dependency declaration found: TabularCenterExamples -> TabularCenterExamples
//
// — the package appearing to depend on itself. The directory is
// `tabular-center-swift/examples` so the two identities differ. The library is
// `tabular-center-swift/` now, so the clash is gone, but the name stays: it
// costs nothing and the next rename should not have to rediscover this. It breaks the
// symmetry with `tabular-center-rust/examples` and `tabular-center-kotlin/examples`, which is a smaller cost
// than a package that cannot resolve.
import PackageDescription

let package = Package(
    name: "TabularCenterExamples",
    products: [
        .executable(name: "traffic-light", targets: ["TrafficLight"]),
        .executable(name: "timer", targets: ["Timer"]),
        .executable(name: "retry", targets: ["Retry"]),
        .executable(name: "login", targets: ["Login"]),
        .executable(name: "observable-counter", targets: ["ObservableCounter"]),
        .executable(name: "spec-check", targets: ["SpecCheck"]),
    ],
    dependencies: [
        .package(path: "..")
    ],
    targets: [
        .target(name: "ExampleCheck"),

        .executableTarget(
            name: "TrafficLight",
            dependencies: [.product(name: "TabularCenter", package: "tabular-center-swift"), "ExampleCheck"]
        ),
        .executableTarget(
            name: "Timer",
            dependencies: [.product(name: "TabularCenter", package: "tabular-center-swift"), "ExampleCheck"]
        ),
        .executableTarget(
            name: "Retry",
            dependencies: [.product(name: "TabularCenter", package: "tabular-center-swift"), "ExampleCheck"]
        ),
        .executableTarget(
            name: "Login",
            dependencies: [.product(name: "TabularCenter", package: "tabular-center-swift"), "ExampleCheck"]
        ),
        .executableTarget(
            name: "ObservableCounter",
            dependencies: [.product(name: "TabularCenter", package: "tabular-center-swift"), "ExampleCheck"]
        ),
        .executableTarget(
            name: "SpecCheck",
            dependencies: [
                .product(name: "TabularCenter", package: "tabular-center-swift"),
                .product(name: "TabularCenterTesting", package: "tabular-center-swift"),
                "ExampleCheck",
            ]
        ),
    ]
)
