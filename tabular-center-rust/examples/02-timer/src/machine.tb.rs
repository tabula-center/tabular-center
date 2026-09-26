//! The matrix, in a file of its own. See `spec/matrix-files.md`, and
//! `01-traffic-light/src/machine.tb.rs` for why Rust reaches it with
//! `#[path]` and re-exports it: `transition_matrix!` generates the state and
//! action types, so splitting a matrix out of Rust moves types, not just text.

use tabula::transition_matrix;

use crate::{Ctx, Reason};

#[rustfmt::skip]
transition_matrix! {
    machine Timer;
    context Ctx;
    state   State;
    action  Action;
    effects Effect { StartClock, StopClock { reason: Reason } }
    initial Idle;

    states  { Idle, Running { since: u64 }, Done }
    actions { Start, Tick { now: u64 }, Cancel }

    //            Start                                  Tick     Cancel
    Idle    => [  HANDLE,                                IGNORE,  IGNORE                                  ];
    Running => [  IGNORE,                                HANDLE,  GO!(Idle, StopClock { reason: Reason::Cancelled }) ];
    Done    => [  GO!(Running { since: 0 }, StartClock), IGNORE,  IGNORE                                  ];
}
