{
  scc,
  zig,
  stdenvNoCC,
  lib,
}: 
  let 
    fs = lib.fileset;
    sourceFiles = ../../tests/test.sh;

  in stdenvNoCC.mkDerivation {
    name = "scc-behaviour";
    version = "master";

    src = fs.toSource {
      root = ../../tests;
      fileset = sourceFiles;
    };

    nativeBuildInputs = [ scc zig ];

    dontConfigure = true;
    dontBuild = true;
    doCheck = true;

    checkPhase = ''
      zig version

      zig fmt --check .
      
      mkdir -p $out

      ./test.sh ${scc}/bin/scc
    '';

    meta = {
      description = "scc behaviour tests";
      platforms = [ "x86_64-linux" ];
    };
  }
