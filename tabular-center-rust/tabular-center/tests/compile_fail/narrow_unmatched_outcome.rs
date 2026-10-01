//~ EXPECT: non-exhaustive patterns
//
// The narrowed surface keeps the matrix's guarantee in Rust's shape: the
// `Err` side of `narrow` is the machine's whole `State`, so an exhaustive
// `match` on it names every state -- leave one out, or add one to the machine,
// and the call site stops compiling. Rust's surface is not row-precise
// (`macro_rules!` cannot build names or deduplicate sets, and this crate takes
// no dependency to get round that; see `src/hop.rs`), so `Done` is required
// here although `Idle`'s row cannot produce it.
use tabular_center::transition_matrix;
include!("_prelude.rs");

transition_matrix! {
    machine Pipe; context Ctx; state State; action Action; effects Effect { } initial Idle;
    states  { Idle, Busy, Done }
    actions { Go, Stop }
    paths {
        run: [Idle, Go, Busy, Stop, Done];
    }
    Idle => [ HANDLE, IGNORE ];
    Busy => [ IGNORE, HANDLE ];
    Done => [ IGNORE, IGNORE ];
}

struct Impl;

fn main() {
    let mut ctx = Ctx { limit: 0 };
    match narrow::<Idle, Go, _>(&mut Impl, &mut ctx, Idle, Action::Go(Go)) {
        Ok(_) => {}
        Err((State::Idle(_), _)) => {}
        Err((State::Busy(_), _)) => {}
        // `Done` is missing.
    }
}
