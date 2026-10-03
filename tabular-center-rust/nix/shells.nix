# `nix develop ./tabular-center-rust`; the root re-exports it as `.#rust`.
ctx:

{
  default = ctx.mkShell "rust" ctx.rustInputs;
}
