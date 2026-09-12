// swift-tools-version: 5.7
import PackageDescription

// A separate package that depends on Tabula BY PATH, the way a user would —
// the same reason the Rust examples sit outside the cargo workspace. It is the
// only place the public API is exercised from outside.
//
// ## Why this directory is not called `swift`
//
// SwiftPM derives a path dependency's *identity* from its directory basename.
// With the library at `swift/` and these examples at `examples/swift/`, both
// resolve to the identity `swift`, and SwiftPM reports
//
//     cyclic dependency declaration found: TabulaExamples -> TabulaExamples
//
// — the package appearing to depend on itself. The directory is
// `examples/swift-examples` so the two identities differ. It breaks the
// symmetry with `examples/rust` and `examples/kotlin`, which is a smaller cost
// than a package that cannot resolve.
let package = Package(
    name: "TabulaExamples",
    products: [
        .executable(name: "traffic-light", targets: ["TrafficLight"]),
        .executable(name: "timer", targets: ["Timer"]),
        .executable(name: "retry", targets: ["Retry"]),
        .executable(name: "login", targets: ["Login"]),
        .executable(name: "observable-counter", targets: ["ObservableCounter"]),
        .executable(name: "spec-check", targets: ["SpecCheck"]),
    ],
    dependencies: [
        .package(path: "../../swift")
    ],
    targets: [
        // The assertion harness, as its own target, so every example depends
        // on it explicitly rather than sharing a module by accident.
        .target(name: "ExampleCheck"),

        // One target per example. Each has its own dependency line, which is
        // the configuration axis here: `TrafficLight` names `Tabula` and
        // nothing else, and would stop building the day an example started
        // needing more than the runtime.
        //
        // `package: "swift"` is the DIRECTORY name of the path dependency, not
        // the `name` in its manifest -- SwiftPM identifies path dependencies
        // by directory, and said so itself:
        //
        //   unknown package 'Tabula' ... valid packages are: 'swift'
        //
        // The bare `dependencies: ["Tabula"]` form does not work either: by-name
        // lookup matches the *package* name `Tabula` and resolves to this
        // package.
        .executableTarget(
            name: "TrafficLight",
            dependencies: [.product(name: "Tabula", package: "swift"), "ExampleCheck"]
        ),
        .executableTarget(
            name: "Timer",
            dependencies: [.product(name: "Tabula", package: "swift"), "ExampleCheck"]
        ),
        .executableTarget(
            name: "Retry",
            dependencies: [.product(name: "Tabula", package: "swift"), "ExampleCheck"]
        ),
        .executableTarget(
            name: "Login",
            dependencies: [.product(name: "Tabula", package: "swift"), "ExampleCheck"]
        ),
        // The only target whose checks can report `skip`. ObservableStore is
        // Darwin only, so off Darwin this builds, runs, checks the machine,
        // and says so rather than passing silently or failing loudly.
        .executableTarget(
            name: "ObservableCounter",
            dependencies: [.product(name: "Tabula", package: "swift"), "ExampleCheck"]
        ),
        // The only target that names TabulaTesting. That product ships in the
        // library's manifest and, until this example, nothing outside the
        // library had ever imported it.
        .executableTarget(
            name: "SpecCheck",
            dependencies: [
                .product(name: "Tabula", package: "swift"),
                .product(name: "TabulaTesting", package: "swift"),
                "ExampleCheck",
            ]
        ),
    ]
)
