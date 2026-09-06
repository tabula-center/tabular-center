import Tabula
import TabulaTesting

/// Adapters for `retry.tbl` and `nested-delegate.tbl`.
///
/// Two adapters over one pair of machines, because the child must be conformant
/// **on its own**: being composed does not change it, and a child that only
/// works inside its parent is not a reusable machine.

struct RetryAdapter: Adapter {
    let name = "retry"
    let table = RETRY_TABLE

    /// See `TimerAdapter.effectName` — Swift cases are lowerCamel, the fixtures
    /// are UpperCamel.
    static func effectName(_ f: RetryF) -> String {
        switch f {
        case .sleep: return "Sleep"
        case .giveUp: return "GiveUp"
        }
    }

    func replay(_ trace: Trace) throws -> [Observed] {
        let ctx = RetryCtx(maxAttempts: trace.ctx["max_attempts"] ?? 1)
        let cells = ComposedImpl()
        var state = try stateOf(trace.from, trace.fromFields)
        var out: [Observed] = []

        for st in trace.steps {
            let action: RetryA
            switch st.action {
            case "Attempt": action = .attempt
            case "Elapsed": action = .elapsed
            case "Abort": action = .abort
            default: throw SpecError("retry: unknown action `\(st.action)`")
            }

            let step = retryStep(cells, ctx, state, action)
            let effects = step.effects.map(Self.effectName)
            let expect: Expect
            switch step {
            case .stay: expect = .stay
            case .ignored: expect = .ignored
            case let .go(next, _):
                state = next
                var want: [String: Int] = [:]
                if case let .go(_, fields) = st.expect { want = fields }
                expect = describe(next, want)
            }
            out.append(Observed(expect: expect, effects: effects))
        }
        return out
    }

    private func stateOf(_ name: String, _ f: [String: Int]) throws -> RetryS {
        switch name {
        case "Ready": return .ready
        case "Exhausted": return .exhausted
        case "Waiting": return .waiting(attempt: f["attempt"] ?? 1)
        default: throw SpecError("retry: unknown state `\(name)`")
        }
    }

    private func describe(_ s: RetryS, _ want: [String: Int]) -> Expect {
        switch s {
        case .ready: return .go(state: "Ready", fields: [:])
        case .exhausted: return .go(state: "Exhausted", fields: [:])
        case let .waiting(attempt):
            return .go(
                state: "Waiting", fields: want["attempt"] != nil ? ["attempt": attempt] : [:])
        }
    }
}

struct JobAdapter: Adapter {
    let name = "nested-delegate"
    let table = JOB_TABLE

    static func effectName(_ f: JobF) -> String {
        switch f {
        case .log: return "Log"
        case .backoff: return "Backoff"
        case .alert: return "Alert"
        }
    }

    func replay(_ trace: Trace) throws -> [Observed] {
        let ctx = JobCtx(retry: RetryCtx(maxAttempts: trace.ctx["max_attempts"] ?? 1))
        let cells = ComposedImpl()

        // `from Retrying child_attempt=N` starts the child in waiting(N);
        // absent means ready. The trace format is flat by design, so a nested
        // state is addressed by a prefixed field rather than by nesting.
        var state: JobS
        switch trace.from {
        case "Idle": state = .idle
        case "Done": state = .done
        case "Retrying":
            let child: RetryS = trace.fromFields["child_attempt"]
                .map { RetryS.waiting(attempt: $0) } ?? .ready
            state = .retrying(child: child)
        default: throw SpecError("job: unknown state `\(trace.from)`")
        }

        var out: [Observed] = []
        for st in trace.steps {
            let action: JobA
            switch st.action {
            case "Run": action = .run
            case "Tick": action = .tick
            case "Cancel": action = .cancel
            default: throw SpecError("job: unknown action `\(st.action)`")
            }

            let step = jobStep(cells, ctx, state, action)
            let effects = step.effects.map(Self.effectName)
            let expect: Expect
            switch step {
            case .stay: expect = .stay
            case .ignored: expect = .ignored
            case let .go(next, _):
                state = next
                let name: String
                switch next {
                case .idle: name = "Idle"
                case .done: name = "Done"
                case .retrying: name = "Retrying"
                }
                expect = .go(state: name, fields: [:])
            }
            out.append(Observed(expect: expect, effects: effects))
        }
        return out
    }
}
