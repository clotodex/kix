{
  pkgs ? import <nixpkgs> { },
}:

let

  # Base derivation function to copy YAML files
  mkYamlDerivation =
    name: file: deps:
    derivation {
      inherit name;
      system = builtins.currentSystem;
      src = ./.;
      buildInputs = deps ++ [ pkgs.coreutils ];
      builder = pkgs.writeScript "builder.sh" ''
        #!/bin/sh
        export PATH=${pkgs.coreutils}/bin:$PATH
        mkdir -p $out

        # Copy the main YAML file
        cp ${file} $out/

        # Create runtime references to dependencies to establish dependency tree
        for dep in ${toString deps}; do
          if [ -d "$dep" ]; then
            # Create a reference to the dependency in our output
            echo "# Depends on: $dep" >> $out/dependencies.txt
          fi
        done
      '';
      PATH = "${pkgs.coreutils}/bin";
    };

  # Dependency chain: clusterrole -> clusterrolebinding -> configmap -> service -> deployment

  # 1. ClusterRole (no dependencies)
  clusterrole = mkYamlDerivation "coredns-clusterrole" ./yamls/clusterrole.yaml [ ];

  # 2. ClusterRoleBinding (depends on ClusterRole)
  clusterrolebinding = mkYamlDerivation "coredns-clusterrolebinding" ./yamls/clusterrolebinding.yaml [
    clusterrole
  ];

  # 3. ConfigMap (depends on ClusterRoleBinding)
  configmap = mkYamlDerivation "coredns-configmap" ./yamls/configmap.yaml [ ];


  # 4. Deployment (depends on Service - this is the root node)
  deployment = mkYamlDerivation "coredns-deployment" ./yamls/deployment.yaml [ configmap  clusterrolebinding ];

  # 5. Service (depends on ConfigMap)
  service = mkYamlDerivation "coredns-service" ./yamls/service.yaml [ deployment ];

  # Combined manifests for kubectl usage
  manifests = pkgs.stdenv.mkDerivation {
    name = "coredns-manifests";
    src = ./.;
    buildInputs = [ clusterrole clusterrolebinding configmap service deployment ];

    installPhase = ''
      mkdir -p $out

      # Collect YAML files from all derivations in the dependency tree
      find "${clusterrole}" -name "*.yaml" -exec cp {} $out/ \; 2>/dev/null || true
      find "${clusterrolebinding}" -name "*.yaml" -exec cp {} $out/ \; 2>/dev/null || true
      find "${configmap}" -name "*.yaml" -exec cp {} $out/ \; 2>/dev/null || true
      find "${service}" -name "*.yaml" -exec cp {} $out/ \; 2>/dev/null || true
      find "${deployment}" -name "*.yaml" -exec cp {} $out/ \; 2>/dev/null || true

      # Create a usage README
      echo "# CoreDNS Kubernetes Manifests" > $out/README.md
      echo "" >> $out/README.md
      echo "This directory contains all the Kubernetes manifests needed to deploy CoreDNS." >> $out/README.md
      echo "" >> $out/README.md
      echo "## Usage:" >> $out/README.md
      echo "kubectl apply -f ." >> $out/README.md
      echo "" >> $out/README.md
      echo "## Files included:" >> $out/README.md
      ls $out/*.yaml 2>/dev/null | while read file; do
        echo "- $(basename "$file")" >> $out/README.md
      done || echo "No YAML files found" >> $out/README.md
    '';
  };

in
{
  # Export all derivations
  inherit clusterrole clusterrolebinding configmap service deployment;

  # The root node of the dependency tree
  default = service;

  # Combined manifests for kubectl - this is probably what you want for actual usage
  kubectl = manifests;

  # Helper to build all components
  all = pkgs.symlinkJoin {
    name = "coredns-k8s-manifests";
    paths = [
      clusterrole
      clusterrolebinding
      configmap
      service
      deployment
    ];
  };
}
