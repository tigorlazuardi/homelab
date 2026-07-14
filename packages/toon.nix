{
  lib,
  fetchurl,
  makeWrapper,
  nodejs,
  stdenvNoCC,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "toon";
  version = "2.3.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/@toon-format/cli/-/cli-${finalAttrs.version}.tgz";
    hash = "sha256-d5kKY+K+/JpY7TmFDeIfG2luKpL9XDSnyxUlRjz986o=";
  };

  citty = fetchurl {
    url = "https://registry.npmjs.org/citty/-/citty-0.2.2.tgz";
    hash = "sha256-/pO4suJ8xOsQn9n09p8x5LKIe7uA9tQ6ixuZpKlxLQE=";
  };

  consola = fetchurl {
    url = "https://registry.npmjs.org/consola/-/consola-3.4.2.tgz";
    hash = "sha256-2p/eAKfPi8AXBocrSzbkeRtr5eWjMwtTnHAqr1H7DnE=";
  };

  tokenx = fetchurl {
    url = "https://registry.npmjs.org/tokenx/-/tokenx-1.3.0.tgz";
    hash = "sha256-B9+IUrsKV0Vd0iocD+GTWK7tNF1amjfzqyeiKI2tTV8=";
  };

  nativeBuildInputs = [ makeWrapper ];

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    package=$out/lib/node_modules/@toon-format/cli
    mkdir -p \
      $package/node_modules/citty \
      $package/node_modules/consola \
      $package/node_modules/tokenx \
      $out/bin
    tar -xzf $src --strip-components=1 -C $package
    tar -xzf ${finalAttrs.citty} --strip-components=1 -C $package/node_modules/citty
    tar -xzf ${finalAttrs.consola} --strip-components=1 -C $package/node_modules/consola
    tar -xzf ${finalAttrs.tokenx} --strip-components=1 -C $package/node_modules/tokenx
    makeWrapper ${nodejs}/bin/node $out/bin/toon \
      --add-flags $package/bin/toon.mjs

    runHook postInstall
  '';

  meta = {
    description = "CLI for JSON to TOON conversion using Token-Oriented Object Notation";
    homepage = "https://github.com/toon-format/toon";
    license = lib.licenses.mit;
    mainProgram = "toon";
    platforms = lib.platforms.all;
  };
})
