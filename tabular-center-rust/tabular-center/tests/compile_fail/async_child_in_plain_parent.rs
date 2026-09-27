//~ EXPECT: no field `outcome` on type `impl Future
//
// Color flows one way. `Parent` is plain and delegates to `slow`, which is
// `async`. A plain parent's DELEGATE arm does not await, so the child's `step`
// is a future where a `Step` is required -- and rustc refuses it. By
// construction: tabular-center emits no diagnostic of its own, and there is nothing to
// circumvent. The allowed direction, an async parent over either child, is
// tests/async_composition.rs.
mod slow {
    use tabular_center::transition_matrix;

    pub struct Ctx;

    transition_matrix! {
        machine Slow; context Ctx; prototype async fn handle; state State; action Action; effects Effect { Crossed } initial Low;
        states  { Low, High }
        actions { Bump }
        Low  => [ HANDLE ];
        High => [ IGNORE ];
    }
}

mod parent {
    use super::slow;
    use tabular_center::transition_matrix;

    pub struct Ctx;

    transition_matrix! {
        machine Parent; context Ctx; state State; action Action; effects Effect { Note } initial Busy;
        states  { Busy { child: slow::State } }
        actions { Bump }
        Busy => [ DELEGATE!(slow) ];
    }
}

fn main() {}
