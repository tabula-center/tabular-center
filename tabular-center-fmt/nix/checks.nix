# The formatter's own checks: its tests (the contract as cases, and
# idempotence), clippy, and rustfmt on its source. Whether the repository's
# matrices are aligned is the root's `tb-aligned`.
ctx:

let
  verify = name: ctx.mkCheck name "./tabular-center-fmt/tools/verify ${name}";
in
{
  tb-fmt-test = verify "tb-fmt-test";
  tb-fmt-clippy = verify "tb-fmt-clippy";
  tb-fmt-rustfmt = verify "tb-fmt-rustfmt";
}
