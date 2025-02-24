{
  description = "Model Context Porotocol SDK for Elixir";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";

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
        version = "1.18.2";

        src = pkgs.fetchFromGitHub {
          owner = "elixir-lang";
          repo = "elixir";
          rev = "v1.18.2";
          sha256 = "sha256-8FhUKAaEjBBcF0etVPdkxMfrnR5niU40U8cxDRJdEok=";
        };
      };
    in {
      default = mkShell {
        name = "hermes-ex";
        packages = with pkgs; [elixir_1_18 uv just];
      };
    });
  };
}
