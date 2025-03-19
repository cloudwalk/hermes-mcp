{
  description = "Model Context Porotocol SDK for Elixir";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = {nixpkgs, ...}: let
    inherit (nixpkgs.lib) genAttrs;
    inherit (nixpkgs.lib.systems) flakeExposed;
    forAllSystems = f:
      genAttrs flakeExposed (system: f (import nixpkgs {inherit system;}));
  in {
    devShells = forAllSystems (pkgs: let
      inherit (pkgs) mkShell;
      inherit (pkgs.beam.interpreters) erlang_27;
      inherit (pkgs.beam) packagesWith;
      beam = packagesWith erlang_27;
      elixir_1_18 = beam.elixir.override {
        version = "1.18.3";

        src = pkgs.fetchFromGitHub {
          owner = "elixir-lang";
          repo = "elixir";
          rev = "v1.18.3";
          sha256 = "sha256-jH+1+IBWHSTyqakGClkP1Q4O2FWbHx7kd7zn6YGCog0=";
        };
      };
    in {
      default = mkShell {
        name = "hermes-ex";
        packages = with pkgs; [elixir_1_18 uv just go zig _7zz xz];
      };
    });
  };
}
