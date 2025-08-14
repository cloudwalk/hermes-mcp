{
  description = "Model Context Protocol SDK for Elixir";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05-small";
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

    zig = pkgs:
      pkgs.zig.overrideAttrs (old: rec {
        version = "0.14.0";
        src = pkgs.fetchFromGitHub {
          inherit (old.src) owner repo;
          rev = version;
          hash = "sha256-VyteIp5ZRt6qNcZR68KmM7CvN2GYf8vj5hP+gHLkuVk=";
        };
      });
  in {
    devShells = forAllSystems (pkgs: {
      default = pkgs.mkShell {
        name = "hermes-mcp-dev";
        packages = with pkgs; [
          (elixir-with-otp erlang_28)."1.18.4"
          erlang_28
          uv
          just
          go
          (zig pkgs)
          _7zz
          xz
          nodejs
          k6
        ];
      };
    });

    packages = forAllSystems (pkgs: {
      default = pkgs.stdenv.mkDerivation {
        pname = "hermes-mcp";
        version = "0.14.1"; # x-release-please-version
        src = ./.;

        buildInputs = with pkgs; [
          elixir-bin.latest
          erlang
          (zig pkgs)
          _7zz
          xz
          git
        ];

        buildPhase = ''
          export MIX_ENV=prod
          export HERMES_MCP_COMPILE_CLI=true
          export HOME=$TMPDIR

          mix do deps.get, compile
          mix release hermes_mcp --overwrite
        '';

        installPhase = ''
          mkdir -p $out/bin

          echo "=== Build output structure ==="
          find _build -type f -name "*hermes*" 2>/dev/null || true

          if [ -d "_build/prod/rel/hermes_mcp/burrito_out" ]; then
            echo "Found burrito_out directory"
            cp -r _build/prod/rel/hermes_mcp/burrito_out/* $out/bin/ || true
          elif [ -d "_build/prod/rel/hermes_mcp/bin" ]; then
            echo "Found standard release bin directory"
            cp -r _build/prod/rel/hermes_mcp/bin/* $out/bin/ || true
          else
            echo "No bin directory found, checking for other release outputs"
            find _build/prod/rel -name "*" -type f -executable | head -5
          fi

          if [ -n "$(ls -A $out/bin 2>/dev/null)" ]; then
            chmod +x $out/bin/* || true
            echo "=== Installed binaries ==="
            ls -la $out/bin/
          else
            echo "ERROR: No binaries were installed!"
            exit 1
          fi
        '';

        meta = with pkgs.lib; {
          description = "Model Context Protocol (MCP) implementation in Elixir";
          homepage = "https://github.com/cloudwalk/hermes-mcp";
          license = licenses.mit;
          maintainers = with maintainers; [zoedsoupe];
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
