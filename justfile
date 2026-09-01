default: test

test: test-rust compile-fail conformance

test-rust:
    cd rust && cargo test --all-features

# Every diagnostic in spec/diagnostics.md must have a fixture that fails to
# compile with the expected message.
compile-fail:
    ./tools/compile-fail

fmt:
    cd rust && cargo fmt --all

lint:
    cd rust && cargo clippy --all-targets --all-features -- -D warnings

no-std:
    cd rust && cargo build -p tabula --no-default-features --target thumbv7em-none-eabihf

# Replay spec/conformance against every implementation that has landed.
conformance:
    cd rust && cargo run -q -p tabula-conformance

# Render a machine's matrix as a diffable grid.
table-diff FIXTURE="":
    cd rust && cargo run -q -p tabula-conformance --bin table-diff -- {{FIXTURE}}

expand EXAMPLE="timer_matrix":
    cd rust && cargo expand --example {{EXAMPLE}}
