//~ EXPECT: tabula::path-unterminated: path `connect` ends at `Live`, which can still be left
//
// A path that never ends is not a happy path, it is a loop with a name. `Live`
// has a HANDLE in its row, so the machine is not done when the path says it is.
use tabula::transition_matrix;
include!("_prelude.rs");

transition_matrix! {
    machine Link; context Ctx; state State; action Action; effects Effect { } initial Idle;
    states  { Idle, Connecting, Live }
    actions { Start, Ready }
    paths {
        connect: [Idle, Start, Connecting, Ready, Live];
    }
    Idle       => [ HANDLE, IGNORE ];
    Connecting => [ IGNORE, HANDLE ];
    Live       => [ HANDLE, IGNORE ];
}

fn main() {}
