//~ EXPECT: tabular-center::path-broken: path `connect` goes `Idle` -`Start`-> `Connecting`, and cell (Idle, Start) cannot reach `Connecting`
//
// The declaration and the matrix disagree: the path says `Idle -Start->
// Connecting`, and the cell at (Idle, Start) is IGNORE. A HANDLE there would
// be derived into the GO; a GO elsewhere, or an IGNORE, cannot be.
use tabular_center::transition_matrix;
include!("_prelude.rs");

transition_matrix! {
    machine Link; context Ctx; state State; action Action; effects Effect { } initial Idle;
    states  { Idle, Connecting, Live }
    actions { Start, Ready }
    paths {
        connect: [Idle, Start, Connecting, Ready, Live];
    }
    Idle       => [ IGNORE, IGNORE ];
    Connecting => [ IGNORE, HANDLE ];
    Live       => [ IGNORE, IGNORE ];
}

fn main() {}
