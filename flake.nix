{
  description = "Model Context Protocol SDK for Elixir";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    elixir-overlay.url = "github:zoedsoupe/elixir-overlay";
  };

  outputs = {
    self,
    nixpkgs,
    elixir-overlay,
  }: let
    inherit (nixpkgs.lib) genAttrs;
    inherit (nixpkgs.lib.systems) flakeExposed;

    forAllSystems = f:
      genAttrs flakeExposed (
        system: let
          overlays = [elixir-overlay.overlays.default];
          pkgs = import nixpkgs {inherit system overlays;};
        in
          f pkgs
      );
  in {
    devShells = forAllSystems (pkgs: {
      default = pkgs.mkShell {
        name = "hermes-mcp-dev";
        buildInputs = with pkgs; [
          elixir-bin.latest
          erlang
          uv
          just
          go
          zig
          _7zz
          xz
        ];
      };
    });

    packages = forAllSystems (pkgs: {
      default = pkgs.stdenv.mkDerivation {
        pname = "hermes-mcp";
        version = "0.4.1";
        src = ./.;

        buildInputs = with pkgs; [
          elixir-bin.latest
          erlang
          zig
          _7zz
          xz
          git
        ];

        buildPhase = ''
          export MIX_ENV=prod
          export HOME=$TMPDIR

          # Get dependencies and compile
          mix deps.get
          mix compile
          mix release hermes_mcp --overwrite
        '';

        installPhase = ''
          mkdir -p $out/bin

          # Try to copy burrito output first, fallback to regular release
          if [ -d "_build/prod/rel/hermes_mcp/burrito_out" ]; then
            cp -r _build/prod/rel/hermes_mcp/burrito_out/* $out/bin/ || true
          fi

          if [ -d "_build/prod/rel/hermes_mcp/bin" ]; then
            cp -r _build/prod/rel/hermes_mcp/bin/* $out/bin/ || true
          fi

          # Make binaries executable
          chmod +x $out/bin/* || true
        '';

        meta = with pkgs.lib; {
          description = "Model Context Protocol (MCP) implementation in Elixir";
          homepage = "https://github.com/cloudwalk/hermes-mcp";
          license = licenses.mit;
          maintainers = ["zoedsoupe"];
          platforms = platforms.unix ++ platforms.darwin;
        };
      };
    });

    apps = forAllSystems (pkgs: {
      default = {
        type = "app";
        program = "${self.packages.${pkgs.system}.default}/bin/hermes_mcp";
      };
    });
  };
}
