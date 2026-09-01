package dev.tabula

import kotlin.reflect.KClass

/** Which of the six kinds a [Cell] declaration is. */
enum class Kind { HANDLE, IGNORE, GO, EMIT, UNREACHABLE, DELEGATE }

/**
 * One entry in a [Row].
 *
 * `to` and `emit` take `KClass`, not strings, so a typo is a compile error
 * rather than a generator error — the earliest possible failure, and one that
 * costs nothing to provide.
 */
@Retention(AnnotationRetention.SOURCE)
annotation class CellSpec(
    val kind: Kind,
    val to: KClass<*> = Unit::class,
    val emit: Array<KClass<*>> = [],
    val child: KClass<*> = Unit::class,
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
