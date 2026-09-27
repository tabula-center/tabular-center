//~ EXPECT: tabular-center::path-unknown-state: path `connect` names state `Livee`, which is not declared
//
// A path names a state the machine does not declare. Checked against a lookup
// generated from the `states` block -- `macro_rules!` cannot compare two
// identifiers, so the declared names become the lookup's own rules.
use tabular_center::transition_matrix;
include!("_prelude.rs");

transition_matrix! {
    machine Link; context Ctx; state State; action Action; effects Effect { } initial Idle;
    states  { Idle, Connecting, Live }
    actions { Start, Ready }
    paths {
        connect: [Idle, Start, Connecting, Ready, Livee];
    }
    Idle       => [ HANDLE, IGNORE ];
    Connecting => [ IGNORE, HANDLE ];
    Live       => [ IGNORE, IGNORE ];
}

fn main() {}
