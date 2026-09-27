package harness

import kotlin.coroutines.Continuation
import kotlin.coroutines.EmptyCoroutineContext
import kotlin.coroutines.startCoroutine

/**
 * Runs a suspending block to completion on the calling thread.
 *
 * `kotlinx.coroutines` would give this for free, but it is a Maven dependency
 * and `tabular-center-core` must not acquire one. `kotlin.coroutines` — the intrinsics
 * in the stdlib — is enough, which is also the proof that the suspending driver
 * needs nothing beyond the `suspend` keyword.
 */
fun runSuspend(block: suspend () -> Unit) {
    var error: Throwable? = null
    var done = false
    block.startCoroutine(Continuation(EmptyCoroutineContext) { result ->
        result.exceptionOrNull()?.let { error = it }
        done = true
    })
    check(done) { "runSuspend: block did not complete synchronously" }
    error?.let { throw it }
}
