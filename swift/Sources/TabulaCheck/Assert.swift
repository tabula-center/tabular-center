/// A test harness in thirty lines.
///
/// Not XCTest: nixpkgs' Swift toolchain does not ship it, and a test framework
/// that has to be resolved is a test framework that can stop the tests from
/// running at all. The Kotlin side made the same call about JUnit, for the
/// same reason.
enum Assert {
    // Plain mutable statics. `nonisolated(unsafe)` is Swift 5.10 syntax and
    // this package declares tools-version 5.9; in Swift 5 language mode a
    // mutable static is a concurrency warning at worst, and this harness is
    // single-threaded by construction.
    //
    // The version moved and the conclusion did not: tools-version selects the
    // manifest API, not the language mode, and 5.9 is still Swift 5 mode. If
    // this ever goes to 6, these become errors and the fix is
    // `nonisolated(unsafe)`, which 5.10 will by then accept.
    static var failures = 0
    static var checks = 0

    static func eq<T: Equatable>(_ actual: T, _ expected: T, _ what: String) {
        checks += 1
        if actual != expected {
            failures += 1
            print("FAIL \(what)")
            print("       got      \(actual)")
            print("       expected \(expected)")
        }
    }

    static func ok(_ condition: Bool, _ what: String) {
        checks += 1
        if !condition {
            failures += 1
            print("FAIL \(what)")
        }
    }

    static func throwsError(_ what: String, _ body: () throws -> Void) {
        checks += 1
        do {
            try body()
            failures += 1
            print("FAIL \(what): expected a throw, got none")
        } catch {
            // expected
        }
    }

    static func report(_ suite: String) -> Int {
        if failures == 0 {
            print("ok   \(suite) (\(checks) checks)")
        } else {
            print("FAIL \(suite) (\(failures) of \(checks) checks failed)")
        }
        return failures
    }
}
