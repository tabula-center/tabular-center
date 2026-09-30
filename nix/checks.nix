# The root's half of `nix flake check`: every step that reads more than one
# implementation. The per-language checks come from the language flakes and
# are merged in ../flake.nix.
#
# Every check shells out to `tools/verify <step>`. That script is the single
# source of truth for what "green" means, so the flake, CI, and a developer
# typing `./tools/verify` all run the same commands. Three lint escapes
# reached CI because the local loop and the flake checked different things; a
# duplicated list here is how that happens.
ctx:

let
  inherit (ctx) toolchains allInputs allSetup mkCheck;
  verify = name: mkCheck name [ ] "./tools/verify ${name}";
in
{
  version = verify "version";

  # doc/ is generated from spec/ and the code, and committed. Checked because
  # the pages are what diagnostic messages link to: a stale page means someone
  # following a link from an error reads about a different error.
  docs = verify "docs";

  # The check above the three matrix-stable checks. Each of those scans roots
  # it names, so a matrix in a directory none names is outside all of them and
  # silently so. This enumerates the files that exist and asks which scan
  # reaches each. No toolchain: it is `find` and `case`.
  matrix-covered = verify "matrix-covered";

  # Compares all three implementations to each other rather than each to a
  # golden. Needs no toolchain -- it reads source as text -- so it notices a
  # Swift diagnostic going missing on a machine that cannot build Swift.
  diagnostics-coverage = verify "diagnostics-coverage";

  # Asks the conformance harnesses' question earlier: they walk adapters, so an
  # incomplete fixture is invisible until one exists.
  fixtures-complete = verify "fixtures-complete";

  # tools/verify only compares. A step that can bless passes by construction.
  # Scans the root script and all three language scripts. Text only.
  no-bless = verify "no-bless";

  # Generated code is not committed, as source or as a golden. Text only.
  no-generated = verify "no-generated";

  # CONTRIBUTING says every diagnostic gets a fixture. Text only.
  diagnostics-tested = verify "diagnostics-tested";

  # The one check that must see more than one implementation at a time: the
  # renderings are not committed, so agreement is asserted by rendering from
  # each toolchain present and diffing. Rust and Kotlin are always here;
  # Swift joins where it exists. It fails rather than passes if fewer than two
  # are present, so it cannot agree with itself.
  #
  # The only root check with toolchains, and it takes them from the language
  # flakes rather than naming any here.
  renderings-agree = mkCheck "renderings-agree" allInputs ''
    ${allSetup}
    ./tools/verify renderings-agree
  '';

  # Every `.tb.` matrix is aligned as tabular-center-fmt would leave it. It
  # reads all three languages' matrices, so it is a root check; it needs only
  # the formatter's toolchain, which the formatter's flake exports.
  tb-aligned = mkCheck "tb-aligned" toolchains.fmt.inputs "./tools/verify tb-aligned";
}
