{
  pkgs,
  stdenvNoCC,

  zig,
}: let
  zigBuildFlags = "--global-cache-dir $(pwd)/.cache --cache-dir $(pwd)/zig-cache -Dcpu=baseline";
in stdenvNoCC.mkDerivation {
  name = "scc";
  version = "master";

  src = ./..;

  nativeBuildInputs = [ zig ];

  dontConfigure = true;
  dontInstall = true;
  doCheck = true;

  buildPhase = ''
    runHook preBuild

    mkdir --parents .cache
    ln --symbolic ${pkgs.callPackage ./build.zig.zon.nix {}} .cache/p

    zig build install        \
      ${zigBuildFlags}       \
      -Doptimize=ReleaseSafe \
      --prefix $out

    runHook postBuild
  '';
}
