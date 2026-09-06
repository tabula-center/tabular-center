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
        .executable(name: "tabula-examples", targets: ["Examples"])
    ],
    dependencies: [
        .package(path: "../../swift")
    ],
    targets: [
        // `package: "swift"` is the DIRECTORY name of the path dependency, not
        // the `name` in its manifest — SwiftPM identifies path dependencies by
        // directory, and said so itself:
        //
        //   unknown package 'Tabula' ... valid packages are: 'swift'
        //
        // The bare `dependencies: ["Tabula"]` form does not work either: by-name
        // lookup matches the *package* name `Tabula` and resolves to this
        // package.
        .executableTarget(
            name: "Examples",
            dependencies: [.product(name: "Tabula", package: "swift")]
        )
    ]
)
