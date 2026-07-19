{
  lib,
  stdenvNoCC,
  fetchurl,
}:
stdenvNoCC.mkDerivation {
  pname = "push";
  version = "0.8.0";

  src = fetchurl {
    url = "https://github.com/owainlewis/push/releases/download/v0.8.0/push-v0.8.0-x86_64-unknown-linux-gnu.tar.gz";
    hash = "sha256-T2EI2qLYymJwYoRpGXjdtnnXyd0mLduUsXIISbNOxfg=";
  };

  installPhase = ''
    runHook preInstall
    install -Dm755 push -t $out/bin
    runHook postInstall
  '';

  meta = {
    description = "Personal assistant messaging gateway";
    homepage = "https://github.com/owainlewis/push";
    license = lib.licenses.mit;
    mainProgram = "push";
    platforms = [ "x86_64-linux" ];
  };
}
