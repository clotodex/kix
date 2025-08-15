# Simplified Nginx Kubernetes Module for KiX
#
# This module provides a simple but flexible Nginx deployment for Kubernetes.
# Users can either use simple options or extend manifests with raw attribute sets.
#
# Usage:
#   services.nginx = {
#     enable = true;
#     replicas = 2;
#     # Extend manifests directly
#     deploymentExtras = { spec.template.spec.nodeSelector.disktype = "ssd"; };
#   };

{
  pkgs,
  config,
  lib,
}:

let
  # Simple default nginx config
  defaultConfig = ''
    events { worker_connections 1024; }
    http {
        server {
            listen 80;
            location / {
                root /usr/share/nginx/html;
                index index.html;
            }
            location /health {
                return 200 "ok";
                add_header Content-Type text/plain;
            }
        }
    }
  '';

  # Simplified options
  options = {
    services.nginx = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable Nginx service";
      };

      image = lib.mkOption {
        type = lib.types.str;
        default = "nginx:alpine";
        description = "Docker image";
      };

      replicas = lib.mkOption {
        type = lib.types.int;
        default = 1;
        description = "Number of replicas";
      };

      config = lib.mkOption {
        type = lib.types.str;
        default = defaultConfig;
        description = "Nginx configuration";
      };

      # Raw attribute set extensions and overrides
      configMapExtras = lib.mkOption {
        type = lib.types.attrs;
        default = {};
        description = "Additional attributes to merge into ConfigMap manifest";
        example = {
          metadata.annotations."config.alpha.kubernetes.io/managed-by" = "kix";
          data."custom-file.conf" = "custom content";
        };
      };

      deploymentExtras = lib.mkOption {
        type = lib.types.attrs;
        default = {};
        description = "Additional attributes to merge into Deployment manifest";
        example = {
          spec.template.spec.nodeSelector.disktype = "ssd";
          spec.template.spec.containers = [{
            name = "nginx";
            env = [{ name = "DEBUG"; value = "true"; }];
          }];
        };
      };

      serviceExtras = lib.mkOption {
        type = lib.types.attrs;
        default = {};
        description = "Additional attributes to merge into Service manifest";
        example = {
          spec.type = "LoadBalancer";
          metadata.annotations."service.beta.kubernetes.io/aws-load-balancer-type" = "nlb";
        };
      };

      # Complete manifest overrides
      manifests = lib.mkOption {
        type = lib.types.attrs;
        default = {};
        description = "Raw Kubernetes manifests to use instead of generated ones. Keys should be manifest names.";
        example = {
          "configmap-nginx.json" = {
            apiVersion = "v1";
            kind = "ConfigMap";
            metadata.name = "custom-nginx-config";
            data."nginx.conf" = "events {}; http { server { listen 8080; } }";
          };
        };
      };
    };
  };

  # Get config with defaults
  cfg = config.services.nginx or {};
  
  # Simple defaults
  defaults = {
    enable = false;
    image = "nginx:alpine";
    replicas = 1;
    config = defaultConfig;
    configMapExtras = {};
    deploymentExtras = {};
    serviceExtras = {};
    manifests = {};
  };

  # Merge user config with defaults
  finalCfg = defaults // cfg;

  # Simple base manifests
  baseConfigMap = {
    apiVersion = "v1";
    kind = "ConfigMap";
    metadata = {
      name = "nginx-config";
      labels.app = "nginx";
    };
    data = {
      "nginx.conf" = finalCfg.config;
    };
  };

  baseDeployment = {
    apiVersion = "apps/v1";
    kind = "Deployment";
    metadata = {
      name = "nginx-deployment";
      labels.app = "nginx";
    };
    spec = {
      replicas = finalCfg.replicas;
      selector.matchLabels.app = "nginx";
      template = {
        metadata.labels.app = "nginx";
        spec = {
          containers = [{
            name = "nginx";
            image = finalCfg.image;
            ports = [{ containerPort = 80; }];
            volumeMounts = [{
              name = "nginx-conf";
              mountPath = "/etc/nginx/nginx.conf";
              subPath = "nginx.conf";
            }];
          }];
          volumes = [{
            name = "nginx-conf";
            configMap.name = "nginx-config";
          }];
        };
      };
    };
  };

  baseService = {
    apiVersion = "v1";
    kind = "Service";
    metadata = {
      name = "nginx-service";
      labels.app = "nginx";
    };
    spec = {
      selector.app = "nginx";
      ports = [{ port = 80; targetPort = 80; }];
    };
  };

  # Merge base manifests with user extensions
  configMapManifest = lib.recursiveUpdate baseConfigMap finalCfg.configMapExtras;
  deploymentManifest = lib.recursiveUpdate baseDeployment finalCfg.deploymentExtras;
  serviceManifest = lib.recursiveUpdate baseService finalCfg.serviceExtras;

  # Support for complete manifest overrides
  finalManifests = 
    if finalCfg.manifests != {} then
      # Use user-provided manifests, but convert to JSON files
      lib.mapAttrs (name: manifest: 
        pkgs.writeText name (builtins.toJSON manifest)
      ) finalCfg.manifests
    else
      # Use generated manifests with extensions
      {
        "configmap-nginx.json" = pkgs.writeText "configmap-nginx.json" (builtins.toJSON configMapManifest);
        "deployment-nginx.json" = pkgs.writeText "deployment-nginx.json" (builtins.toJSON deploymentManifest);
        "service-nginx.json" = pkgs.writeText "service-nginx.json" (builtins.toJSON serviceManifest);
      };

in
{
  # Export the options for module system integration
  inherit options;

  # Export manifests only if the service is enabled
  manifests = lib.optionalAttrs finalCfg.enable finalManifests;
}
