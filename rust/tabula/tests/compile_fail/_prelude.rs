// Shared preamble for compile-fail fixtures. Not a test itself.
pub struct Ctx {
    pub limit: u32,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Effect {
    StartClock,
    StopClock,
}
