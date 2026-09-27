//~ EXPECT: 'async' call in a function that does not support concurrency
//
// Color flows one way. `JobMixed` is uncolored and delegates to `RetryAsync`,
// which is `async throws`. The generated `delegateToRetryAsync` carries the
// PARENT's color, so it calls `RetryAsync.step` without `await` -- and swiftc
// refuses it. By construction: no diagnostic of tabular-center's own, and nothing to
// circumvent.
//
// This file is deliberately empty of code. The error is in the emitted
// `job-mixed.emitted.swift`, which `tools/verify` adds to this fixture's
// compile because the machine is marked refused in TabularCenterCodegenCheck. The
// reverse direction, a colorless child in a colored parent, is
// complete/job-async.swift, which must compile.
