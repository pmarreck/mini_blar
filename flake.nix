{
  description = "mini_blar: constrained subset of the BLAR archive format";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    zig-overlay = {
      url = "github:mitchellh/zig-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    blip = {
      url = "github:pmarreck/BLIP/v3.0.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, zig-overlay, blip, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        zig = zig-overlay.packages.${system}."0.16.0";
        pname = "mini_blar";
        version = "3.0.0";
        isDarwin = pkgs.stdenv.isDarwin;

        # No zigDeps fixed-output derivation here (unlike the fleet-standard
        # Strategy 1): ALL Zig deps (blip, zstdz) are vendored in-tree under
        # zig-pkg/, which Zig 0.16 resolves with priority over the global
        # cache. The sandbox needs no network, so there is no hash to chase.
        # (The old FOD stopped being buildable the day deps were vendored —
        # `zig build --fetch=all` fetches nothing and zig-cache/p is never
        # created; it only "worked" via stale cache substitution.)

        commonInputs = [ zig ]
          ++ pkgs.lib.optionals isDarwin [
            pkgs.darwin.cctools
            pkgs.apple-sdk
          ];

        # -Dcpu=baseline: Nix-built artifacts are shared via binary caches
        # (Garnix), so a builder with AVX-512 must not poison the cached
        # binary with instructions that SIGILL on plainer hosts (e.g. Zen 2).
        # Same fix as zstdz@0a478bb.
        zigBuildPhase = optimize: ''
          export HOME="$TMPDIR"
          export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/zig-cache
          mkdir -p $ZIG_GLOBAL_CACHE_DIR
          zig build --prefix $out -Doptimize=${optimize} -Dcpu=baseline
        '';
      in {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [ zig hyperfine ];
        };

        packages.default = pkgs.stdenv.mkDerivation {
          inherit pname version;
          src = self;
          nativeBuildInputs = commonInputs;
          dontConfigure = true;
          dontInstall = true;
          dontFixup = true;
          buildPhase = zigBuildPhase "ReleaseFast";
        };

        checks.default = pkgs.stdenv.mkDerivation {
          pname = "${pname}-tests";
          inherit version;
          src = self;
          nativeBuildInputs = commonInputs;
          dontConfigure = true;
          dontFixup = true;
          buildPhase = ''
            export HOME="$TMPDIR"
            export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/zig-cache
            mkdir -p $ZIG_GLOBAL_CACHE_DIR
            timeout 600 zig build test -Dcpu=baseline || { echo "Tests failed"; exit 1; }
          '';
          installPhase = ''
            mkdir -p $out
            echo "tests passed" > $out/result
          '';
        };

        # The zstd-only compression profile (-Denable_compression=true, as
        # consumed by validate_gui's single-binary launcher) must round-trip
        # green too. zstdz is vendored in-tree (zig-pkg/), so the sandboxed
        # build needs no extra fetch.
        #
        # On Linux the test binary is targeted at musl: linking zstd's C code
        # pulls in libc, and a glibc-dynamic test exe can't spawn inside the
        # Nix sandbox (its /lib64 ELF interpreter doesn't exist there —
        # FileNotFound). Musl makes it fully static; no patchelf dance needed
        # (cf. zstdz@2110c2c which solved the same problem the other way).
        checks.test-compression = let
          muslFlag = pkgs.lib.optionalString pkgs.stdenv.isLinux
            "-Dtarget=${pkgs.stdenv.hostPlatform.parsed.cpu.name}-linux-musl";
        in pkgs.stdenv.mkDerivation {
          pname = "${pname}-tests-compression";
          inherit version;
          src = self;
          nativeBuildInputs = commonInputs;
          dontConfigure = true;
          dontFixup = true;
          buildPhase = ''
            export HOME="$TMPDIR"
            export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/zig-cache
            mkdir -p $ZIG_GLOBAL_CACHE_DIR
            timeout 600 zig build test -Denable_compression=true -Dcpu=baseline ${muslFlag} || { echo "Compression tests failed"; exit 1; }
          '';
          installPhase = ''
            mkdir -p $out
            echo "compression tests passed" > $out/result
          '';
        };
      }
    );
}
