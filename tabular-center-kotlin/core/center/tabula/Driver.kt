// Running a machine: `Driver` and its suspending twin `SuspendDriver` hold a
// state and a FIFO mailbox, step one action at a time, apply the outcome
// before performing effects, and queue follow-up actions rather than
// re-entering `step`. Neither needs a coroutine library.
//
// - `applyOutcome`: Applies one step's outcome and counts it.
package center.tabula

/** Why a driver call could not proceed. */
sealed interface DriverError {
    /** The mailbox is full. */
    data class QueueFull(val capacity: Int) : DriverError

    /** `run` was called from inside itself. */
    data object Reentered : DriverError
}

/** Raised when a driver call cannot proceed. */
class DriverException(val error: DriverError) : RuntimeException(error.toString())

/** What one drain accomplished. */
data class Progress(
    val steps: Int = 0,
    val effects: Int = 0,
    val followUps: Int = 0,
    val transitions: Int = 0,
    val ignored: Int = 0,
)

/**
 * A bounded FIFO of pending actions, plus the current state.
 *
 * Split out from the drivers because Kotlin cannot abstract over `suspend`:
 * [Driver] and [SuspendDriver] are two colors of the same loop, and this holds
 * everything that is colorless. That split is the shape every colored API in
 * this library takes — one file per color, no shared abstraction, because the
 * language does not offer one.
 *
 * - `pending`: Pending actions.
 * - `enqueue`: Add an action to the back of the mailbox.
 */
class Mailbox<S, A>(initial: S, val capacity: Int = 8) {
    var state: S = initial
        internal set

    private val queue = ArrayDeque<A>()

    val pending: Int get() = queue.size

    internal var running = false

    fun enqueue(action: A) {
        if (queue.size == capacity) throw DriverException(DriverError.QueueFull(capacity))
        queue.addLast(action)
    }

    internal fun dequeue(): A? = queue.removeFirstOrNull()
}

internal fun <S, A, F> Mailbox<S, A>.applyOutcome(step: Step<S, F>, p: Progress): Progress =
    when (step) {
        is Step.Go -> { state = step.next; p.copy(transitions = p.transitions + 1) }
        is Step.Stay -> p
        is Step.Ignored -> p.copy(ignored = p.ignored + 1)
    }

/**
 * The blocking driver.
 *
 * `step` is never re-entered, and follow-up actions are **queued, never
 * recursed**: a handler returns an action as data and is handed no way back
 * into `step`.
 *
 * - `state`: The current state.
 * - `enqueue`: Add an action to the back of the mailbox.
 * - `dispatch`: Dispatch one action and drain everything it causes.
 * - `run`: Drain the mailbox, strictly FIFO.
 */
class Driver<S, A, F>(initial: S, capacity: Int = 8) {
    val mailbox = Mailbox<S, A>(initial, capacity)

    val state: S get() = mailbox.state

    fun enqueue(action: A) = mailbox.enqueue(action)

    fun dispatch(action: A, step: (S, A) -> Step<S, F>, perform: (F) -> A?): Progress {
        enqueue(action)
        return run(step, perform)
    }

    fun run(step: (S, A) -> Step<S, F>, perform: (F) -> A?): Progress {
        if (mailbox.running) throw DriverException(DriverError.Reentered)
        mailbox.running = true
        try {
            var p = Progress()
            while (true) {
                val action = mailbox.dequeue() ?: break
                val outcome = step(mailbox.state, action)
                p = mailbox.applyOutcome(outcome, p.copy(steps = p.steps + 1))
                for (effect in outcome.effects) {
                    p = p.copy(effects = p.effects + 1)
                    val followUp = perform(effect) ?: continue
                    mailbox.enqueue(followUp)
                    p = p.copy(followUps = p.followUps + 1)
                }
            }
            return p
        } finally {
            mailbox.running = false
        }
    }
}

/**
 * The suspending driver.
 *
 * The same loop, a different color. Kotlin cannot abstract over `suspend`, so
 * this is a separate type rather than a generic parameter — see [Mailbox].
 *
 * Depends on the `suspend` keyword only, not on `kotlinx.coroutines`: the
 * zero-runtime-dependency rule holds.
 *
 * - `state`: The current state.
 * - `enqueue`: Add an action to the back of the mailbox.
 * - `dispatch`: Dispatch one action and drain everything it causes.
 * - `run`: Drain the mailbox, strictly FIFO.
 */
class SuspendDriver<S, A, F>(initial: S, capacity: Int = 8) {
    val mailbox = Mailbox<S, A>(initial, capacity)

    val state: S get() = mailbox.state

    fun enqueue(action: A) = mailbox.enqueue(action)

    suspend fun dispatch(
        action: A,
        step: suspend (S, A) -> Step<S, F>,
        perform: suspend (F) -> A?,
    ): Progress {
        enqueue(action)
        return run(step, perform)
    }

    suspend fun run(
        step: suspend (S, A) -> Step<S, F>,
        perform: suspend (F) -> A?,
    ): Progress {
        if (mailbox.running) throw DriverException(DriverError.Reentered)
        mailbox.running = true
        try {
            var p = Progress()
            while (true) {
                val action = mailbox.dequeue() ?: break
                val outcome = step(mailbox.state, action)
                p = mailbox.applyOutcome(outcome, p.copy(steps = p.steps + 1))
                for (effect in outcome.effects) {
                    p = p.copy(effects = p.effects + 1)
                    val followUp = perform(effect) ?: continue
                    mailbox.enqueue(followUp)
                    p = p.copy(followUps = p.followUps + 1)
                }
            }
            return p
        } finally {
            mailbox.running = false
        }
    }
}
