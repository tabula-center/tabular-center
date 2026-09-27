//! The `auth` matrix, in a file of its own. See `spec/matrix-files.md`.
//!
//! A private module at the crate root, re-exported by `pub mod auth` in
//! `lib.rs`. At the root rather than inside `mod auth` because a `#[path]`
//! in an inline module resolves against a directory named after the module,
//! and one rule for every example is worth more than a `src/auth/` directory
//! holding one file.

use tabular_center::transition_matrix;

use crate::auth::Ctx;

#[rustfmt::skip]
transition_matrix! {
    machine Auth;
    context Ctx;
    state   State;
    action  Action;
    effects Effect { Prompt, Lockout }
    initial AwaitingCredentials;

    states  { AwaitingCredentials { attempts: u32 }, Authenticated, LockedOut }
    actions { Submit { ok: u32 }, Reset }

    //                            Submit    Reset
    AwaitingCredentials  => [     HANDLE,   GO!(AwaitingCredentials { attempts: 0 }, Prompt) ];
    Authenticated        => [     IGNORE,   GO!(AwaitingCredentials { attempts: 0 }, Prompt) ];
    LockedOut            => [     IGNORE,   IGNORE                                          ];
}
