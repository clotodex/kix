{ lib, ... }:
let
  types = lib.types;
in
{
  options.services.coredns.deployment = lib.mkOption {
    type = types.submodule {
      options = {
        skipConfig = lib.mkOption {
          type = types.bool;
          default = false;
        };
        enabled = lib.mkOption {
          type = types.bool;
          default = true;
        };
        name = lib.mkOption {
          type = types.str;
          default = "";
        };
        annotations = lib.mkOption {
          type = types.attrsOf types.str;
          default = { };
        };
        selector = lib.mkOption {
          type = types.attrsOf types.anything;
          default = { };
        };
        initContainers = lib.mkOption {
          type = types.listOf types.attrs;
          default = [ ];
        };
        affinity = lib.mkOption {
          type = types.attrsOf types.anything;
          default = { };
        };
        topologySpreadConstraints = lib.mkOption {
          type = types.listOf types.attrs;
          default = [ ];
        };
        nodeSelector = lib.mkOption {
          type = types.attrsOf types.str;
          default = { };
        };
        tolerations = lib.mkOption {
          type = types.listOf types.attrs;
          default = [ ];
        };
        extraContainers = lib.mkOption {
          type = types.listOf types.attrs;
          default = [ ];
        };
        extraVolumes = lib.mkOption {
          type = types.listOf types.attrs;
          default = [ ];
        };
        extraVolumeMounts = lib.mkOption {
          type = types.listOf types.attrs;
          default = [ ];
        };
        extraSecrets = lib.mkOption {
          type = types.listOf types.attrs;
          default = [ ];
        };
        env = lib.mkOption {
          type = types.listOf types.attrs;
          default = [ ];
        };
      };
    };
    default = {
      skipConfig = false;
      enabled = true;
      name = "";
      annotations = { };
      selector = { };
      initContainers = [ ];
      affinity = { };
      topologySpreadConstraints = [ ];
      nodeSelector = { };
      tolerations = [ ];
      extraContainers = [ ];
      extraVolumes = [ ];
      extraVolumeMounts = [ ];
      extraSecrets = [ ];
      env = [ ];
    };
    description = "Deployment-level configuration for CoreDNS (pods, selectors, topologySpreadConstraints, extra volumes, env, etc).";
  };
}
