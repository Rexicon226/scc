# generated by zon2nix (https://github.com/nix-community/zon2nix)

{ linkFarm, fetchzip }:

linkFarm "zig-packages" [
  {
    name = "12200d45b8662a6f8ab8f2c30623cee77a5e7bc95867a1f1c15d64e9bddd4e25bab9";
    path = fetchzip {
      url = "https://github.com/nektro/zig-tracer/archive/e5b21467c891fe9a2956358a38b496a5d9a174fc.tar.gz";
      hash = "sha256-c9sav0dUvAS9iySk2WoVUzmEfslcCnaGthPrslUkQ24=";
    };
  }
]