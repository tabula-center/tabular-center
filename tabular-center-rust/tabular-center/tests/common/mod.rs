//! What the async tests share: a dependency-free executor and a future that
//! suspends exactly once. `tabular-center` has no dependencies, so neither do its tests.
//!
//! Poll `f` to completion on this thread, returning its output and how many
//! polls that took. A waker that does nothing is enough: nothing here waits
//! on anything but itself.

use std::future::Future;
use std::pin::{pin, Pin};
use std::task::{Context, Poll, RawWaker, RawWakerVTable, Waker};

pub fn block_on<F: Future>(f: F) -> (F::Output, u32) {
    fn raw() -> RawWaker {
        fn clone(_: *const ()) -> RawWaker {
            raw()
        }
        fn noop(_: *const ()) {}
        static VTABLE: RawWakerVTable = RawWakerVTable::new(clone, noop, noop, noop);
        RawWaker::new(std::ptr::null(), &VTABLE)
    }
    let waker = unsafe { Waker::from_raw(raw()) };
    let mut cx = Context::from_waker(&waker);
    let mut f = pin!(f);
    let mut polls = 0;
    loop {
        polls += 1;
        if let Poll::Ready(out) = f.as_mut().poll(&mut cx) {
            return (out, polls);
        }
    }
}

/// Suspends exactly once, then completes.
pub struct YieldOnce(pub bool);

impl Future for YieldOnce {
    type Output = ();
    fn poll(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<()> {
        if self.0 {
            Poll::Ready(())
        } else {
            self.0 = true;
            cx.waker().wake_by_ref();
            Poll::Pending
        }
    }
}
