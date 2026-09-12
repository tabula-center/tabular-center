// A four-function assertion harness, shared by every example's tests.
//
// No package, so an example's test file can call it without an import while
// still being compiled as its own unit. Deliberately not `dev.tabula.testing`:
// that module is part of the library and an example must not appear to need a
// test dependency the library does not ship.
object Check {
    var failures = 0
    var checks = 0

    fun <T> eq(actual: T, expected: T, what: String) {
        checks++
        if (actual != expected) {
            failures++
            println("FAIL $what")
            println("       got      $actual")
            println("       expected $expected")
        }
    }

    fun ok(cond: Boolean, what: String) {
        checks++
        if (!cond) {
            failures++
            println("FAIL $what")
        }
    }

    fun report(name: String) {
        if (failures == 0) {
            println("ok   $name ($checks checks)")
        } else {
            println("FAIL $name ($failures of $checks checks failed)")
            kotlin.system.exitProcess(1)
        }
    }
}
