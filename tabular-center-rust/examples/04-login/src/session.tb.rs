//! The `session` matrix, in a file of its own. See `spec/matrix-files.md`.
//!
//! A private module at the crate root, re-exported by `pub mod session` in
//! `lib.rs`. At the root rather than inside `mod session` because a `#[path]`
//! in an inline module resolves against a directory named after the module,
//! and one rule for every example is worth more than a `src/session/` directory
//! holding one file.
//!
//! `DELEGATE!(auth)` names the child by path, so `auth` is imported here.
//! `super::auth::State` in the states still resolves: from a module at the
//! crate root, `super` is the crate root.

use tabular_center::transition_matrix;

use crate::auth;
use crate::session::Ctx;

#[rustfmt::skip]
transition_matrix! {
    machine Session;
    context Ctx;
    state   State;
    action  Action;
    effects Effect { Audit, Warn, Redirect }
    initial LoggedOut;

    states  { LoggedOut { auth: super::auth::State }, Active, Banned }
    actions { Credentials { ok: u32 }, StartOver, Logout }

    //                 Credentials         StartOver           Logout
    LoggedOut  => [     DELEGATE!(auth),   DELEGATE!(auth),    IGNORE                    ];
    Active     => [     IGNORE,            IGNORE,             GO!(Banned, Audit)        ];
    Banned     => [     IGNORE,            IGNORE,             IGNORE                    ];
}
