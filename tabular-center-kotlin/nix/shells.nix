# `nix develop ./tabular-center-kotlin`; the root re-exports it as `.#kotlin`.
ctx:

{
  default = ctx.mkShell "kotlin" ctx.kotlinInputs;
}
