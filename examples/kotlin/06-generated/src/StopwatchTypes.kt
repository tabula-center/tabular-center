// The types `Stopwatch.tb.kt` refers to, plus the machine's context and the
// receiver its prototype is an extension on.
//
// The third machine in this example, and it exists for two things the other
// two cannot show:
//
// - **An extension receiver as color.** The prototype is `fun Clock.handle`,
//   so every generated cell, effect handler, `step` and `perform` is an
//   extension on `Clock`. A cell body calls `now()` without being handed a
//   clock, and a caller cannot dispatch without one in scope. ARCHITECTURE §5
//   lists receivers among the colors the generator copies rather than
//   enumerates; this is that claim exercised.
// - **An internal machine.** Everything here is `internal`, and so is the
//   generated surface. Before the processor read the declaration's
//   visibility, it emitted a public `Cells` over these types -- which is
//   `exposes its internal parameter type`, an error in a file the user never
//   wrote.
package generated.stopwatch

internal sealed interface S {
    data object Idle : S
    data class Running(val since: Long) : S
}

internal sealed interface A {
    data object Start : A
    data object Stop : A
}

internal sealed interface F {
    data object Beep : F
}

internal class Ctx {
    var lastElapsed: Long = -1
    var beeps = 0
}

/**
 * The receiver. Public, and in a real project usually from another package
 * entirely, which is why the generator writes its name fully qualified.
 */
interface Clock {
    fun now(): Long
}
