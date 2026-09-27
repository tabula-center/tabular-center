//~ EXPECT: tabular-center::empty-emit: cell (Off, Poke) uses EMIT with no effects
//
// `EMIT!()` means "handled, no transition, nothing emitted" -- which is
// `IGNORE` if the action does not apply in this state and `HANDLE` if it does.
// Accepting it would make those two indistinguishable in the table, and the
// distinction is what `tabular-center::dead-row` and the coverage report are computed
// from.
//
// Rust accepted this until now while Kotlin and Swift rejected it. The
// conformance suite could not have caught the divergence: it compares
// behaviour, and no fixture writes a cell the spec forbids.
use tabular_center::transition_matrix;
include!("_prelude.rs");

transition_matrix! {
    machine Toggle; context Ctx; state State; action Action; effects Effect { Light } initial Off;
    states  { Off, On }
    actions { Flip, Poke }
    Off => [ GO!(On, Light), EMIT!() ];
    On  => [ GO!(Off),       HANDLE  ];
}
fn main() {}
