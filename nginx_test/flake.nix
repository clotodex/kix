{
  description = "PoC: Nix derivation-backed Kubernetes manifests with mini modules";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11"; # pick a commit/branch you prefer
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      perSystem =
        { pkgs, ... }:
        let
          lib = pkgs.lib;

          # user config (end-user overrides go in example-config.nix)
          userConfig = import ./example-config.nix;

          # small set of modules: each module is (pkgs: config: { manifests = ...; options = ...; })
          moduleFiles = [ ./modules/nginx.nix ];

          instantiatedModules = builtins.map (
            m:
            (import m) {
              inherit pkgs lib;
              config = userConfig;
            }
          ) moduleFiles;

          # collect manifests (each module returns an attributeset `manifests` mapping filename -> content-or-path)
          manifests = lib.foldl' (acc: m: acc // (m.manifests or { })) { } instantiatedModules;

          # Build a directory containing all manifests. The directory itself is a derivation; its hash
          # is a proof-of-state for the whole set of YAML manifests.
          #manifestsDerivation = pkgs.runCommand "k8s-manifests" { } ''
          #  mkdir -p $out
          #  ${lib.concatStringsSep "\n" (
          #    lib.mapAttrsToList (name: content: "cp ${content} $out/${name}") manifests
          #  )}
          #'';

          manifestsDerivation = pkgs.runCommand "k8s-manifests" { } ''
            mkdir -p $out
            ${lib.concatStringsSep "\n" (
              lib.mapAttrsToList (_: content: "echo ${content} >> $out/dependencies.txt") manifests
            )}
          '';
        in
        {
          packages = {
            default = manifestsDerivation;
            manifests = manifestsDerivation;
          };
        };
    };
}
