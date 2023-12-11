{
  description = "";

  inputs = {
    nixpkgs = {
      url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    };

    tools = {
      url = "github:RGBCube/FlakeTools";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zig = {
      url = "github:mitchellh/zig-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zls = {
      url = "github:zigtools/zls/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, tools, zig, zls, ... }: 
    tools.recursiveUpdateMap (system: let
    # Not legacy just weird naming. See the nixpkgs flake.
    pkgs = nixpkgs.legacyPackages.${system};
  in {
    devShells.${system}.default = pkgs.callPackage ./nix/devShell.nix {
      inherit (zls.packages.${system}) zls;

      zig = zig.packages.${system}.master;
    };

    packages.${system} = rec {
      scc = pkgs.callPackage ./nix/package.nix {
        zig = zig.packages.${system}.master;
      };
      default = scc;
    };

    checks.${system} = rec {
      behaviour = pkgs.callPackage ./nix/checks/behaviour.nix {
        inherit (self.packages.${system}) scc;
        zig = zig.packages.${system}.master;
      };
    };

  # Our supported systems are the same supported systems as the Zig binaries.
  }) (builtins.attrNames zig.packages);
}
