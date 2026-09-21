//~ EXPECT: the name `connect` is defined multiple times
//
// Two paths with one name. Refused by rustc rather than with tabula's text:
// this compares two names the machine chose, with no declared list to
// generate a lookup from -- the same reason `unknown-child` is left to rustc.
// One item per path name makes the repeat a duplicate definition.
use tabula::transition_matrix;
include!("_prelude.rs");

transition_matrix! {
    machine Link; context Ctx; state State; action Action; effects Effect { } initial Idle;
    states  { Idle, Connecting, Live }
    actions { Start, Ready }
    paths {
        connect: [Idle, Start, Connecting, Ready, Live];
        connect: [Idle, Start, Connecting, Ready, Live];
    }
    Idle       => [ HANDLE, IGNORE ];
    Connecting => [ IGNORE, HANDLE ];
    Live       => [ IGNORE, IGNORE ];
}

fn main() {}
