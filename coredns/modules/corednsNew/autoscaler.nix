{
  pkgs,
  lib,
  config,
  ...
}:
let
  types = lib.types;
in
{

  # TODO: should have global metadata that gets merged (labels, annotations, namespaces)

  # TODO: look into set-by-null and filter null before jsoning  (for liveness probe and other defaults)

  options.services.coredns.autoscaler = lib.mkOption {
    description = "Cluster-proportional-autoscaler (CPA) configuration for CoreDNS deployment.";
    default = { };
    type = types.submodule {
      options = {
        enabled = lib.mkEnableOption {
        };

        coresPerReplica = lib.mkOption {
          type = types.int;
          default = 256;
        };

        nodesPerReplica = lib.mkOption {
          type = types.int;
          default = 16;
        };

        min = lib.mkOption {
          type = types.int;
          default = 0;
        };

        max = lib.mkOption {
          type = types.int;
          default = 0;
        };

        includeUnschedulableNodes = lib.mkOption {
          type = types.bool;
          default = false;
        };

        preventSinglePointFailure = lib.mkOption {
          type = types.bool;
          default = true;
        };

        podAnnotations = lib.mkOption {
          type = types.attrsOf types.str;
          default = { };
        };

        customFlags = lib.mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "List of extra flags like \"--nodelabels=...\"";
        };

        image = lib.mkOption {
          type = types.submodule {
            options = {
              repository = lib.mkOption {
                type = types.str;
                default = "registry.k8s.io/cpa/cluster-proportional-autoscaler";
              };
              tag = lib.mkOption {
                type = types.str;
                default = "v1.9.0";
              };
              pullPolicy = lib.mkOption {
                type = types.str;
                default = "IfNotPresent";
              };
              pullSecrets = lib.mkOption {
                type = types.listOf types.str;
                default = [ ];
              };
            };
          };
          default = { };
        };
        resources = lib.mkOption {
          type = types.submodule {
            options = {
              requests = lib.mkOption {
                type = types.attrsOf types.str;
                default = {
                  cpu = "20m";
                  memory = "10Mi";
                };
              };
              limits = lib.mkOption {
                type = types.attrsOf types.str;
                default = {
                  cpu = "20m";
                  memory = "10Mi";
                };
              };
            };
          };
          default = { };
        };

        configmap = lib.mkOption {
          type = types.submodule {
            options = {
              annotations = lib.mkOption {
                type = types.attrsOf types.str;
                default = { };
              };
            };
          };
          default = { };
        };

        livenessProbe = lib.mkOption {
          type = types.submodule {
            options = {
              enabled = lib.mkOption {
                type = types.bool;
                default = true;
              };
              initialDelaySeconds = lib.mkOption {
                type = types.int;
                default = 10;
              };
              periodSeconds = lib.mkOption {
                type = types.int;
                default = 5;
              };
              timeoutSeconds = lib.mkOption {
                type = types.int;
                default = 5;
              };
              failureThreshold = lib.mkOption {
                type = types.int;
                default = 3;
              };
              successThreshold = lib.mkOption {
                type = types.int;
                default = 1;
              };
            };
          };
          default = { };
        };

        extraContainers = lib.mkOption {
          type = types.listOf types.attrs;
          default = [ ];
        };

        extraClusterrole = lib.mkOption {
          type = types.attrsOf types.anything;
          default = { };
          example = ''
            rules = [
              {
                apiGroups = [ "apps" ];
                resources = [ "statefulsets" ];
                verbs = [ "get"; "list"; "watch" ];
              }
            ];
          '';
          description = "Attr set that will be merged on top of the generated clusterrole.yaml.";
        };

        extraClusterroleBinding = lib.mkOption {
          type = types.attrsOf types.anything;
          default = { };
          example = ''
            subjects = [
              {
                kind = "ServiceAccount";
                name = "custom-sa-name";
                namespace = "custom-namespace";
              }
            ];
          '';
          description = "Attr set that will be merged on top of the generated clusterrolebinding.yaml.";
      };

        extraDeployment = lib.mkOption {
          type = types.attrsOf types.anything;
          default = { };
          example = ''
            spec.template.spec = {
              priorityClassName = {
                ...
              };

              affinity = {
                ...
              };

              nodeSelector = {
                ...
              };

              tolerations = [
                ...
              ];
            };
          '';
          description = "Attr set that will be merged on top of the generated clusterrolebinding.yaml.";
      };
    };
  };

  config =
    let

      removeNulls = lib.filterAttrs (_: v: v != null);

      mkResource = x: extra: removeNulls (lib.recursiveUpdate x extra);

      coredns = config.services.coredns;

      autoscalername = "${coredns.applicationName}-autoscaler";
        labelsAutoscaler = {};

      clusterServiceMeta = lib.optionalAttrs coredns.isClusterService {
 "k8s-app" = lib.strings.toLower (coredns.k8sAppLabelOverride or coredns.applicationName);
        };

        nameInstance = {
              "app.kubernetes.io/instance" = chart.release.name;
              "app.kubernetes.io/name" = "${chart.name}-autoscaler"; # FIXME: not fully following chart
            };

      clusterroleAutoscaler = {
        apiVersion = "rbac.authorization.k8s.io/v1";
        kind = "ClusterRole";
        metadata = {
          name = autoscalername;
          labels = labelsAutoscaler;
          # TODO: rename to globalAnnotations
          annotations = coredns.customAnnotations;
        };
        rules = [
          {
            apiGroups = [ "" ];
            resources = [ "nodes" ];
            verbs = [
              "list"
              "watch"
            ];
          }
          {
            apiGroups = [ "" ];
            resources = [ "replicationcontrollers/scale" ];
            verbs = [
              "get"
              "update"
            ];
          }
          {
            apiGroups = [
              "extensions"
              "apps"
            ];
            resources = [
              "deployments/scale"
              "replicasets/scale"
            ];
            verbs = [
              "get"
              "update"
            ];
          }
          {
            apiGroups = [ "" ];
            resources = [ "configmaps" ];
            verbs = [
              "get"
              "create"
            ];
          }
        ];
      };

      clusterRoleAutoScalerDrv = pkgs.writeText "clusterole-autoscaler.json" (
        builtins.toJSON clusterroleAutoscaler
      );

      #  serviceaccount-autoscaler.yaml

      serviceAccountAutoScaler = {
        apiVersion = "v1";
        kind = "ServiceAccount";
        metadata = {
          name = autoscalername;
          namespace = coredns.namespace;
          labels = labelsAutoscaler;
        }
        // lib.optionalAttrs (coredns ? customAnnotations) {
          annotations = coredns.customAnnotations;
        };

        # only add if pullSecrets defined
        imagePullSecrets = lib.optional (
          coredns.autoscaler.image ? pullSecrets
        ) coredns.autoscaler.image.pullSecrets;
      };
      serviceAccountAutoScalerDrv = pkgs.writeText "serviceaccount-autoscaler.json" (
        builtins.toJSON serviceAccountAutoScaler
      );

      clusterRoleAutoScalerBinding = {
        apiVersion = "rbac.authorization.k8s.io/v1";
        kind = "ClusterRoleBinding";
        metadata = {
          name = autoscalername;
          labels = labelsAutoscaler;
          annotations = coredns.customAnnotations // {
            "nix.kix.dev/autoscalerclusterrole-dependency" = "${clusterRoleAutoScalerDrv}";
            "nix.kix.dev/autoscalerserviceaccount-dependency" = "${serviceAccountAutoScalerDrv}";
          };
        };
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "ClusterRole";
          name = autoscalername;
        };
        subjects = [
          {
            kind = "ServiceAccount";
            name = autoscalername;
            namespace = coredns.namespace;
          }
        ];
      };

      clusterRoleAutoScalerBindingDrv = pkgs.writeText "clusterrolebinding-autoscaler.json" (
        builtins.toJSON clusterRoleAutoScalerBinding
      );

      configMapAutoscaler = {
        apiVersion = "v1";
        kind = "ConfigMap";
        metadata = {
          name = autoscalername;
          namespace = coredns.namespace;
          labels = labelsAutoscaler;
          annotations = coredns.autoscaler.configmap.annotations // coredns.customAnnotations;
        };
        data = {
          linear = builtins.toJSON coredns.autoscaler;
        };
      };

      configMapAutoscalerDrv = pkgs.writeText "configmap-autoscaler.json" (
        builtins.toJSON configMapAutoscaler
      );

      deploymentAutoscaler = {
        apiVersion = "apps/v1";
        kind = "Deployment";
        metadata = {
          name = autoscalername;
          namespace = coredns.namespace;
          labels = labelsAutoscaler;
          annotations = coredns.customAnnotations;
        };
        spec = {
          replicas = 1; # TODO: make configurable
          selector = {
            matchLabels = nameInstance
            // clusterServiceMeta;
          };
          template = {
            metadata = {
              labels =
                  clusterServiceMeta
                // nameInstance
                // coredns.customLabels;
              annotations = {
                "checksum/configmap" = "${configMapAutoscalerDrv}";
                "nix.kix.dev/configmap-dependency" = "${configMapAutoscalerDrv}";
              }
              // lib.optionalAttrs coredns.rbac.create {
                "nix.kix.dev/clusterrolebinding-dependency" = "${clusterRoleAutoScalerBindingDrv}";
              }
              // lib.optionalAttrs coredns.isClusterService {
                "scheduler.alpha.kubernetes.io/tolerations" = builtins.toJSON [
                  {
                    key = "CriticalAddonsOnly";
                    operator = "Exists";
                  }
                ];
              }
              //

                coredns.autoscaler.podAnnotations; # TODO: is it on purpose that coredns helm chart does not pull in customAnnotations here?
            };
            spec = {
              serviceAccountName = autoscalername; # TODO: think about how to make this reference more effective
            }
            // lib.optionalAttrs (coredns.autoscaler.image.pullSecrets != [ ]) {
              imagePullSecrets = coredns.autoscaler.image.pullSecrets;
            }
            // {
              containers = [
                (
                  {
                    name = "autoscaler";
                    image = "${coredns.autoscaler.image.repository}:${coredns.autoscaler.image.tag}";
                    imagePullPolicy = coredns.autoscaler.image.pullPolicy;
                    resources = coredns.autoscaler.resources;
                    command = [
                      "/cluster-proportional-autoscaler"
                      "--namespace=${coredns.namespace}"
                      "--configmap=${autoscalername}"
                      "--target=Deployment/${coredns.deployment.name or coredns.applicationName}"
                      "--logtostderr=true"
                      "--v=2"
                    ]
                    ++ coredns.autoscaler.customFlags or [ ]; # FIXME: should move to submodule pattern otherwise breaks if userside not set
                  }
                  // lib.optionalAttrs (coredns.autoscaler.livenessProbe.enabled) {
                    livenessProbe = {
                      httpGet = {
                        path = "/healthz";
                        port = 8080;
                        scheme = "HTTP";
                      };
                      # TODO: I think this should be mergable with coredns.autoscaler.livenessProbe but would need to skip enabled
                      initialDelaySeconds = coredns.autoscaler.livenessProbe.initialDelaySeconds;
                      periodSeconds = coredns.autoscaler.livenessProbe.periodSeconds;
                      timeoutSeconds = coredns.autoscaler.livenessProbe.timeoutSeconds;
                      successThreshold = coredns.autoscaler.livenessProbe.successThreshold;
                      failureThreshold = coredns.autoscaler.livenessProbe.failureThreshold;
                    };
                  }
                )
              ]
              ++ coredns.autoscaler.extraContainers;
            };
          };
        };
      };

      deploymentAutoscalerDrv = pkgs.writeText "deployment-autoscaler.json" (
        builtins.toJSON deploymentAutoscaler
      );
    in
    {
      manifests =
        lib.optionalAttrs
          (config.services.coredns.autoscaler.enabled && !config.services.coredns.hpa.enabled)
          {
            "deployment-autoscaler.json" = deploymentAutoscalerDrv;
          };
    };

}
