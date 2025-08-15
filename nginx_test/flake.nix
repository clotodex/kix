
{ description = "PoC: Nix derivation-backed Kubernetes manifests with mini modules";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11"; # pick a commit/branch you prefer
  };

  outputs = { self, nixpkgs }:
    let
      pkgs = import nixpkgs { system = "x86_64-linux"; };
      lib = pkgs.lib;

      # user config (end-user overrides go in example-config.nix)
      config = import ./example-config.nix;

      # small set of modules: each module is (pkgs: config: { manifests = ...; options = ...; })
      moduleFiles = [ ./modules/nginx.nix ];

      instantiatedModules = builtins.map (m: (import m) { inherit pkgs config lib; }) moduleFiles;

      # collect manifests (each module returns an attributeset `manifests` mapping filename -> content-or-path)
      manifests = lib.foldl' (acc: m: acc // (m.manifests or {})) {} instantiatedModules;
    in
    {
      # Build a directory containing all manifests. The directory itself is a derivation; its hash
      # is a proof-of-state for the whole set of YAML manifests.
      manifests = pkgs.runCommand "k8s-manifests" {} ''
        mkdir -p $out
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: content: 
          "cp ${content} $out/${name}"
        ) manifests)}
      '';

      # Use the new flake output format
      packages.x86_64-linux = {
        default = self.manifests;
        manifests = self.manifests;
      };
    };
}
