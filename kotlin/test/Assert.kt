package harness

/**
 * A test harness in thirty lines.
 *
 * Not JUnit or kotlin.test: those come from Maven, and this module compiles
 * with `kotlinc` alone. That constraint is temporary — it goes away when
 * Gradle can reach Maven — but shipping unverifiable code while waiting for a
 * build system would have been worse.
 */
object Assert {
    private var failures = 0
    private var checks = 0

    fun <T> eq(actual: T, expected: T, what: String) {
        checks++
        if (actual != expected) {
            failures++
            println("FAIL $what")
            println("       got    $actual")
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

    fun <E : Throwable> throws(what: String, body: () -> Unit) {
        checks++
        try {
            body()
            failures++
            println("FAIL $what: expected a throw, got none")
        } catch (_: Throwable) {
        }
    }

    fun report(suite: String): Int {
        if (failures == 0) println("ok   $suite ($checks checks)")
        else println("FAIL $suite ($failures of $checks checks failed)")
        return failures
    }
}
