/**
 * **5. The other color: a machine whose `step` suspends.**
 *
 * Everything in examples 1–4 is colorless, and so was every example before
 * this one — `SuspendDriver` shipped with checks and no worked example, which
 * is the shipped-surface-without-a-consumer condition the graded set exists to
 * notice.
 *
 * The point of the example is that **nothing changes but the keyword**. The
 * matrix is the same shape, the cells are the same six kinds, the driver is
 * the same loop. `suspend` splats onto the generated dispatcher and onto every
 * required member, and that is the whole difference.
 *
 * It also demonstrates the zero-dependency claim rather than asserting it:
 * [runSuspend] below drives a suspending machine with `kotlin.coroutines`
 * intrinsics alone. If `SuspendDriver` needed `kotlinx.coroutines`, this file
 * could not compile, because the examples are built against `core` and the
 * stdlib and nothing else.
 */
package examples.suspending

import dev.tabularcenter.Step
import dev.tabularcenter.SuspendDriver
import kotlin.coroutines.Continuation
import kotlin.coroutines.EmptyCoroutineContext
import kotlin.coroutines.startCoroutine

sealed interface S {
    data object Idle : S
    data object Loading : S
    data object Loaded : S
}

sealed interface A {
    data object Start : A
    data object Arrived : A
    data object Give : A
}

sealed interface F {
    /** Fetching is what eventually produces an `Arrived`. */
    data object Fetch : F
    data class Log(val line: String) : F
}

class Ctx {
    val log = mutableListOf<String>()
}

/**
 * The cell surface, and the only place the color appears in a declaration.
 *
 * Both members are `suspend` because the prototype is. Neither implementation
 * below actually suspends, which is the honest shape of most real machines: a
 * machine is colored because *something* in it might await, not because
 * everything does.
 */
interface Cells {
    suspend fun idleStart(ctx: Ctx, state: S.Idle, action: A.Start): Step<S, F>
    suspend fun loadingArrived(ctx: Ctx, state: S.Loading, action: A.Arrived): Step<S, F>
}

/** The generated dispatcher, suspending because the cells are. */
suspend fun step(c: Cells, ctx: Ctx, s: S, a: A): Step<S, F> = when (s) {
    is S.Idle -> when (a) {
        is A.Start -> c.idleStart(ctx, s, a)
        is A.Arrived -> Step.Ignored
        is A.Give -> Step.Ignored
    }
    is S.Loading -> when (a) {
        is A.Start -> Step.Ignored
        is A.Arrived -> c.loadingArrived(ctx, s, a)
        is A.Give -> Step.Go(S.Loaded)
    }
    is S.Loaded -> Step.Ignored
}

/** The effect handler, also suspending, and also free not to suspend. */
suspend fun perform(ctx: Ctx, f: F): A? = when (f) {
    is F.Fetch -> {
        ctx.log.add("fetch")
        // Returned as data. This function cannot reach `step`, colored or not.
        A.Arrived
    }
    is F.Log -> {
        ctx.log.add(f.line)
        null
    }
}

class Impl : Cells {
    override suspend fun idleStart(ctx: Ctx, state: S.Idle, action: A.Start): Step<S, F> =
        Step.Go(S.Loading, listOf(F.Fetch))

    override suspend fun loadingArrived(ctx: Ctx, state: S.Loading, action: A.Arrived): Step<S, F> =
        Step.Go(S.Loaded, listOf(F.Log("loaded")))
}

/** Drive the machine from `Idle` until nothing is pending. */
suspend fun run(): Pair<S, Ctx> {
    val ctx = Ctx()
    val cells = Impl()
    val driver = SuspendDriver<S, A, F>(S.Idle)
    driver.dispatch(
        A.Start,
        step = { s, a -> step(cells, ctx, s, a) },
        perform = { f -> perform(ctx, f) },
    )
    return driver.state to ctx
}

/**
 * Run a suspending block to completion on the calling thread.
 *
 * `kotlinx.coroutines` would give this for free and is a Maven dependency;
 * `kotlin.coroutines` is in the stdlib and is enough. Twelve lines is what the
 * zero-runtime-dependency rule costs a caller who has no coroutine runtime of
 * their own — and a caller who does has `runBlocking` already.
 */
fun runSuspend(block: suspend () -> Unit) {
    var error: Throwable? = null
    var done = false
    block.startCoroutine(
        Continuation(EmptyCoroutineContext) { result ->
            result.exceptionOrNull()?.let { error = it }
            done = true
        },
    )
    check(done) { "runSuspend: block did not complete synchronously" }
    error?.let { throw it }
}
