# `nix develop ./tabular-center-rust`. The root flake re-exports it as `.#rust`.
ctx:

{
  default = ctx.mkShell "rust" ctx.rustInputs;
}
