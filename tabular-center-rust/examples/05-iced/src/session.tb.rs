//! The parent matrix: a session that contains a connection.
//!
//! `DELEGATE!(connection)` hands one cell to the child machine. The parent's
//! state carries the child's, and the parent's `Cells` bound includes the
//! child's, so a hole anywhere in the child is a build error here.

use tabula::transition_matrix;

use crate::connection;
use crate::session::Ctx;

#[rustfmt::skip]
transition_matrix! {
    machine Session;
    context Ctx;
    state   State;
    action  Action;
    effects Effect { Note, Dial }
    initial Booting;

    states  { Booting, Running { child: connection::State }, Ended }
    actions { Boot, Tap, Finish }

    //            Boot                                          Tap                     Finish
    Booting  => [ GO!(Running { child: connection::State::Idle(connection::Idle) }), IGNORE, IGNORE            ];
    Running  => [ IGNORE,                                       DELEGATE!(connection), GO!(Ended, Note)        ];
    Ended    => [ IGNORE,                                       IGNORE,                IGNORE                  ];
}
