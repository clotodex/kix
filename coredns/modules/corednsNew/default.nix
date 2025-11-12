{
  lib,
  pkgs,
  config,
  kixlib,
  ...
}:

let
  types = lib.types;

  options.services.coredns = {
    enable = lib.mkOption {
      type = types.bool;
      default = false;
      description = "Enable CoreDNS service.";
    };

    # TODO: set postprocessing functions?

    applicationName = lib.mkOption {
      type = types.str;
      default = "coredns";
      description = "Application name used in resource names.";
    };

    namespace = lib.mkOption {
      type = types.str;
      default = "default";
      description = "The namespace to use";
    };

    settings = lib.mkOption {
      type = types.submodule {
        options = {
          servers = lib.mkOption {
            type = types.listOf (
              types.submodule {
                options = {
                  port = lib.mkOption {
                    type = types.int;
                    default = 53;
                    description = "Port number for this server block.";
                  };

                  servicePort = lib.mkOption {
                    type = types.nullOr types.int;
                    default = null;
                    description = "Service port (defaults to server port).";
                  };

                  nodePort = lib.mkOption {
                    type = types.nullOr types.int;
                    default = null;
                    description = "NodePort for this server.";
                  };

                  hostPort = lib.mkOption {
                    type = types.nullOr types.int;
                    default = null;
                    description = "HostPort for this server.";
                  };

                  zones = lib.mkOption {
                    type = types.listOf (
                      types.submodule {
                        options = {
                          zone = lib.mkOption {
                            type = types.str;
                            description = "DNS zone string (e.g. \".\").";
                          };

                          scheme = lib.mkOption {
                            type = types.nullOr types.str;
                            default = null;
                            description = "Zone scheme (dns://, tls://, grpc://, https://) or null for default.";
                          };

                          use_tcp = lib.mkOption {
                            type = types.bool;
                            default = false;
                            description = "If true, treat this zone as TCP-enabled.";
                          };
                        };
                      }
                    );
                    default = [ { zone = "."; } ];
                    description = "List of zones for this server.";
                  };

                  plugins = lib.mkOption {
                    type = types.listOf (
                      types.submodule {
                        options = {
                          name = lib.mkOption {
                            type = types.str;
                            description = "Plugin name (e.g. errors, health, kubernetes).";
                          };

                          parameters = lib.mkOption {
                            type = types.nullOr types.str;
                            default = null;
                            description = "Plugin parameters (string).";
                          };

                          configBlock = lib.mkOption {
                            type = types.nullOr types.str;
                            default = null;
                            description = "Optional plugin config block (multiline string).";
                          };
                        };
                      }
                    );
                    default = [ ];
                    description = "List of CoreDNS plugins for this server.";
                  };
                };
              }
            );
            default = [
              {
                zones = [
                  {
                    zone = ".";
                    use_tcp = true;
                  }
                ];
                port = 53;
                servicePort = null;
                nodePort = null;
                hostPort = null;
                plugins = [ { name = "errors"; } ];
              }
            ];
            description = "List of server blocks (CoreDNS servers). Each item is a typed submodule describing zones, port and plugins.";
          };

          extraConfig = lib.mkOption {
            type = types.submodule {
              options = { }; # dynamic config mapping
            };
            default = { };
            description = "Additional CoreDNS configuration applied outside the default zone block (e.g. import parameters).";
          };
        };
      };
    };

    isClusterService = lib.mkOption {
      type = types.bool;
      default = true;
      description = "Whether to label this as a cluster service.";
    };

    replicaCount = lib.mkOption {
      type = types.int;
      default = 1;
      description = "Number of CoreDNS replicas.";
    };

    resources = lib.mkOption {
      type = types.submodule {
        options = {
          limits = lib.mkOption {
            type = types.attrsOf types.str;
            default = {
              cpu = "100m";
              memory = "128Mi";
            };
          };
          requests = lib.mkOption {
            type = types.attrsOf types.str;
            default = {
              cpu = "100m";
              memory = "128Mi";
            };
          };
        };
      };
      default = {
        limits = {
          cpu = "100m";
          memory = "128Mi";
        };
        requests = {
          cpu = "100m";
          memory = "128Mi";
        };
      };
      description = "CPU/memory requests and limits for CoreDNS containers.";
    };

    integrations = lib.mkOption {
      type = lib.types.submodule {
        options = {
          prometheus = lib.mkOption {
            type = types.submodule {
              options = {
                enabled = lib.mkOption {
                  type = types.bool;
                  default = false;
                  description = "Enable Prometheus metrics endpoint.";
                };
              };
            };
            default = {
              enabled = false;
            };
            description = "Prometheus integration configuration.";
          };
        };
      };
    };

    # service account - can either be passed or auto-created
    serviceAccount = lib.mkOption {
      type = lib.types.submodule {
        options = {
          create = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether to create a new ServiceAccount automatically.";
          };

          name = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Name of the existing ServiceAccount (if not created).";
          };

          namespace = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Namespace of the existing ServiceAccount.";
          };
        };
      };

      default = {
        create = true;
      };
      description = ''
        ServiceAccount configuration.

        Examples:

        - Create automatically:
          ```
          serviceAccount.create = true;
          ```
        - Use an existing one:
          ```
          serviceAccount = {
            create = false;
            name = "my-sa";
            namespace = "prod";
          };
          ```
      '';
    };

    podDisruptionBudget = lib.mkOption {
      type = types.attrsOf types.anything;
      default = { };
    };

    # TODO: I want to pull this out as a dependency or parent
    # hpaing something is not coredns specific
    hpa = lib.mkOption {
      type = types.submodule {
        options = {
          enabled = lib.mkOption {
            type = types.bool;
            default = false;
          };
          minReplicas = lib.mkOption {
            type = types.int;
            default = 1;
          };
          maxReplicas = lib.mkOption {
            type = types.int;
            default = 2;
          };
          metrics = lib.mkOption {
            type = types.listOf types.attrs;
            default = [ ];
          };
        };
      };
      default = {
        enabled = false;
        minReplicas = 1;
        maxReplicas = 2;
        metrics = [ ];
      };
      description = "Optional Horizontal Pod Autoscaler (HPA) configuration for CoreDNS.";
    };
  };

  coredns = config.services.coredns;

  ports = import ./ports.nix {
    inherit lib;
    servers = coredns.servers;
  };

  applyToAll =
    resource:
    # TODO: filter for specific resources

    # add namespace and merge labels and annotations
    lib.recursiveUpdate {
      metadata.labels = {
        "app.kubernetes.io/managed-by" = "Helm";
      };
    } resource;

  kixlib' =
    (kixlib.withMetadata {

      namespace = coredns.namespace;
      # merge labels and annotations
      labels = {
        "app.kubernetes.io/managed-by" = "Helm";
        "app.kubernetes.io/instance" = "release-name";
        "helm.sh/chart" = "coredns-1.43.2";
        "app.kubernetes.io/name" = "coredns";
      }
      // lib.optionalAttrs coredns.isClusterService {
        "k8s-app" = "coredns";
        "kubernetes.io/cluster-service" = "true";
        "kubernetes.io/name" = "CoreDNS";
      };
      annotations = { };
    }).withPreprocessor
      applyToAll;

  #imports = [
  #  ./autoscaler.nix
  #  ./deployment.nix
  #];

  buildCorefile =
    { }:
    let

      inherit (lib)
        concatStringsSep
        optionalString
        concatMapStrings
        splitString
        ;

      # render extraConfig
      renderExtraConfig =
        extraConfig:
        concatStringsSep "\n" (
          map (
            name:
            let
              conf = extraConfig.${name};
            in
            name + optionalString (conf ? parameters && conf.parameters != null) (" " + conf.parameters)
          ) (builtins.attrNames extraConfig)
        );

      # render zones
      renderZone = zone: (zone.scheme or "") + (zone.zone or ".");

      renderZones = zones: if zones == [ ] then "." else concatStringsSep " " (map renderZone zones);

      # render plugins
      renderPlugin =
        plugin:
        let
          params = optionalString (plugin ? parameters && plugin.parameters != null) (
            " " + plugin.parameters
          );
          cfg = optionalString (plugin ? configBlock && plugin.configBlock != null) (
            " {\n"
            + concatMapStrings (line: "            " + line + "\n") (splitString "\n" plugin.configBlock)
            + "        }"
          );
        in
        "  " + plugin.name + params + cfg + "\n";

      # render a server
      renderServer =
        server:
        let
          zones = renderZones (server.zones or [ ]);
          port = optionalString (server ? port && server.port != null) (":" + toString server.port);
          plugins = concatStringsSep "" (map renderPlugin (server.plugins or [ ]));
        in
        zones + port + " {\n" + plugins + "}\n";

    in
    renderExtraConfig (coredns.extraConfig or { })
    + "\n"
    + concatStringsSep "\n" (map renderServer (coredns.servers or [ ]));

  deploySA = kixlib'.rbac.mkServiceAccount { };
  roleBind = kixlib'.rbac.bind (kixlib'.rbac.mkClusterRole {
    rules = [
      {
        apiGroups = [ "" ];
        resources = [
          "endpoints"
          "services"
          "pods"
          "namespaces"
        ];
        verbs = [
          "list"
          "watch"
        ];
      }
      {
        apiGroups = [ "discovery.k8s.io" ];
        resources = [ "endpointslices" ];
        verbs = [
          "list"
          "watch"
        ];
      }
    ];
  }) deploySA;

  configMapVol =
    with kixlib'.configMap;
    mkConfigMap { }
    |> withEntry "Corefile" (buildCorefile { })
    |> withEntries (
      map (zonefile: {
        key = zonefile.filename;
        value = zonefile.contents;
      }) (coredns.zoneFiles or [ ])
    )
    |> asVolume {
      # TODO: could this be auto-generated with hash? do we need to care?
      items = [
        {
          key = "Corefile";
          path = "Corefile";
        }
      ];
    };

  cContainer =
    with kixlib'.pod;
    mkContainer {
      name = "coredns";
      image = "coredns/coredns:1.12.3";
      args = [
        "-conf"
        "/etc/coredns/Corefile"
      ];
      imagePullPolicy = "IfNotPresent";
      resources = coredns.resources;
    }
    |> withVolumeMount {
      name = configMapVol.name;
      mountPath = "/etc/coredns";
    }
    # TODO: add extra secrets as volume mounts
    |> withLivenessProbe (
      coredns.livenessProbe or {
        failureThreshold = 5;
        httpGet = {
          path = "/health";
          port = 8080;
          scheme = "HTTP";
        };
        initialDelaySeconds = 60;
        periodSeconds = 10;
        successThreshold = 1;
        timeoutSeconds = 5;
      }
    )
    |> withReadinessProbe (
      coredns.livenessProbe or {
        failureThreshold = 1;
        httpGet = {
          path = "/ready";
          port = 8181;
          scheme = "HTTP";
        };
        initialDelaySeconds = 30;
        periodSeconds = 5;
        successThreshold = 1;
        timeoutSeconds = 5;
      }
    )
    |> lib.recursiveUpdate config.containerOverrides or { };

  cService =
    kixlib'.workload.mkDeployment {
      replicas = coredns.replicaCount or 1;
      # TODO: is this different from k8s default? - overriding should be a global thing
      strategy = {
        type = "RollingUpdate";
        rollingUpdate = {
          maxSurge = "25%";
          maxUnavailable = 1;
        };
      };
      metadata.labels = {
        "app.kubernetes.io/version" = "1.12.3";
      };
      template =
        kixlib'.pod.mkPodTemplate {
          metadata = {
            annotations = {
              "scheduler.alpha.kubernetes.io/tolerations" =
                ''[{"key":"CriticalAddonsOnly", "operator":"Exists"}]'';
            };
            labels = {
              # TODO:
              "k8s-app" = "coredns";
              "app.kubernetes.io/name" = "coredns";
              "app.kubernetes.io/instance" = "release-name";
            };
          };
          spec = {
            containers = [ cContainer ];
            volumes = [ configMapVol ];
            # if clusterservice, add toleration for critical addons
            dnsPolicy = lib.optionalAttrs coredns.isClusterService "Default";

          };
        }
        |> lib.recursiveUpdate config.podOverrides or { };
    }
    |> kixlib'.addDependency roleBind # FIXME: instead of this roll that as (forced) argument into withSA
    |> kixlib'.workload.withServiceAccount deploySA
    |> kixlib'.workload.intoService { spec.type = "ClusterIP"; };

  #  - monitor it -> maybe should come from prometheus app, not packaged with this
  #      - Servicemonitor
  #      - Service to select prometheus pods??
  #  - With hpa
  #      - Hpa
  #  - Or with autoscaler -> could be a dependency instead
  #      - Deployment
  #          - Service account
  #              - Clusterrolebinding
  #                  - Clusterrole
  #  - And disruption budget
  # - philosophy clash: configurable from outside or batteries included
in
{
  inherit options;

  config = {

    # TODO: assertions
    # add an assertion for the servers
    # Specifying a Server Block with a zone that is already assigned to a server and running it on the same port is an error. This Corefile will generate an error on startup
    # Note that if you use the bind plugin you can have the same zone listening on the same port, provided they are binded to different interfaces or IP addresses.

    manifests = lib.optionalAttrs coredns.enable {
      "coredns" = kixlib'.mkManifest cService;
    };
  };
}
