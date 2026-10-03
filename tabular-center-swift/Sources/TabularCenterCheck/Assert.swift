/// A test harness in thirty lines.
///
/// Not XCTest: nixpkgs' Swift toolchain does not ship it, and a test framework
/// that has to be resolved is a test framework that can stop the tests from
/// running at all. The Kotlin side made the same call about JUnit, for the
/// same reason.
enum Assert {
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
