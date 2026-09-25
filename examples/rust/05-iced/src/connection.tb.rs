//! The matrix, in a file of its own. See `spec/matrix-files.md`.
//!
//! The same connection as `examples/kotlin/07-compose`, so the two GUI
//! examples can be read side by side: the machine is the same, the host
//! architectures are not.

use tabula::transition_matrix;

use crate::connection::Ctx;

#[rustfmt::skip]
transition_matrix! {
    machine Connection;
    context Ctx;
    state   State;
    action  Action;
    effects Effect { Dial, Hangup }
    initial Idle;

    states  { Idle, Connecting, Live { since: u32 }, Failed }
    actions { Start, Ready { at: u32 }, Close, Retry }

    //             Start                  Ready     Close                   Retry
    Idle       => [ GO!(Connecting, Dial), IGNORE,   IGNORE,                IGNORE                 ];
    Connecting => [ IGNORE,                HANDLE,   GO!(Failed),           IGNORE                 ];
    Live       => [ IGNORE,                IGNORE,   GO!(Idle, Hangup),     IGNORE                 ];
    Failed     => [ IGNORE,                IGNORE,   IGNORE,                GO!(Connecting, Dial)  ];
}
