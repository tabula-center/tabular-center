//~ EXPECT: the trait bound `Impl: tabular_center::Handle<Retry, Waiting, Elapsed>` is not satisfied
//
// The composition property, as a test:
//
//   Scoping a total child into a total parent yields a total parent, and the
//   compiler proves it by the same mechanism as everything else.
//
// `Waiting x Elapsed` is a cell of the CHILD. It is unimplemented, and the
// error appears at a call to the PARENT's `step`. This is what DELEGATE buys
// over HANDLE: a hand-written HANDLE body is free to ignore the child, so no
// bound would propagate and the hole would go unnoticed.
use tabular_center::{transition_matrix, Delegate, Handle, Lens, Step};

mod retry {
    use super::*;
    #[derive(Debug, Default)]
    pub struct Ctx;

    transition_matrix! {
        machine Retry; context Ctx; state State; action Action; effects Effect { Sleep } initial Ready;
        states  { Ready, Waiting { attempt: u32 } }
        actions { Attempt, Elapsed }
        Ready   => [ HANDLE, IGNORE ];
        Waiting => [ IGNORE, HANDLE ];
    }
}

mod job {
    use super::*;
    #[derive(Debug, Default)]
    pub struct Ctx {
        pub retry: super::retry::Ctx,
    }

    transition_matrix! {
        machine Job; context Ctx; state State; action Action; effects Effect { Backoff } initial Retrying;
        states  { Retrying { child: retry::State } }
        actions { Tick }
        Retrying => [ DELEGATE!(retry) ];
    }
}

struct Impl;

impl Handle<retry::Retry, retry::Ready, retry::Attempt> for Impl {
    fn handle(
        &mut self,
        _c: &mut retry::Ctx,
        _s: retry::Ready,
        _a: retry::Attempt,
    ) -> Step<retry::State, retry::Effect> {
        Step::stay()
    }
}
// retry::Waiting x retry::Elapsed is HANDLE and has no impl.

// The lens is per (parent state, child); only the prism is per cell.
impl Lens<job::Job, job::Retrying, retry::Marker> for Impl {
    fn child_state(&mut self, s: &job::Retrying) -> retry::State {
        s.child
    }
    fn embed(&mut self, s: job::Retrying, child: retry::State) -> job::State {
        job::State::Retrying(job::Retrying { child, ..s })
    }
    fn lift(&mut self, _e: retry::Effect) -> job::Effect {
        job::Effect::Backoff(job::Backoff)
    }
    fn child_ctx<'a>(&mut self, c: &'a mut job::Ctx) -> &'a mut retry::Ctx {
        &mut c.retry
    }
}

impl Delegate<job::Job, job::Retrying, job::Tick, retry::Marker> for Impl {
    fn to_child(
        &mut self,
        _c: &mut job::Ctx,
        _s: &job::Retrying,
        _a: job::Tick,
    ) -> Option<retry::Action> {
        Some(retry::Action::Elapsed(retry::Elapsed))
    }
}

fn main() {
    let mut ctx = job::Ctx { retry: retry::Ctx };
    let _ = job::step(
        &mut Impl,
        &mut ctx,
        job::State::Retrying(job::Retrying {
            child: retry::State::Ready(retry::Ready),
        }),
        job::Action::Tick(job::Tick),
    );
}
