//! The matrix, in a file of its own. See `spec/matrix-files.md`, and
//! `01-traffic-light/src/machine.tb.rs` for why Rust reaches it with
//! `#[path]` and re-exports it: `transition_matrix!` generates the state and
//! action types, so splitting a matrix out of Rust moves types, not just text.

use tabula::transition_matrix;

use crate::Ctx;

#[rustfmt::skip]
transition_matrix! {
    machine Retry;
    context Ctx;
    state   State;
    action  Action;
    effects Effect { Sleep { ms: u64 }, GiveUp }
    initial Ready;

    states  { Ready, Waiting { attempt: u32 }, Exhausted }
    actions { Attempt, Elapsed, Abort }

    //                Attempt   Elapsed   Abort
    Ready     => [    HANDLE,   IGNORE,   GO!(Exhausted)  ];
    Waiting   => [    IGNORE,   HANDLE,   GO!(Exhausted)  ];
    Exhausted => [    IGNORE,   IGNORE,   IGNORE          ];
}
