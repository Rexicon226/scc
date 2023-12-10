{
  zig,
  zls,
  zon2nix,

  mkShell,
}:

mkShell {
  name = "scc";

  buildInputs = [
    zig
    zls
    zon2nix
  ];
}
