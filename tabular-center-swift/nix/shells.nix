# `nix develop ./tabular-center-swift`; the root re-exports it as `.#swift`.
# Carries the Swift runtime path (LD_LIBRARY_PATH) and curl for swift-lock.
ctx:

{
  default = ctx.mkShell "swift" (ctx.swiftPkgs ++ [ ctx.pkgs.curl ]);
}
