//~ EXPECT: cannot find value `ctx` in this scope
//
// Rule R3, enforced by construction rather than by a lint. The dispatcher
// binds its parameters under `__tabula_`-prefixed names, so `ctx` simply is
// not in scope inside a GO! expression.
use tabula::transition_matrix;
include!("_prelude.rs");

transition_matrix! {
    machine Timer; context Ctx; state State; action Action; effect Effect; initial Idle;
    states  { Idle, Running { since: u32 }, Done }
    actions { Start, Tick { now: u32 }, Cancel }
    Idle    => [ GO!(Running { since: ctx.limit }), IGNORE, IGNORE ];
    Running => [ IGNORE, IGNORE, GO!(Idle) ];
    Done    => [ IGNORE, IGNORE, IGNORE ];
}
fn main() {}
