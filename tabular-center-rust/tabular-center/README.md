# tabular-center

Transition-matrix state machines whose completeness is enforced by the
compiler.

You declare a machine as a grid -- one row per state, one column per action,
and a decision in every cell -- with `transition_matrix!`. Add a state or an
action and the build fails until every new cell is decided; add an effect and
every handler that must perform it stops compiling. There is no wildcard arm to
fall into.

- No dependencies, and `no_std` (with an optional `alloc`/`std`).
- The matrix is plain `macro_rules!`: no proc-macro, no build-graph cost.
- The same machine model, cell semantics and conformance fixtures as the
  Kotlin and Swift implementations.

The guide, with examples the project's CI compiles and runs:
<https://tabula-center.github.io/tabular-center/doc/rust>

Source, specification and the other two implementations:
<https://github.com/tabula-center/tabular-center>

Licensed under either of MIT or Apache-2.0, at your option.
