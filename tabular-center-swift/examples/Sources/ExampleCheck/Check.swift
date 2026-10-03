/// A four-function assertion harness, shared by every example.
///
/// Its own target, so each example's checks are a separate build product that
/// depends on it explicitly. Deliberately not `TabularCenterTesting`: that module is
/// part of the library, and an example must not appear to need a test
/// dependency the library does not ship.
public enum Check {
    public static var failures = 0
    public static var checks = 0

    public static func eq<T: Equatable>(_ actual: T, _ expected: T, _ what: String) {
        checks += 1
        if actual != expected {
            failures += 1
            print("FAIL \(what)")
            print("       got      \(actual)")
            print("       expected \(expected)")
        }
    }

    public static func ok(_ condition: Bool, _ what: String) {
        checks += 1
        if !condition {
            failures += 1
            print("FAIL \(what)")
        }
    }

    public static func report(_ name: String) -> Int32 {
        if failures == 0 {
            print("ok   \(name) (\(checks) checks)")
            return 0
        }
        print("FAIL \(name) (\(failures) of \(checks) checks failed)")
        return 1
    }
}
