# `nix develop ./tabular-center-kotlin`. The root flake re-exports it as `.#kotlin`.
ctx:

{
  default = ctx.mkShell "kotlin" ctx.kotlinInputs;
}
