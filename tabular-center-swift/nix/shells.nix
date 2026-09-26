# `nix develop ./tabular-center-swift`. The root flake re-exports it as `.#swift`.
#
# Only the shells that carry Swift get LD_LIBRARY_PATH (mkShell sets it): it is
# a blunt instrument, and there is no reason for a Rust or Kotlin shell to have
# the Swift runtime ahead of anything.
ctx:

{
  default = ctx.mkShell "swift" ctx.swiftPkgs;
}
