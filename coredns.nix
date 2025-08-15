# Simplified CoreDNS Kubernetes Module for KiX
#
# This module provides a flexible CoreDNS deployment for Kubernetes.
# Users can either use simple options or extend manifests with raw attribute sets.
#
# Usage:
#   services.coredns = {
#     enable = true;
#     replicas = 2;
#     servers = [
#       {
#         port = 53;
#         zones = [{ zone = "."; }];
#         plugins = [
#           { name = "errors"; }
#           { name = "health"; parameters = ":8080"; }
#           { name = "ready"; }
#           { name = "kubernetes"; parameters = "cluster.local in-addr.arpa ip6.arpa"; }
#           { name = "prometheus"; parameters = ":9153"; }
#           { name = "forward"; parameters = ". /etc/resolv.conf"; }
#           { name = "cache"; parameters = "30"; }
#           { name = "loop"; }
#           { name = "reload"; }
#           { name = "loadbalance"; }
#         ];
#       }
#     ];
#   };

{
  pkgs,
  config,
  lib,
}:

let
  # Helper functions for naming and labeling (similar to Helm templates)
  helpers = rec {
    # Generate name (equivalent to coredns.name template)
    name = nameOverride: 
      if nameOverride != null then lib.strings.substring 0 63 (lib.strings.removeSuffix "-" nameOverride)
      else "coredns";
    
    # Generate full name (equivalent to coredns.fullname template)
    fullname = { fullnameOverride ? null, nameOverride ? null, releaseName ? "coredns" }:
      if fullnameOverride != null then 
        lib.strings.substring 0 63 (lib.strings.removeSuffix "-" fullnameOverride)
      else
        let
          chartName = name nameOverride;
        in
        if lib.hasInfix chartName releaseName then
          lib.strings.substring 0 63 (lib.strings.removeSuffix "-" releaseName)
        else
          lib.strings.substring 0 63 (lib.strings.removeSuffix "-" "${releaseName}-${chartName}");
    
    # Generate k8s app label (equivalent to coredns.k8sapplabel template)
    k8sAppLabel = k8sAppLabelOverride:
      if k8sAppLabelOverride != null then 
        lib.strings.substring 0 63 (lib.strings.removeSuffix "-" k8sAppLabelOverride)
      else "coredns";
    
    # Generate common labels (equivalent to coredns.labels template)
    labels = { isClusterService ? false, k8sAppLabelOverride ? null, chartVersion ? "1.0.0" }: 
      {
        "app.kubernetes.io/name" = name null;
        "app.kubernetes.io/instance" = "coredns";
        "app.kubernetes.io/managed-by" = "kix";
        "helm.sh/chart" = "coredns-${lib.replaceStrings ["+"] ["_"] chartVersion}";
      } // lib.optionalAttrs isClusterService {
        "k8s-app" = k8sAppLabel k8sAppLabelOverride;
        "kubernetes.io/cluster-service" = "true";
        "kubernetes.io/name" = "CoreDNS";
      };
    
    # Generate autoscaler labels  
    autoscalerLabels = { isClusterService ? false, k8sAppLabelOverride ? null, chartVersion ? "1.0.0" }:
      {
        "app.kubernetes.io/name" = "${name null}-autoscaler";
        "app.kubernetes.io/instance" = "coredns";
        "app.kubernetes.io/managed-by" = "kix";
        "helm.sh/chart" = "coredns-${lib.replaceStrings ["+"] ["_"] chartVersion}";
      } // lib.optionalAttrs isClusterService {
        "k8s-app" = "${k8sAppLabel k8sAppLabelOverride}-autoscaler";
        "kubernetes.io/cluster-service" = "true";
        "kubernetes.io/name" = "CoreDNS";
      };
  };

  # Port generation logic (equivalent to coredns.servicePorts and coredns.containerPorts templates)
  portLogic = {
    # Extract ports from server configuration
    extractPorts = servers:
      let
        # Process each server block
        processServer = server:
          let
            port = toString server.port;
            servicePort = if server ? servicePort then server.servicePort else server.port;
            
            # Process zones to determine protocols
            processZones = zones:
              let
                processZone = zone:
                  let
                    scheme = zone.scheme or "";
                    useTcp = zone.use_tcp or false;
                  in
                  {
                    isUdp = lib.elem scheme ["dns://" ""] || useTcp;
                    isTcp = lib.elem scheme ["tls://" "grpc://" "https://"] || (scheme == "dns://" && useTcp) || (scheme == "" && useTcp);
                  };
                
                zoneResults = map processZone zones;
                
              in
              {
                isUdp = lib.any (z: z.isUdp) zoneResults || (zones == [] || lib.all (z: z.scheme or "" == "") zoneResults);
                isTcp = lib.any (z: z.isTcp) zoneResults;
              };
            
            zoneProtocols = processZones (server.zones or []);
            
            # Extract prometheus port from plugins
            prometheusPort = 
              let
                prometheusPlugins = lib.filter (p: p.name == "prometheus") (server.plugins or []);
              in
              if prometheusPlugins != [] then
                let
                  plugin = lib.head prometheusPlugins;
                  addr = plugin.parameters or ":9153";
                  parts = lib.splitString ":" addr;
                in
                if lib.length parts >= 2 then lib.last parts else null
              else null;
          in
          {
            "${port}" = {
              servicePort = servicePort;
              isUdp = zoneProtocols.isUdp;
              isTcp = zoneProtocols.isTcp;
            } // lib.optionalAttrs (server ? nodePort) {
              nodePort = server.nodePort;
            } // lib.optionalAttrs (server ? hostPort) {
              hostPort = server.hostPort;
            };
          } // lib.optionalAttrs (prometheusPort != null) {
            "${prometheusPort}" = {
              servicePort = lib.toInt prometheusPort;
              isUdp = false;
              isTcp = true;
            };
          };
        
        serverPorts = map processServer servers;
      in
      lib.foldl' lib.recursiveUpdate {} serverPorts;
    
    # Generate service ports
    generateServicePorts = portDict:
      lib.flatten (lib.mapAttrsToList (port: info:
        let
          portInt = lib.toInt port;
          portList = []
            ++ lib.optional info.isUdp {
              port = info.servicePort;
              protocol = "UDP";
              name = "udp-${port}";
              targetPort = portInt;
            }
            ++ lib.optional info.isTcp {
              port = info.servicePort;
              protocol = "TCP";
              name = "tcp-${port}";
              targetPort = portInt;
            };
        in
        map (p: p // lib.optionalAttrs (info ? nodePort) { nodePort = info.nodePort; }) portList
      ) portDict);
    
    # Generate container ports
    generateContainerPorts = portDict:
      lib.flatten (lib.mapAttrsToList (port: info:
        let
          portInt = lib.toInt port;
          portList = []
            ++ lib.optional info.isUdp {
              containerPort = portInt;
              protocol = "UDP";
              name = "udp-${port}";
            }
            ++ lib.optional info.isTcp {
              containerPort = portInt;
              protocol = "TCP";
              name = "tcp-${port}";
            };
        in
        map (p: p // lib.optionalAttrs (info ? hostPort) { hostPort = info.hostPort; }) portList
      ) portDict);
  };

  # Generate CoreDNS configuration from servers
  generateCorefile = servers:
    let
      generateServerBlock = server:
        let
          # Generate zone list
          zones = lib.concatStringsSep " " (map (zone: 
            if zone ? scheme && zone.scheme != "" then "${zone.scheme}${zone.zone}"
            else zone.zone
          ) (server.zones or [{ zone = "."; }]));
          
          # Generate plugin list
          plugins = lib.concatStringsSep "\n    " (map (plugin:
            if plugin ? parameters then "${plugin.name} ${plugin.parameters}"
            else plugin.name
          ) (server.plugins or []));
        in
        ''
          ${zones}:${toString server.port} {
              ${plugins}
          }
        '';
    in
    lib.concatStringsSep "\n\n" (map generateServerBlock servers);

  # Default CoreDNS configuration
  defaultServers = [
    {
      port = 53;
      zones = [{ zone = "."; }];
      plugins = [
        { name = "errors"; }
        { name = "health"; parameters = ":8080"; }
        { name = "ready"; }
        { name = "kubernetes"; parameters = "cluster.local in-addr.arpa ip6.arpa"; }
        { name = "prometheus"; parameters = ":9153"; }
        { name = "forward"; parameters = ". /etc/resolv.conf"; }
        { name = "cache"; parameters = "30"; }
        { name = "loop"; }
        { name = "reload"; }
        { name = "loadbalance"; }
      ];
    }
  ];

  # Module options
  options = {
    services.coredns = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable CoreDNS service";
      };

      replicas = lib.mkOption {
        type = lib.types.int;
        default = 2;
        description = "Number of replicas";
      };

      servers = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule {
          options = {
            port = lib.mkOption {
              type = lib.types.int;
              default = 53;
              description = "Port number for this server block";
            };

            servicePort = lib.mkOption {
              type = lib.types.nullOr lib.types.int;
              default = null;
              description = "Service port (defaults to server port)";
            };

            nodePort = lib.mkOption {
              type = lib.types.nullOr lib.types.int;
              default = null;
              description = "NodePort for this server";
            };

            hostPort = lib.mkOption {
              type = lib.types.nullOr lib.types.int;
              default = null;
              description = "Host port for this server";
            };

            zones = lib.mkOption {
              type = lib.types.listOf (lib.types.submodule {
                options = {
                  zone = lib.mkOption {
                    type = lib.types.str;
                    description = "DNS zone";
                  };

                  scheme = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                    description = "Zone scheme (dns://, tls://, grpc://, https://)";
                  };

                  use_tcp = lib.mkOption {
                    type = lib.types.bool;
                    default = false;
                    description = "Enable TCP for DNS zones";
                  };
                };
              });
              default = [{ zone = "."; }];
              description = "List of zones for this server";
            };

            plugins = lib.mkOption {
              type = lib.types.listOf (lib.types.submodule {
                options = {
                  name = lib.mkOption {
                    type = lib.types.str;
                    description = "Plugin name";
                  };

                  parameters = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                    description = "Plugin parameters";
                  };
                };
              });
              default = [];
              description = "List of CoreDNS plugins for this server";
            };
          };
        });
        default = defaultServers;
        description = "CoreDNS server blocks configuration";
      };

      # RBAC options
      rbac = {
        create = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Create RBAC resources";
        };

        pspEnable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable Pod Security Policy";
        };
      };

      # Service Account options
      serviceAccount = {
        create = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Create service account";
        };

        name = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Service account name";
        };
      };

      # Cluster service options
      isClusterService = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether this is a cluster service";
      };

      k8sAppLabelOverride = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Override for k8s-app label";
      };

      # Deployment options
      deployment = {
        enabled = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable deployment";
        };

        skipConfig = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Skip creating ConfigMap";
        };

        name = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Override deployment name";
        };

        annotations = lib.mkOption {
          type = lib.types.attrs;
          default = {};
          description = "Deployment annotations";
        };

        selector = lib.mkOption {
          type = lib.types.nullOr lib.types.attrs;
          default = null;
          description = "Override deployment selector";
        };
      };

      # Autoscaler options
      autoscaler = {
        enabled = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable cluster proportional autoscaler";
        };

        image = lib.mkOption {
          type = lib.types.submodule {
            options = {
              repository = lib.mkOption {
                type = lib.types.str;
                default = "k8s.gcr.io/cpa/cluster-proportional-autoscaler";
                description = "Image repository";
              };

              tag = lib.mkOption {
                type = lib.types.str;
                default = "1.8.5";
                description = "Image tag";
              };

              pullPolicy = lib.mkOption {
                type = lib.types.str;
                default = "IfNotPresent";
                description = "Image pull policy";
              };

              pullSecrets = lib.mkOption {
                type = lib.types.listOf lib.types.attrs;
                default = [];
                description = "Image pull secrets";
              };
            };
          };
          default = {};
          description = "Autoscaler image configuration";
        };

        coresPerReplica = lib.mkOption {
          type = lib.types.float;
          default = 256.0;
          description = "Cores per replica for autoscaling";
        };

        nodesPerReplica = lib.mkOption {
          type = lib.types.float;
          default = 16.0;
          description = "Nodes per replica for autoscaling";
        };

        min = lib.mkOption {
          type = lib.types.int;
          default = 1;
          description = "Minimum replicas";
        };

        max = lib.mkOption {
          type = lib.types.int;
          default = 10;
          description = "Maximum replicas";
        };

        preventSinglePointFailure = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Prevent single point of failure";
        };

        includeUnschedulableNodes = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Include unschedulable nodes in calculations";
        };

        configmap = {
          annotations = lib.mkOption {
            type = lib.types.attrs;
            default = {};
            description = "Autoscaler ConfigMap annotations";
          };
        };

        podAnnotations = lib.mkOption {
          type = lib.types.attrs;
          default = {};
          description = "Autoscaler pod annotations";
        };

        priorityClassName = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Autoscaler priority class name";
        };

        affinity = lib.mkOption {
          type = lib.types.attrs;
          default = {};
          description = "Autoscaler pod affinity";
        };

        tolerations = lib.mkOption {
          type = lib.types.listOf lib.types.attrs;
          default = [];
          description = "Autoscaler pod tolerations";
        };

        nodeSelector = lib.mkOption {
          type = lib.types.attrs;
          default = {};
          description = "Autoscaler node selector";
        };

        resources = lib.mkOption {
          type = lib.types.attrs;
          default = {};
          description = "Autoscaler container resources";
        };

        livenessProbe = {
          enabled = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable autoscaler liveness probe";
          };

          initialDelaySeconds = lib.mkOption {
            type = lib.types.int;
            default = 10;
            description = "Liveness probe initial delay";
          };

          periodSeconds = lib.mkOption {
            type = lib.types.int;
            default = 10;
            description = "Liveness probe period";
          };

          timeoutSeconds = lib.mkOption {
            type = lib.types.int;
            default = 5;
            description = "Liveness probe timeout";
          };

          successThreshold = lib.mkOption {
            type = lib.types.int;
            default = 1;
            description = "Liveness probe success threshold";
          };

          failureThreshold = lib.mkOption {
            type = lib.types.int;
            default = 3;
            description = "Liveness probe failure threshold";
          };
        };

        customFlags = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = "Custom flags for autoscaler";
        };

        extraContainers = lib.mkOption {
          type = lib.types.listOf lib.types.attrs;
          default = [];
          description = "Extra containers for autoscaler pod";
        };
      };

      # HPA options
      hpa = {
        enabled = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable HorizontalPodAutoscaler";
        };

        minReplicas = lib.mkOption {
          type = lib.types.int;
          default = 1;
          description = "HPA minimum replicas";
        };

        maxReplicas = lib.mkOption {
          type = lib.types.int;
          default = 10;
          description = "HPA maximum replicas";
        };

        metrics = lib.mkOption {
          type = lib.types.listOf lib.types.attrs;
          default = [];
          description = "HPA metrics configuration";
        };

        behavior = lib.mkOption {
          type = lib.types.nullOr lib.types.attrs;
          default = null;
          description = "HPA scaling behavior";
        };
      };

      # Pod Disruption Budget
      podDisruptionBudget = lib.mkOption {
        type = lib.types.nullOr lib.types.attrs;
        default = null;
        description = "Pod disruption budget configuration";
      };

      # Additional CoreDNS configuration
      extraConfig = lib.mkOption {
        type = lib.types.attrs;
        default = {};
        description = "Extra configuration blocks to add to Corefile";
      };

      zoneFiles = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule {
          options = {
            filename = lib.mkOption {
              type = lib.types.str;
              description = "Zone file name";
            };

            contents = lib.mkOption {
              type = lib.types.str;
              description = "Zone file contents";
            };
          };
        });
        default = [];
        description = "Additional zone files";
      };

      # Main image configuration
      image = lib.mkOption {
        type = lib.types.submodule {
          options = {
            repository = lib.mkOption {
              type = lib.types.str;
              default = "coredns/coredns";
              description = "CoreDNS image repository";
            };

            tag = lib.mkOption {
              type = lib.types.str;
              default = "1.11.1";
              description = "CoreDNS image tag";
            };

            pullPolicy = lib.mkOption {
              type = lib.types.str;
              default = "IfNotPresent";
              description = "Image pull policy";
            };

            pullSecrets = lib.mkOption {
              type = lib.types.listOf lib.types.attrs;
              default = [];
              description = "Image pull secrets";
            };
          };
        };
        default = {};
        description = "CoreDNS image configuration";
      };

      # Pod configuration
      replicaCount = lib.mkOption {
        type = lib.types.int;
        default = 2;
        description = "Number of replicas (used when autoscaler and HPA are disabled)";
      };

      rollingUpdate = {
        maxUnavailable = lib.mkOption {
          type = lib.types.either lib.types.int lib.types.str;
          default = 1;
          description = "Max unavailable during rolling update";
        };

        maxSurge = lib.mkOption {
          type = lib.types.either lib.types.int lib.types.str;
          default = "25%";
          description = "Max surge during rolling update";
        };
      };

      podSecurityContext = lib.mkOption {
        type = lib.types.attrs;
        default = {};
        description = "Pod security context";
      };

      securityContext = lib.mkOption {
        type = lib.types.attrs;
        default = {};
        description = "Container security context";
      };

      terminationGracePeriodSeconds = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "Termination grace period";
      };

      priorityClassName = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Priority class name";
      };

      affinity = lib.mkOption {
        type = lib.types.attrs;
        default = {};
        description = "Pod affinity";
      };

      topologySpreadConstraints = lib.mkOption {
        type = lib.types.listOf lib.types.attrs;
        default = [];
        description = "Topology spread constraints";
      };

      tolerations = lib.mkOption {
        type = lib.types.listOf lib.types.attrs;
        default = [];
        description = "Pod tolerations";
      };

      nodeSelector = lib.mkOption {
        type = lib.types.attrs;
        default = {};
        description = "Node selector";
      };

      initContainers = lib.mkOption {
        type = lib.types.listOf lib.types.attrs;
        default = [];
        description = "Init containers";
      };

      extraContainers = lib.mkOption {
        type = lib.types.listOf lib.types.attrs;
        default = [];
        description = "Extra containers";
      };

      extraSecrets = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Secret name";
            };

            mountPath = lib.mkOption {
              type = lib.types.str;
              description = "Mount path";
            };

            defaultMode = lib.mkOption {
              type = lib.types.nullOr lib.types.int;
              default = null;
              description = "Default file mode";
            };
          };
        });
        default = [];
        description = "Extra secrets to mount";
      };

      extraVolumeMounts = lib.mkOption {
        type = lib.types.listOf lib.types.attrs;
        default = [];
        description = "Extra volume mounts";
      };

      extraVolumes = lib.mkOption {
        type = lib.types.listOf lib.types.attrs;
        default = [];
        description = "Extra volumes";
      };

      env = lib.mkOption {
        type = lib.types.listOf lib.types.attrs;
        default = [];
        description = "Environment variables";
      };

      resources = lib.mkOption {
        type = lib.types.attrs;
        default = {};
        description = "Container resources";
      };

      livenessProbe = {
        enabled = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable liveness probe";
        };

        initialDelaySeconds = lib.mkOption {
          type = lib.types.int;
          default = 60;
          description = "Liveness probe initial delay";
        };

        periodSeconds = lib.mkOption {
          type = lib.types.int;
          default = 10;
          description = "Liveness probe period";
        };

        timeoutSeconds = lib.mkOption {
          type = lib.types.int;
          default = 5;
          description = "Liveness probe timeout";
        };

        successThreshold = lib.mkOption {
          type = lib.types.int;
          default = 1;
          description = "Liveness probe success threshold";
        };

        failureThreshold = lib.mkOption {
          type = lib.types.int;
          default = 5;
          description = "Liveness probe failure threshold";
        };
      };

      readinessProbe = {
        enabled = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable readiness probe";
        };

        initialDelaySeconds = lib.mkOption {
          type = lib.types.int;
          default = 30;
          description = "Readiness probe initial delay";
        };

        periodSeconds = lib.mkOption {
          type = lib.types.int;
          default = 10;
          description = "Readiness probe period";
        };

        timeoutSeconds = lib.mkOption {
          type = lib.types.int;
          default = 5;
          description = "Readiness probe timeout";
        };

        successThreshold = lib.mkOption {
          type = lib.types.int;
          default = 1;
          description = "Readiness probe success threshold";
        };

        failureThreshold = lib.mkOption {
          type = lib.types.int;
          default = 3;
          description = "Readiness probe failure threshold";
        };
      };

      podAnnotations = lib.mkOption {
        type = lib.types.attrs;
        default = {};
        description = "Pod annotations";
      };

      # Naming overrides
      nameOverride = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Override the name";
      };

      fullnameOverride = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Override the full name";
      };

      # Custom labels and annotations
      customLabels = lib.mkOption {
        type = lib.types.attrs;
        default = {};
        description = "Custom labels to add to all resources";
      };

      customAnnotations = lib.mkOption {
        type = lib.types.attrs;
        default = {};
        description = "Custom annotations to add to all resources";
      };

      # Raw attribute set extensions and overrides
      configMapExtras = lib.mkOption {
        type = lib.types.attrs;
        default = {};
        description = "Additional attributes to merge into ConfigMap manifest";
      };

      deploymentExtras = lib.mkOption {
        type = lib.types.attrs;
        default = {};
        description = "Additional attributes to merge into Deployment manifest";
      };

      serviceExtras = lib.mkOption {
        type = lib.types.attrs;
        default = {};
        description = "Additional attributes to merge into Service manifest";
      };

      serviceAccountExtras = lib.mkOption {
        type = lib.types.attrs;
        default = {};
        description = "Additional attributes to merge into ServiceAccount manifest";
      };

      clusterRoleExtras = lib.mkOption {
        type = lib.types.attrs;
        default = {};
        description = "Additional attributes to merge into ClusterRole manifest";
      };

      clusterRoleBindingExtras = lib.mkOption {
        type = lib.types.attrs;
        default = {};
        description = "Additional attributes to merge into ClusterRoleBinding manifest";
      };

      # Complete manifest overrides
      manifests = lib.mkOption {
        type = lib.types.attrs;
        default = {};
        description = "Raw Kubernetes manifests to use instead of generated ones. Keys should be manifest names.";
      };
    };
  };

  # Get config with defaults
  cfg = config.services.coredns or {};
  
  # Simple defaults
  defaults = {
    enable = false;
    image = "coredns/coredns:1.11.1";
    replicas = 2;
    servers = defaultServers;
    rbac.create = true;
    rbac.pspEnable = false;
    serviceAccount.create = true;
    serviceAccount.name = null;
    isClusterService = true;
    k8sAppLabelOverride = null;
    autoscaler.enabled = false;
    autoscaler.image = "k8s.gcr.io/cpa/cluster-proportional-autoscaler:1.8.5";
    autoscaler.coresPerReplica = 256;
    autoscaler.nodesPerReplica = 16;
    autoscaler.min = 1;
    autoscaler.max = 10;
    nameOverride = null;
    fullnameOverride = null;
    customLabels = {};
    customAnnotations = {};
    configMapExtras = {};
    deploymentExtras = {};
    serviceExtras = {};
    serviceAccountExtras = {};
    clusterRoleExtras = {};
    clusterRoleBindingExtras = {};
    manifests = {};
  };

  # Merge user config with defaults
  finalCfg = lib.recursiveUpdate defaults cfg;

  # Calculate derived values
  appName = helpers.name finalCfg.nameOverride;
  fullName = helpers.fullname {
    inherit (finalCfg) fullnameOverride nameOverride;
  };
  serviceAccountName = if finalCfg.serviceAccount.create then 
    (finalCfg.serviceAccount.name or fullName) else 
    (finalCfg.serviceAccount.name or "default");
  
  # Generate Corefile content
  corefileContent = generateCorefile finalCfg.servers;
  
  # Extract port information
  portDict = portLogic.extractPorts finalCfg.servers;
  servicePorts = portLogic.generateServicePorts portDict;
  containerPorts = portLogic.generateContainerPorts portDict;
  
  # Common labels
  commonLabels = helpers.labels {
    inherit (finalCfg) isClusterService k8sAppLabelOverride;
  } // finalCfg.customLabels;
  
  autoscalerCommonLabels = helpers.autoscalerLabels {
    inherit (finalCfg) isClusterService k8sAppLabelOverride;
  } // finalCfg.customLabels;

in
{
  # Export the options for module system integration
  inherit options;

  # Generate manifests
  generatedManifests = 
    let
      # Generate extraConfig block for Corefile
      extraConfigBlock = if finalCfg.extraConfig != {} then
        lib.concatStringsSep "\n" (lib.mapAttrsToList (name: conf:
          if conf ? parameters then "${name} ${conf.parameters}"
          else name
        ) finalCfg.extraConfig)
      else "";
      
      # Enhanced Corefile generation with extraConfig
      enhancedCorefileContent = if extraConfigBlock != "" then
        "${extraConfigBlock}\n${corefileContent}"
      else
        corefileContent;

      # Base ConfigMap for main CoreDNS
      baseConfigMap = lib.optionalAttrs (finalCfg.deployment.enabled && !finalCfg.deployment.skipConfig) {
        apiVersion = "v1";
        kind = "ConfigMap";
        metadata = {
          name = fullName;
          labels = commonLabels;
        } // lib.optionalAttrs (finalCfg.customAnnotations != {}) {
          annotations = finalCfg.customAnnotations;
        };
        data = {
          Corefile = enhancedCorefileContent;
        } // lib.foldl' (acc: zoneFile: acc // {
          "${zoneFile.filename}" = zoneFile.contents;
        }) {} finalCfg.zoneFiles;
      };

      # Autoscaler ConfigMap  
      autoscalerConfigMap = lib.optionalAttrs finalCfg.autoscaler.enabled {
        apiVersion = "v1";
        kind = "ConfigMap";
        metadata = {
          name = "${fullName}-autoscaler";
          labels = autoscalerCommonLabels;
        } // lib.optionalAttrs (finalCfg.customAnnotations != {} || finalCfg.autoscaler.configmap.annotations != {}) {
          annotations = finalCfg.customAnnotations // finalCfg.autoscaler.configmap.annotations;
        };
        data = {
          linear = builtins.toJSON {
            coresPerReplica = finalCfg.autoscaler.coresPerReplica;
            nodesPerReplica = finalCfg.autoscaler.nodesPerReplica;
            preventSinglePointFailure = finalCfg.autoscaler.preventSinglePointFailure;
            min = finalCfg.autoscaler.min;
            max = finalCfg.autoscaler.max;
            includeUnschedulableNodes = finalCfg.autoscaler.includeUnschedulableNodes;
          };
        };
      };

      # Main CoreDNS Deployment
      mainDeployment = lib.optionalAttrs finalCfg.deployment.enabled {
        apiVersion = "apps/v1";
        kind = "Deployment";
        metadata = {
          name = finalCfg.deployment.name or fullName;
          labels = commonLabels // {
            "app.kubernetes.io/version" = lib.replaceStrings [":"] ["-"] (lib.replaceStrings ["@"] ["_"] (lib.substring 0 63 (lib.removeSuffix "-" finalCfg.image.tag)));
          };
        } // lib.optionalAttrs (finalCfg.customAnnotations != {} || finalCfg.deployment.annotations != {}) {
          annotations = finalCfg.customAnnotations // finalCfg.deployment.annotations;
        };
        spec = {
          strategy = {
            type = "RollingUpdate";
            rollingUpdate = {
              maxUnavailable = finalCfg.rollingUpdate.maxUnavailable;
              maxSurge = finalCfg.rollingUpdate.maxSurge;
            };
          };
          selector = finalCfg.deployment.selector or {
            matchLabels = {
              "app.kubernetes.io/instance" = "coredns";
              "app.kubernetes.io/name" = appName;
            } // lib.optionalAttrs finalCfg.isClusterService {
              "k8s-app" = helpers.k8sAppLabel finalCfg.k8sAppLabelOverride;
            };
          };
          template = {
            metadata = {
              labels = {
                "app.kubernetes.io/name" = appName;
                "app.kubernetes.io/instance" = "coredns";
              } // lib.optionalAttrs finalCfg.isClusterService {
                "k8s-app" = helpers.k8sAppLabel finalCfg.k8sAppLabelOverride;
              } // finalCfg.customLabels;
              annotations = {
                "checksum/config" = "generated-by-nix";
              } // lib.optionalAttrs finalCfg.isClusterService {
                "scheduler.alpha.kubernetes.io/tolerations" = "[{\"key\":\"CriticalAddonsOnly\", \"operator\":\"Exists\"}]";
              } // finalCfg.podAnnotations;
            };
            spec = {
              serviceAccountName = serviceAccountName;
            } // lib.optionalAttrs (finalCfg.podSecurityContext != {}) {
              securityContext = finalCfg.podSecurityContext;
            } // lib.optionalAttrs (finalCfg.terminationGracePeriodSeconds != null) {
              terminationGracePeriodSeconds = finalCfg.terminationGracePeriodSeconds;
            } // lib.optionalAttrs (finalCfg.priorityClassName != null) {
              priorityClassName = finalCfg.priorityClassName;
            } // lib.optionalAttrs finalCfg.isClusterService {
              dnsPolicy = "Default";
            } // lib.optionalAttrs (finalCfg.affinity != {}) {
              affinity = finalCfg.affinity;
            } // lib.optionalAttrs (finalCfg.topologySpreadConstraints != []) {
              topologySpreadConstraints = finalCfg.topologySpreadConstraints;
            } // lib.optionalAttrs (finalCfg.tolerations != []) {
              tolerations = finalCfg.tolerations;
            } // lib.optionalAttrs (finalCfg.nodeSelector != {}) {
              nodeSelector = finalCfg.nodeSelector;
            } // lib.optionalAttrs (finalCfg.image.pullSecrets != []) {
              imagePullSecrets = finalCfg.image.pullSecrets;
            } // lib.optionalAttrs (finalCfg.initContainers != []) {
              initContainers = finalCfg.initContainers;
            } // {
              containers = [{
                name = "coredns";
                image = "${finalCfg.image.repository}:${finalCfg.image.tag}";
                imagePullPolicy = finalCfg.image.pullPolicy;
                args = [ "-conf" "/etc/coredns/Corefile" ];
                volumeMounts = [{
                  name = "config-volume";
                  mountPath = "/etc/coredns";
                }] ++ (map (secret: {
                  name = secret.name;
                  mountPath = secret.mountPath;
                  readOnly = true;
                }) finalCfg.extraSecrets) ++ finalCfg.extraVolumeMounts;
                ports = containerPorts;
                resources = finalCfg.resources;
              } // lib.optionalAttrs (finalCfg.env != []) {
                env = finalCfg.env;
              } // lib.optionalAttrs finalCfg.livenessProbe.enabled {
                livenessProbe = {
                  httpGet = {
                    path = "/health";
                    port = 8080;
                    scheme = "HTTP";
                  };
                  initialDelaySeconds = finalCfg.livenessProbe.initialDelaySeconds;
                  periodSeconds = finalCfg.livenessProbe.periodSeconds;
                  timeoutSeconds = finalCfg.livenessProbe.timeoutSeconds;
                  successThreshold = finalCfg.livenessProbe.successThreshold;
                  failureThreshold = finalCfg.livenessProbe.failureThreshold;
                };
              } // lib.optionalAttrs finalCfg.readinessProbe.enabled {
                readinessProbe = {
                  httpGet = {
                    path = "/ready";
                    port = 8181;
                    scheme = "HTTP";
                  };
                  initialDelaySeconds = finalCfg.readinessProbe.initialDelaySeconds;
                  periodSeconds = finalCfg.readinessProbe.periodSeconds;
                  timeoutSeconds = finalCfg.readinessProbe.timeoutSeconds;
                  successThreshold = finalCfg.readinessProbe.successThreshold;
                  failureThreshold = finalCfg.readinessProbe.failureThreshold;
                };
              } // lib.optionalAttrs (finalCfg.securityContext != {}) {
                securityContext = finalCfg.securityContext;
              }] ++ finalCfg.extraContainers;
              volumes = [{
                name = "config-volume";
                configMap = {
                  name = fullName;
                  items = [{
                    key = "Corefile";
                    path = "Corefile";
                  }] ++ (map (zoneFile: {
                    key = zoneFile.filename;
                    path = zoneFile.filename;
                  }) finalCfg.zoneFiles);
                };
              }] ++ (map (secret: {
                name = secret.name;
                secret = {
                  secretName = secret.name;
                } // lib.optionalAttrs (secret.defaultMode != null) {
                  defaultMode = secret.defaultMode;
                };
              }) finalCfg.extraSecrets) ++ finalCfg.extraVolumes;
            };
          };
        } // lib.optionalAttrs (!finalCfg.autoscaler.enabled && !finalCfg.hpa.enabled) {
          replicas = finalCfg.replicaCount;
        };
      };

      # Autoscaler Deployment
      autoscalerDeployment = lib.optionalAttrs (finalCfg.autoscaler.enabled && !finalCfg.hpa.enabled) {
        apiVersion = "apps/v1";
        kind = "Deployment";
        metadata = {
          name = "${fullName}-autoscaler";
          labels = autoscalerCommonLabels;
        } // lib.optionalAttrs (finalCfg.customAnnotations != {}) {
          annotations = finalCfg.customAnnotations;
        };
        spec = {
          selector = {
            matchLabels = {
              "app.kubernetes.io/instance" = "coredns";
              "app.kubernetes.io/name" = "${appName}-autoscaler";
            } // lib.optionalAttrs finalCfg.isClusterService {
              "k8s-app" = "${helpers.k8sAppLabel finalCfg.k8sAppLabelOverride}-autoscaler";
            };
          };
          template = {
            metadata = {
              labels = {
                "app.kubernetes.io/name" = "${appName}-autoscaler";
                "app.kubernetes.io/instance" = "coredns";
              } // lib.optionalAttrs finalCfg.isClusterService {
                "k8s-app" = "${helpers.k8sAppLabel finalCfg.k8sAppLabelOverride}-autoscaler";
              } // finalCfg.customLabels;
              annotations = {
                "checksum/configmap" = "generated-by-nix";
              } // lib.optionalAttrs finalCfg.isClusterService {
                "scheduler.alpha.kubernetes.io/tolerations" = "[{\"key\":\"CriticalAddonsOnly\", \"operator\":\"Exists\"}]";
              } // finalCfg.autoscaler.podAnnotations;
            };
            spec = {
              serviceAccountName = "${fullName}-autoscaler";
            } // lib.optionalAttrs (finalCfg.autoscaler.priorityClassName != null || finalCfg.priorityClassName != null) {
              priorityClassName = finalCfg.autoscaler.priorityClassName or finalCfg.priorityClassName;
            } // lib.optionalAttrs (finalCfg.autoscaler.affinity != {}) {
              affinity = finalCfg.autoscaler.affinity;
            } // lib.optionalAttrs (finalCfg.autoscaler.tolerations != []) {
              tolerations = finalCfg.autoscaler.tolerations;
            } // lib.optionalAttrs (finalCfg.autoscaler.nodeSelector != {}) {
              nodeSelector = finalCfg.autoscaler.nodeSelector;
            } // lib.optionalAttrs (finalCfg.autoscaler.image.pullSecrets != []) {
              imagePullSecrets = finalCfg.autoscaler.image.pullSecrets;
            } // {
              containers = [{
                name = "autoscaler";
                image = "${finalCfg.autoscaler.image.repository}:${finalCfg.autoscaler.image.tag}";
                imagePullPolicy = finalCfg.autoscaler.image.pullPolicy;
                resources = finalCfg.autoscaler.resources;
                command = [
                  "/cluster-proportional-autoscaler"
                  "--namespace=default"  # This should be templated
                  "--configmap=${fullName}-autoscaler"
                  "--target=Deployment/${finalCfg.deployment.name or fullName}"
                  "--logtostderr=true"
                  "--v=2"
                ] ++ finalCfg.autoscaler.customFlags;
              } // lib.optionalAttrs finalCfg.autoscaler.livenessProbe.enabled {
                livenessProbe = {
                  httpGet = {
                    path = "/healthz";
                    port = 8080;
                    scheme = "HTTP";
                  };
                  initialDelaySeconds = finalCfg.autoscaler.livenessProbe.initialDelaySeconds;
                  periodSeconds = finalCfg.autoscaler.livenessProbe.periodSeconds;
                  timeoutSeconds = finalCfg.autoscaler.livenessProbe.timeoutSeconds;
                  successThreshold = finalCfg.autoscaler.livenessProbe.successThreshold;
                  failureThreshold = finalCfg.autoscaler.livenessProbe.failureThreshold;
                };
              }] ++ finalCfg.autoscaler.extraContainers;
            };
          };
        };
      };

      # HorizontalPodAutoscaler
      hpa = lib.optionalAttrs (finalCfg.hpa.enabled && !finalCfg.autoscaler.enabled) {
        apiVersion = "autoscaling/v2";
        kind = "HorizontalPodAutoscaler";
        metadata = {
          name = fullName;
          labels = commonLabels;
        } // lib.optionalAttrs (finalCfg.customAnnotations != {}) {
          annotations = finalCfg.customAnnotations;
        };
        spec = {
          scaleTargetRef = {
            apiVersion = "apps/v1";
            kind = "Deployment";
            name = finalCfg.deployment.name or fullName;
          };
          minReplicas = finalCfg.hpa.minReplicas;
          maxReplicas = finalCfg.hpa.maxReplicas;
          metrics = finalCfg.hpa.metrics;
        } // lib.optionalAttrs (finalCfg.hpa.behavior != null) {
          behavior = finalCfg.hpa.behavior;
        };
      };

      # Main Service
      mainService = lib.optionalAttrs finalCfg.deployment.enabled {
        apiVersion = "v1";
        kind = "Service";
        metadata = {
          name = fullName;
          labels = commonLabels;
        } // lib.optionalAttrs (finalCfg.customAnnotations != {}) {
          annotations = finalCfg.customAnnotations;
        };
        spec = {
          selector = {
            "app.kubernetes.io/instance" = "coredns";
            "app.kubernetes.io/name" = appName;
          } // lib.optionalAttrs finalCfg.isClusterService {
            "k8s-app" = helpers.k8sAppLabel finalCfg.k8sAppLabelOverride;
          };
          ports = servicePorts;
        } // lib.optionalAttrs finalCfg.isClusterService {
          clusterIP = "10.96.0.10";  # Standard CoreDNS cluster IP
        };
      };

      # ServiceAccount
      serviceAccount = lib.optionalAttrs finalCfg.serviceAccount.create {
        apiVersion = "v1";
        kind = "ServiceAccount";
        metadata = {
          name = serviceAccountName;
          labels = commonLabels;
        } // lib.optionalAttrs (finalCfg.customAnnotations != {}) {
          annotations = finalCfg.customAnnotations;
        };
      };

      # Autoscaler ServiceAccount
      autoscalerServiceAccount = lib.optionalAttrs finalCfg.autoscaler.enabled {
        apiVersion = "v1";
        kind = "ServiceAccount";
        metadata = {
          name = "${fullName}-autoscaler";
          labels = autoscalerCommonLabels;
        } // lib.optionalAttrs (finalCfg.customAnnotations != {}) {
          annotations = finalCfg.customAnnotations;
        };
      };

      # ClusterRole
      clusterRole = lib.optionalAttrs finalCfg.rbac.create {
        apiVersion = "rbac.authorization.k8s.io/v1";
        kind = "ClusterRole";
        metadata = {
          name = fullName;
          labels = commonLabels;
        } // lib.optionalAttrs (finalCfg.customAnnotations != {}) {
          annotations = finalCfg.customAnnotations;
        };
        rules = [
          {
            apiGroups = [""];
            resources = ["endpoints" "services" "pods" "namespaces"];
            verbs = ["list" "watch"];
          }
          {
            apiGroups = ["discovery.k8s.io"];
            resources = ["endpointslices"];
            verbs = ["list" "watch"];
          }
        ];
      };

      # Autoscaler ClusterRole
      autoscalerClusterRole = lib.optionalAttrs finalCfg.autoscaler.enabled {
        apiVersion = "rbac.authorization.k8s.io/v1";
        kind = "ClusterRole";
        metadata = {
          name = "${fullName}-autoscaler";
          labels = autoscalerCommonLabels;
        } // lib.optionalAttrs (finalCfg.customAnnotations != {}) {
          annotations = finalCfg.customAnnotations;
        };
        rules = [
          {
            apiGroups = [""];
            resources = ["nodes"];
            verbs = ["list" "watch"];
          }
          {
            apiGroups = [""];
            resources = ["replicationcontrollers/scale"];
            verbs = ["get" "update"];
          }
          {
            apiGroups = ["apps"];
            resources = ["deployments/scale" "replicasets/scale"];
            verbs = ["get" "update"];
          }
          {
            apiGroups = [""];
            resources = ["configmaps"];
            verbs = ["get" "create"];
          }
        ];
      };

      # ClusterRoleBinding
      clusterRoleBinding = lib.optionalAttrs finalCfg.rbac.create {
        apiVersion = "rbac.authorization.k8s.io/v1";
        kind = "ClusterRoleBinding";
        metadata = {
          name = fullName;
          labels = commonLabels;
        } // lib.optionalAttrs (finalCfg.customAnnotations != {}) {
          annotations = finalCfg.customAnnotations;
        };
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "ClusterRole";
          name = fullName;
        };
        subjects = [{
          kind = "ServiceAccount";
          name = serviceAccountName;
          namespace = "default";  # This should be templated
        }];
      };

      # Autoscaler ClusterRoleBinding
      autoscalerClusterRoleBinding = lib.optionalAttrs finalCfg.autoscaler.enabled {
        apiVersion = "rbac.authorization.k8s.io/v1";
        kind = "ClusterRoleBinding";
        metadata = {
          name = "${fullName}-autoscaler";
          labels = autoscalerCommonLabels;
        } // lib.optionalAttrs (finalCfg.customAnnotations != {}) {
          annotations = finalCfg.customAnnotations;
        };
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "ClusterRole";
          name = "${fullName}-autoscaler";
        };
        subjects = [{
          kind = "ServiceAccount";
          name = "${fullName}-autoscaler";
          namespace = "default";  # This should be templated
        }];
      };

      # PodDisruptionBudget
      pdb = lib.optionalAttrs (finalCfg.deployment.enabled && finalCfg.podDisruptionBudget != null) {
        apiVersion = "policy/v1";
        kind = "PodDisruptionBudget";
        metadata = {
          name = fullName;
          labels = commonLabels;
        } // lib.optionalAttrs (finalCfg.customAnnotations != {}) {
          annotations = finalCfg.customAnnotations;
        };
        spec = finalCfg.podDisruptionBudget // lib.optionalAttrs (!(finalCfg.podDisruptionBudget ? selector)) {
          selector = {
            matchLabels = {
              "app.kubernetes.io/instance" = "coredns";
              "app.kubernetes.io/name" = appName;
            } // lib.optionalAttrs finalCfg.isClusterService {
              "k8s-app" = helpers.k8sAppLabel finalCfg.k8sAppLabelOverride;
            };
          };
        };
      };

    in
    lib.filterAttrs (_: v: v != {}) {
      "configmap-coredns.json" = if baseConfigMap != {} then pkgs.writeText "configmap-coredns.json" (builtins.toJSON (lib.recursiveUpdate baseConfigMap finalCfg.configMapExtras)) else {};
      "configmap-autoscaler.json" = if autoscalerConfigMap != {} then pkgs.writeText "configmap-autoscaler.json" (builtins.toJSON autoscalerConfigMap) else {};
      "deployment-coredns.json" = if mainDeployment != {} then pkgs.writeText "deployment-coredns.json" (builtins.toJSON (lib.recursiveUpdate mainDeployment finalCfg.deploymentExtras)) else {};
      "deployment-autoscaler.json" = if autoscalerDeployment != {} then pkgs.writeText "deployment-autoscaler.json" (builtins.toJSON autoscalerDeployment) else {};
      "service-coredns.json" = if mainService != {} then pkgs.writeText "service-coredns.json" (builtins.toJSON (lib.recursiveUpdate mainService finalCfg.serviceExtras)) else {};
      "serviceaccount-coredns.json" = if serviceAccount != {} then pkgs.writeText "serviceaccount-coredns.json" (builtins.toJSON (lib.recursiveUpdate serviceAccount finalCfg.serviceAccountExtras)) else {};
      "serviceaccount-autoscaler.json" = if autoscalerServiceAccount != {} then pkgs.writeText "serviceaccount-autoscaler.json" (builtins.toJSON autoscalerServiceAccount) else {};
      "clusterrole-coredns.json" = if clusterRole != {} then pkgs.writeText "clusterrole-coredns.json" (builtins.toJSON (lib.recursiveUpdate clusterRole finalCfg.clusterRoleExtras)) else {};
      "clusterrole-autoscaler.json" = if autoscalerClusterRole != {} then pkgs.writeText "clusterrole-autoscaler.json" (builtins.toJSON autoscalerClusterRole) else {};
      "clusterrolebinding-coredns.json" = if clusterRoleBinding != {} then pkgs.writeText "clusterrolebinding-coredns.json" (builtins.toJSON (lib.recursiveUpdate clusterRoleBinding finalCfg.clusterRoleBindingExtras)) else {};
      "clusterrolebinding-autoscaler.json" = if autoscalerClusterRoleBinding != {} then pkgs.writeText "clusterrolebinding-autoscaler.json" (builtins.toJSON autoscalerClusterRoleBinding) else {};
      "hpa-coredns.json" = if hpa != {} then pkgs.writeText "hpa-coredns.json" (builtins.toJSON hpa) else {};
      "pdb-coredns.json" = if pdb != {} then pkgs.writeText "pdb-coredns.json" (builtins.toJSON pdb) else {};
    };

  # Export manifests only if the service is enabled
  manifests = lib.optionalAttrs finalCfg.enable (
    if finalCfg.manifests != {} then
      # Use user-provided manifests
      lib.mapAttrs (name: manifest: 
        pkgs.writeText name (builtins.toJSON manifest)
      ) finalCfg.manifests
    else
      # Use generated manifests
      generatedManifests
  );
}

