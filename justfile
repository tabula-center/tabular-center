# `tools/verify` is the single source of truth for what "green" means.
# `nix flake check` runs each of its steps in a sandbox; CI runs the flake.
# All three execute the same commands.

default: verify

# Everything, the way CI sees it.
verify:
    ./tools/verify

# One step, by name: `just step test`. The header of tools/verify lists them.
step STEP:
    ./tools/verify {{STEP}}

# Sandboxed, exactly as CI runs it. Requires nix.
check:
    nix flake check --print-build-logs

fmt:
    cd tabular-center-rust && cargo fmt --all

# Replay spec/conformance against every implementation that has landed.
conformance:
    cd tabular-center-rust && cargo run -q -p tabula-conformance

# Render a machine's matrix as a diffable grid.
table-diff FIXTURE="":
    cd tabular-center-rust && cargo run -q -p tabula-conformance --bin table-diff -- {{FIXTURE}}

# Read what the macro actually generates. Reviewing this is a real exit criterion.
expand TEST="timer_matrix":
    cd tabular-center-rust && cargo expand --test {{TEST}}
