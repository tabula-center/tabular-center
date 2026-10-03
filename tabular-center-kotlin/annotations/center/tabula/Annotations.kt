// The annotations a machine is declared with, read by the KSP processor:
// `@Machine` on the spec interface, one `@Row` per state holding its cells
// (`CellSpec`, by `Kind`), `Emit` for an effect with literal arguments, and
// `@Path` for a happy path. Compile-time only; nothing here runs.
package center.tabula

import kotlin.reflect.KClass

/** Which of the six kinds a [Cell] declaration is. */
enum class Kind { HANDLE, IGNORE, GO, EMIT, UNREACHABLE, DELEGATE }

/**
 * One entry in a [Row].
 *
 * `to` and `emit` take `KClass`, not strings, so a typo is a compile error
 * rather than a generator error — the earliest possible failure, and one that
 * costs nothing to provide.
 *
 * - `args`: Literal constructor arguments for [to], e.g.
 * - `emit`: Payload-free effects: `emit = [F.StopClock::class]`.
 * - `emits`: Effects that carry a payload, with their literal arguments: `emits = [Emit(F.StopClock::class, "reason = Reason.Cancelled")]`.
 */
@Retention(AnnotationRetention.SOURCE)
annotation class CellSpec(
    val kind: Kind,
    val to: KClass<*> = Unit::class,
    val args: String = "",
    val emit: Array<KClass<*>> = [],
    val emits: Array<Emit> = [],
    val child: KClass<*> = Unit::class,
)

/**
 * One effect and the literal arguments to construct it, for [CellSpec.emits].
 *
 * `args` is a string for the same reason [CellSpec.args] is: an annotation
 * cannot hold an expression. A static cell may only emit what is known at
 * declaration time, so a literal is all it ever needs.
 */
@Retention(AnnotationRetention.SOURCE)
annotation class Emit(
    val effect: KClass<*>,
    val args: String = "",
)

/**
 * One row of the matrix: a state, then one cell per action in declared order.
 *
 * Positional rather than named, because positional rows *look* like a table —
 * which is the point of the whole library. A hole should be visible to a human
 * reviewer before the compiler ever runs.
 */
@Target(AnnotationTarget.CLASS)
@Retention(AnnotationRetention.SOURCE)
@Repeatable
annotation class Row(val state: KClass<*>, val cells: Array<CellSpec>)

/**
 * Declares a machine on an interface holding its sealed hierarchies and the
 * `handle` prototype.
 *
 * KSP cannot rewrite code — it only generates new files — so the matrix has to
 * live in annotations, which KSP *can* read. That constraint is what forces the
 * design where the developer never writes a `when` at all: the dispatcher
 * exists only in generated code, so `else` is not available to reach for.
 */
@Target(AnnotationTarget.CLASS)
@Retention(AnnotationRetention.SOURCE)
annotation class Machine(
    val states: Array<KClass<*>>,
    val actions: Array<KClass<*>>,
    val effects: Array<KClass<*>> = [],
    val initial: KClass<*> = Unit::class,
    val name: String = "",
)

/**
 * A happy path: a named route through the matrix. See `spec/happy-paths.md`.
 *
 * Purely additive. A machine without one is declared, generated and consumed
 * exactly as before, and a machine with one produces a byte-identical `TABLE`,
 * `.grid`, `.lint`, `.cov` and `.mmd`. What it buys is generated sugar: the
 * ordinary case reads as ordinary, and the corner cases stop being the first
 * thing a reader meets.
 *
 * ```
 * @Path(
 *     "connect",
 *     [S.Idle::class, A.Start::class, S.Connecting::class, A.Ready::class, S.Live::class],
 * )
 * ```
 *
 * States and actions **alternate**, starting and ending with a state: each
 * `state, action, state` triple is one hop, naming the exact cell it passes
 * through. The parameter is called `states` for historical reasons -- it
 * predates the alternating form -- and holds both.
 *
 * `@Repeatable` for the same reason `@Row` is: a machine may have several, and
 * each is its own declaration rather than an entry in a list-of-lists nobody
 * can read.
 *
 * `SOURCE` retention, like the rest of this file. KSP reads the declaration and
 * discards it; nothing here exists at run time, which is what keeps the runtime
 * types unchanged.
 *
 * Elements are `KClass` rather than strings so a rename in the IDE moves the path
 * with it. `tabular-center::path-unknown-state` catches what a rename cannot -- a state
 * that never existed -- and the other three `path-*` codes catch a route that
 * does not match the rows it describes.
 *
 * - `back`: The action that walks this path backwards, if it has one.
 */
@Repeatable
@Retention(AnnotationRetention.SOURCE)
@Target(AnnotationTarget.CLASS)
annotation class Path(
    val name: String,
    val states: Array<KClass<*>>,
    val back: KClass<*> = Unit::class,
)
