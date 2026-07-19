{
  lib,
  rustPlatform,
  fetchFromGitHub,
  git,
}:
rustPlatform.buildRustPackage {
  pname = "push";
  version = "0.8.0-unstable-2026-07-19";

  src = fetchFromGitHub {
    owner = "owainlewis";
    repo = "push";
    rev = "00d64d843fd28c5bc315ce8fa09fad6c952afe96";
    hash = "sha256-+wAey9r8oq3Clar7AegO/m/be4x+U+ZkTtng9dP4n0I=";
  };

  cargoHash = "sha256-fkawKcPzxMW3VUuntvSnOgd6eKT6QAozQ2ysU5ORWeU=";
  nativeBuildInputs = [ git ];

  meta = {
    description = "Personal assistant messaging gateway";
    homepage = "https://github.com/owainlewis/push";
    license = lib.licenses.mit;
    mainProgram = "push";
  };
}
