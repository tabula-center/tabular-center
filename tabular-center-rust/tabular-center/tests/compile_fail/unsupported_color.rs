//~ EXPECT: tabular-center::unsupported-color: machine `Timer` has a prototype Rust cannot color
//
// Rust's cell surface is a library trait, so a color needs a colored twin of
// it, and `async` is the only color a trait method can carry on stable.
// Anything else is refused by name rather than falling through to
// "no rules expected the token `const`".
use tabular_center::transition_matrix;
include!("_prelude.rs");

transition_matrix! {
    machine Timer; context Ctx; prototype const fn handle; state State; action Action; effects Effect { StartClock } initial Idle;
    states  { Idle, Done }
    actions { Start }
    Idle => [ GO!(Done) ];
    Done => [ IGNORE ];
}

fn main() {}
