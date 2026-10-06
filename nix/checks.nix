# The root's half of `nix flake check`: the steps that read more than one
# implementation, or the repository as a whole. Each check is
# `tools/verify <step>`; the per-language checks come from the language
# flakes and are merged in ../flake.nix.
ctx:

let
  inherit (ctx) toolchains allInputs allSetup mkCheck;
  verify = name: mkCheck name [ ] "./tools/verify ${name}";
in
{
  version = verify "version";

  docs = verify "docs";

  licenses = verify "licenses";
  no-comments = verify "no-comments";
  deps-consistent = verify "deps-consistent";
  compatibility = verify "compatibility";

  matrix-covered = verify "matrix-covered";

  diagnostics-coverage = verify "diagnostics-coverage";

  fixtures-complete = verify "fixtures-complete";

  no-bless = verify "no-bless";

  no-generated = verify "no-generated";

  diagnostics-tested = verify "diagnostics-tested";

  renderings-agree = mkCheck "renderings-agree" allInputs ''
    ${allSetup}
    ./tools/verify renderings-agree
  '';

  tb-aligned = mkCheck "tb-aligned" toolchains.fmt.inputs "./tools/verify tb-aligned";
}
