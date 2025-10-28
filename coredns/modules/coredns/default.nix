{
  lib,
  pkgs,
  config,
  ...
}:

let
  types = lib.types;

  imports = [
    ./autoscaler.nix
    ./deployment.nix
  ];

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

    podDisruptionBudget = lib.mkOption {
      type = types.attrsOf types.anything;
      default = { };
    };

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
    extra = lib.mkOption {
      type = types.submodule {
        options = {
          extraConfig = lib.mkOption {
            type = types.attrsOf types.anything;
            default = { };
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
        extraConfig = { };
        extraContainers = [ ];
        extraVolumes = [ ];
        extraVolumeMounts = [ ];
        extraSecrets = [ ];
        env = [ ];
      };
      description = "Extra files/containers/volumes/secrets/env for CoreDNS pods.";
    };
    image = lib.mkOption {
      type = types.submodule {
        options = {
          repository = lib.mkOption {
            type = types.str;
            default = "coredns/coredns";
          };
          tag = lib.mkOption {
            type = types.str;
            default = "";
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
      default = {
        repository = "coredns/coredns";
        tag = ""; # defaults to chart appVersion in helm
        pullPolicy = "IfNotPresent";
        pullSecrets = [ ]; # list of { name = "..." } or string names
      };
      description = "Container image configuration for CoreDNS.";
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
            default = 60;
          };
          periodSeconds = lib.mkOption {
            type = types.int;
            default = 10;
          };
          timeoutSeconds = lib.mkOption {
            type = types.int;
            default = 5;
          };
          failureThreshold = lib.mkOption {
            type = types.int;
            default = 5;
          };
          successThreshold = lib.mkOption {
            type = types.int;
            default = 1;
          };
        };
      };
      default = {
        enabled = true;
        initialDelaySeconds = 60;
        periodSeconds = 10;
        timeoutSeconds = 5;
        failureThreshold = 5;
        successThreshold = 1;
      };
      description = "Liveness probe configuration for CoreDNS (requires the 'health' plugin enabled).";
    };

    readinessProbe = lib.mkOption {
      type = types.submodule {
        options = {
          enabled = lib.mkOption {
            type = types.bool;
            default = true;
          };
          initialDelaySeconds = lib.mkOption {
            type = types.int;
            default = 30;
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
            default = 1;
          };
          successThreshold = lib.mkOption {
            type = types.int;
            default = 1;
          };
        };
      };
      default = {
        enabled = true;
        initialDelaySeconds = 30;
        periodSeconds = 5;
        timeoutSeconds = 5;
        failureThreshold = 1;
        successThreshold = 1;
      };
      description = "Readiness probe configuration for CoreDNS (requires the 'ready' plugin enabled).";
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

    rollingUpdate = lib.mkOption {
      type = types.attrsOf types.anything;
      default = {
        maxUnavailable = 1;
        maxSurge = "25%";
      };
      description = "Rolling update strategy for CoreDNS Deployment.";
    };

    terminationGracePeriodSeconds = lib.mkOption {
      type = types.int;
      default = 30;
      description = "Termination grace period (seconds) for CoreDNS pods.";
    };

    priorityClassName = lib.mkOption {
      type = types.str;
      default = "";
      description = "Optional priority class name used for CoreDNS pods.";
    };
    podSecurityContext = lib.mkOption {
      type = types.submodule {
        options = { }; # flexible mapping; default is an empty attribute set
      };
      default = { };
      description = "Pod-level securityContext for CoreDNS pods.";
    };

    securityContext = lib.mkOption {
      type = types.submodule {
        options = {
          allowPrivilegeEscalation = lib.mkOption {
            type = types.bool;
            default = false;
          };
          capabilities = lib.mkOption {
            type = types.attrsOf types.anything;
            default = {
              add = [ "NET_BIND_SERVICE" ];
              drop = [ "ALL" ];
            };
          };
          readOnlyRootFilesystem = lib.mkOption {
            type = types.bool;
            default = true;
          };
        };
      };
      default = {
        allowPrivilegeEscalation = false;
        capabilities = {
          add = [ "NET_BIND_SERVICE" ];
          drop = [ "ALL" ];
        };
        readOnlyRootFilesystem = true;
      };
      description = "Container securityContext for the CoreDNS container.";
    };

    podAnnotations = lib.mkOption {
      type = types.submodule {
        options = { }; # arbitrary annotations map
      };
      default = { };
      description = "Annotations applied to CoreDNS pods.";
    };
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

    zoneFiles = lib.mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            filename = lib.mkOption {
              type = types.str;
              default = "";
            };
            domain = lib.mkOption {
              type = types.str;
              default = "";
            };
            contents = lib.mkOption {
              type = types.str;
              default = "";
            };
          };
        }
      );
      default = [ ];
      description = "Custom zone files to configure CoreDNS. Entries should be { filename, domain, contents }.";
    };

    serviceType = lib.mkOption {
      type = types.str;
      default = "ClusterIP";
    };
    service = lib.mkOption {
      type = types.submodule {
        options = {
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
          serviceType = lib.mkOption {
            type = types.str;
            default = "ClusterIP";
          };
          clusterIP = lib.mkOption {
            type = types.nullOr types.str;
            default = null;
          };
          clusterIPs = lib.mkOption {
            type = types.listOf types.str;
            default = [ ];
          };
          loadBalancerIP = lib.mkOption {
            type = types.nullOr types.str;
            default = null;
          };
          loadBalancerClass = lib.mkOption {
            type = types.nullOr types.str;
            default = null;
          };
          externalIPs = lib.mkOption {
            type = types.listOf types.str;
            default = [ ];
          };
          externalTrafficPolicy = lib.mkOption {
            type = types.nullOr types.str;
            default = null;
          };
          ipFamilyPolicy = lib.mkOption {
            type = types.nullOr types.str;
            default = null;
          };
          trafficDistribution = lib.mkOption {
            type = types.str;
            default = "PreferClose";
          };
        };
      };
      default = {
        name = "";
        annotations = { };
        selector = { };
        serviceType = "ClusterIP";
        # Unset/optional Kubernetes Service fields mirrored from coredns.yaml:
        clusterIP = null;
        clusterIPs = [ ];
        loadBalancerIP = null;
        loadBalancerClass = null;
        externalIPs = [ ];
        externalTrafficPolicy = null;
        ipFamilyPolicy = null;
        trafficDistribution = "PreferClose";
      };
      description = "Kubernetes Service configuration for CoreDNS.";
    };

    serviceAccount = lib.mkOption {
      type = types.submodule {
        options = {
          create = lib.mkOption {
            type = types.bool;
            default = false;
          };
          name = lib.mkOption {
            type = types.str;
            default = "";
          };
          annotations = lib.mkOption {
            type = types.attrsOf types.str;
            default = { };
          };
        };
      };
      default = {
        create = false;
        name = "";
        annotations = { };
      };
      description = "ServiceAccount settings for CoreDNS pods.";
    };

    rbac = lib.mkOption {
      type = types.submodule {
        options = {
          create = lib.mkOption {
            type = types.bool;
            default = true;
          };
        };
      };
      default = {
        create = true;
      };
      description = "RBAC-related settings for CoreDNS (create roles/rolebindings).";
    };

    clusterRole = lib.mkOption {
      type = types.submodule {
        options = {
          nameOverride = lib.mkOption {
            type = types.str;
            default = "";
          };
        };
      };
      default = {
        nameOverride = "";
      };
      description = "ClusterRole naming overrides for CoreDNS-related RBAC objects.";
    };

    isClusterService = lib.mkOption {
      type = types.bool;
      default = true;
      description = "If true deploy as a cluster-service (labels/selectors compatible with cluster-level CoreDNS usage).";
    };

    customLabels = lib.mkOption {
      type = types.attrsOf types.anything;
      default = { };
      description = "Custom labels added to Deployment/Pod/ConfigMap/Service/ServiceMonitor (and autoscaler) resources.";
    };

    customAnnotations = lib.mkOption {
      type = types.attrsOf types.anything;
      default = { };
      description = "Custom annotations added to Deployment/Pod/ConfigMap/Service/ServiceMonitor (and autoscaler) resources.";
    };

    affinity = lib.mkOption {
      type = types.attrsOf types.anything;
      default = { };
      description = "Affinity settings for pod assignment";
    };

    topologySpreadConstraints = lib.mkOption {
      type = types.listOf (types.attrsOf types.anything);
      default = [ ];
    };
    tolerations = lib.mkOption {
      type = types.listOf (types.attrsOf types.anything);
      default = [ ];
    };
    initContainers = lib.mkOption {
      type = types.listOf (types.attrsOf types.anything);
      default = [ ];
    };
    nodeSelector = lib.mkOption {
      type = types.attrsOf types.anything;
      default = { };
    };

    env = lib.mkOption {
      type = types.listOf (types.attrsOf types.anything);
      default = [ ];
    };
    extraSecrets = lib.mkOption {
      type = types.listOf (types.attrsOf types.anything);
      default = [ ];
    };

    prometheus = lib.mkOption {
      type = types.submodule {
        options = {
          service = lib.mkOption {
            type = types.submodule {
              options = {
                enabled = lib.mkOption {
                  type = types.bool;
                  default = false;
                };
                annotations = lib.mkOption {
                  type = types.attrsOf types.str;
                  default = {
                    "prometheus.io/scrape" = "true";
                    "prometheus.io/port" = "9153";
                  };
                };
                selector = lib.mkOption {
                  type = types.attrsOf types.anything;
                  default = { };
                };
              };
            };
            default = {
              enabled = false;
              annotations = {
                "prometheus.io/scrape" = "true";
                "prometheus.io/port" = "9153";
              };
            };
          };

          monitor = lib.mkOption {
            type = types.submodule {
              options = {
                enabled = lib.mkOption {
                  type = types.bool;
                  default = false;
                };
                namespace = lib.mkOption {
                  type = types.str;
                  default = "";
                };
                additionalLabels = lib.mkOption {
                  type = types.attrsOf types.str;
                  default = { };
                };
                interval = lib.mkOption {
                  type = types.str;
                  default = "30s";
                };
                selector = lib.mkOption {
                  type = types.attrsOf types.str;
                  default = { };
                };
              };
            };
            default = {
              enabled = false;
            };
          };
        };
      };
      default = {
        enabled = false;
        serviceMonitor.enabled = false;
        serviceMonitor.namespace = "monitoring";
        serviceMonitor.additionalLabels = { };
      };
      description = "Prometheus monitoring configuration for CoreDNS.";
    };
  };

  coredns = config.services.coredns;

  chart = {
    name = "coredns";
    version = "1.10.0"; # should match the chart version
    release = {
      name = "idk";
      service = "idk";
      namespace = "default"; # TODO: use config.kubernetes.namespace
    };
  };

  # like in the define
  fullname = "${chart.release.name}-${chart.name}";

  labels = {
    "app.kubernetes.io/managed-by" = chart.release.service;
    "app.kubernetes.io/instance" = chart.release.name;
    "helm.sh/chart" = "${chart.name}-${chart.version}";
  }
  // lib.optionalAttrs coredns.isClusterService {
    "k8s-app" = lib.mkDefault (lib.strings.toLower (coredns.k8sAppLabelOverride or chart.name));
    "kubernetes.io/cluster-service" = "true";
    "kubernetes.io/name" = "CoreDNS";
  }
  // {
    "app.kubernetes.io/name" = chart.name;
  }
  // coredns.customLabels;

  labelsAutoscaler = {
    "app.kubernetes.io/managed-by" = chart.release.service;
    "app.kubernetes.io/instance" = chart.release.name;
    "helm.sh/chart" = "${chart.name}-${chart.version}";
  }
  // lib.optionalAttrs coredns.isClusterService {
    "k8s-app" = lib.strings.toLower (coredns.k8sAppLabelOverride or chart.name);
    "kubernetes.io/cluster-service" = "true";
    "kubernetes.io/name" = "CoreDNS";
  }
  // {
    "app.kubernetes.io/name" = "${chart.name}-autoscaler";
  }
  // coredns.customLabels;


  clusterRole = {
    apiVersion = "rbac.authorization.k8s.io/v1";
    kind = "ClusterRole";
    metadata = {
      name = "${fullname}";
      labels = labels;
      annotations = coredns.customAnnotations;
    };
    rules = [
      {
        apiGroups = [ "" ];
        resources = [
          "pods"
          "services"
          "endpoints"
          "namespaces"
        ];
        verbs = [
          "get"
          "list"
          "watch"
        ];
      }
      {
        apiGroups = [ "discovery.k8s.io" ];
        resources = [ "endpointslices" ];
        verbs = [
          "get"
          "list"
          "watch"
        ];
      }
    ]
    ++ lib.lists.optional coredns.rbac.pspEnable or false {
      apiGroups = [
        "policy"
        "extensions"
      ];
      resourceNames = [ "${fullname}" ];
      resources = [ "podsecuritypolicies" ];
      verbs = [ "use" ];
    };
  };
  clusterRoleDrv = pkgs.writeText "clusterole.json" (builtins.toJSON clusterRole);

  serviceAccountName = (coredns.serviceAccount.name or "${fullname}"); # TODO: lib.optionalString coredns.serviceAccount.create -> otherwise "default"

  #  serviceaccount.yaml

  serviceAccount = {
    apiVersion = "v1";
    kind = "ServiceAccount";
    metadata = {
      name = serviceAccountName;
      namespace = chart.release.namespace;
      inherit labels;
    }
    //
      lib.optionalAttrs
        (
          (coredns ? serviceAccount && coredns.serviceAccount ? annotations) || (coredns ? customAnnotations)
        )
        {
          annotations = (coredns.customAnnotations or { }) // (coredns.serviceAccount.annotations or { });
        };

    imagePullSecrets = lib.optional (coredns.image ? pullSecrets) coredns.image.pullSecrets;
  };
  serviceAccountDrv = pkgs.writeText "serviceaccount.json" (builtins.toJSON serviceAccount);

  clusterRoleBinding = {
    apiVersion = "rbac.authorization.k8s.io/v1";
    kind = "ClusterRoleBinding";
    metadata = {
      name = fullname;
      labels = labels;
      annotations = coredns.customAnnotations // {
        "nix.kix.dev/clusterrole-dependency" = "${clusterRoleDrv}";
        "nix.kix.dev/serviceaccount-dependency" = "${serviceAccountDrv}";
      };
    };
    roleRef = {
      apiGroup = "rbac.authorization.k8s.io";
      kind = "ClusterRole";
      name = fullname;
    };
    subjects = [
      {
        kind = "ServiceAccount";
        name = "${serviceAccountName}";
        namespace = chart.release.namespace;
      }
    ];
  };

  clusterRoleBindingDrv = pkgs.writeText "clusterrole.json" (builtins.toJSON clusterRoleBinding);

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

  corefileString =
    renderExtraConfig (coredns.extraConfig or { })
    + "\n"
    + concatStringsSep "\n" (map renderServer (coredns.servers or [ ]));

  configMap = {
    apiVersion = "v1";
    kind = "ConfigMap";
    metadata = {
      name = fullname;
      namespace = chart.release.namespace;
      labels = labels;
      annotations = coredns.customAnnotations;
    };
    data = {
      "Corefile" = corefileString;
    }
    // lib.optionalAttrs (coredns.zoneFiles != [ ]) (
      map (z: {
        "${z.filename}" = z.contents;
      }) coredns.zoneFiles
    );
  };

  configMapDrv = pkgs.writeText "configmap.json" (builtins.toJSON configMap);

  # TODO: app.kubernetes.io/version: {{ .coredns.image.tag | default .Chart.AppVersion | replace ":" "-" | replace "@" "_" | trunc 63 | trimSuffix "-" | quote }}
  imageTag = if coredns.image.tag == "" then chart.version else coredns.image.tag;

  servers = coredns.servers or [ ];

  # classify a scheme into udp/tcp flags
  classify =
    scheme:
    if scheme == "dns://" || scheme == "" then
      {
        isudp = true;
        istcp = false;
      }
    else if scheme == "tls://" || scheme == "grpc://" || scheme == "https://" then
      {
        isudp = false;
        istcp = true;
      }
    else
      {
        isudp = false;
        istcp = false;
      };

  ####################################
  # Service ports map construction
  ####################################
  buildServiceMap = builtins.foldl' (
    m: srv:
    let
      portKey = toString (srv.port);
      existing =
        m."${portKey}" or {
          isudp = false;
          istcp = false;
          serviceport = (if srv ? servicePort then srv.servicePort else srv.port);
        };

      afterZones = builtins.foldl' (
        inner: z:
        let
          s = if z ? scheme then z.scheme else "";
          cls = classify s;
          inner1 = inner // (if cls.isudp then { isudp = true; } else { });
          inner2 = inner1 // (if cls.istcp then { istcp = true; } else { });
          inner3 = if (z ? use_tcp) && z.use_tcp then inner2 // { istcp = true; } else inner2;
        in
        inner3
      ) existing (srv.zones or [ ]);

      afterDefault =
        if (!afterZones.isudp && !afterZones.istcp) then afterZones // { isudp = true; } else afterZones;
      afterNode = if srv ? nodePort then afterDefault // { nodePort = srv.nodePort; } else afterDefault;
    in
    m // { "${portKey}" = afterNode; }
  ) { } servers;

  renderServicePorts =
    let
      ports = buildServiceMap;
      keys = builtins.attrNames ports;
    in
    builtins.concatLists (
      map (
        k:
        let
          p = ports."${k}";
          make =
            proto:
            let
              base = {
                port = p.serviceport;
                protocol = proto;
                name = (if proto == "UDP" then "udp-" else "tcp-") + k;
                targetPort = k; # string to avoid parsing issues
              };
            in
            if p ? nodePort then base // { nodePort = p.nodePort; } else base;
        in
        (if p.isudp then [ (make "UDP") ] else [ ]) ++ (if p.istcp then [ (make "TCP") ] else [ ])
      ) keys
    );

  ####################################
  # Container ports map construction
  ####################################
  buildContainerMap = builtins.foldl' (
    m: srv:
    let
      portKey = toString (srv.port);
      existing =
        m."${portKey}" or {
          isudp = false;
          istcp = false;
        };
      afterZones = builtins.foldl' (
        inner: z:
        let
          s = if z ? scheme then z.scheme else "";
          cls = classify s;
          inner1 = inner // (if cls.isudp then { isudp = true; } else { });
          inner2 = inner1 // (if cls.istcp then { istcp = true; } else { });
          inner3 = if (z ? use_tcp) && z.use_tcp then inner2 // { istcp = true; } else inner2;
        in
        inner3
      ) existing (srv.zones or [ ]);

      afterDefault =
        if (!afterZones.isudp && !afterZones.istcp) then afterZones // { isudp = true; } else afterZones;
      afterHost = if srv ? hostPort then afterDefault // { hostPort = srv.hostPort; } else afterDefault;

      withSrv = m // {
        "${portKey}" = afterHost;
      };

      # handle prometheus plugin(s) — add/overwrite prometheus port as tcp-only
      withProm = builtins.foldl' (
        acc: pl:
        if pl.name == "prometheus" then
          let
            parts = lib.splitString ":" (toString (pl.parameters or ""));
            pport = if builtins.length parts > 1 then builtins.elemAt parts 1 else null;
          in
          if pport == null then
            acc
          else
            acc
            // {
              "${pport}" = {
                isudp = false;
                istcp = true;
              };
            }
        else
          acc
      ) withSrv (srv.plugins or [ ]);
    in
    withProm
  ) { } servers;

  renderContainerPorts =
    let
      ports = buildContainerMap;
      keys = builtins.attrNames ports;
    in
    builtins.concatLists (
      map (
        k:
        let
          p = ports."${k}";
          make =
            proto:
            let
              base = {
                containerPort = k;
                protocol = proto;
                name = (if proto == "UDP" then "udp-" else "tcp-") + k;
              };
            in
            if p ? hostPort then base // { hostPort = p.hostPort; } else base;
        in
        (if p.isudp then [ (make "UDP") ] else [ ]) ++ (if p.istcp then [ (make "TCP") ] else [ ])
      ) keys
    );

  deployment = {
    apiVersion = "apps/v1";
    kind = "Deployment";
    metadata = {
      name = (coredns.deployment.name or fullname);
      namespace = chart.release.namespace;
      labels = labels // {
        "app.kubernetes.io/version" = imageTag;
      };
      annotations = (coredns.customAnnotations // coredns.deployment.annotations);
    };

    spec =
      lib.optionalAttrs ((!coredns.autoscaler.enabled) && (!coredns.hpa.enabled)) {
        replicas = coredns.replicaCount;
      }
      // {
        strategy = {
          type = "RollingUpdate";
          rollingUpdate = {
            maxUnavailable = coredns.rollingUpdate.maxUnavailable;
            maxSurge = coredns.rollingUpdate.maxSurge;
          };
        };

        selector = (
          if coredns.deployment.selector != { } then
            coredns.deployment.selector
          else
            {
              matchLabels = {
                "app.kubernetes.io/instance" = chart.release.name;
                "app.kubernetes.io/name" = chart.name;
              }
              // lib.optionalAttrs coredns.isClusterService {
                "k8s-app" = coredns.k8sAppLabelOverride or chart.name;
              };
            }
        );

        template = {
          metadata = {
            labels =
              lib.optionalAttrs coredns.isClusterService {
                "k8s-app" = coredns.k8sAppLabelOverride or chart.name;
              }
              // {
                "app.kubernetes.io/name" = chart.name;
                "app.kubernetes.io/instance" = chart.release.name;
              }
              // coredns.customLabels;
            annotations = {
              "checksum/config" = "${configMapDrv}";
              "nix.kix.dev/configmap-dependency" = "${configMapDrv}";
            }
            // lib.optionalAttrs coredns.isClusterService {
              "scheduler.alpha.kubernetes.io/tolerations" = builtins.toJSON [
                {
                  key = "CriticalAddonsOnly";
                  operator = "Exists";
                }
              ];
            }
            // coredns.podAnnotations;
          };

          spec =
            lib.optionalAttrs (coredns.podSecurityContext != { }) {
              securityContext = coredns.podSecurityContext;
            }
            // lib.optionalAttrs (coredns.terminationGracePeriodSeconds != null) {
              terminationGracePeriodSeconds = coredns.terminationGracePeriodSeconds;
            }
            // {
              serviceAccountName = serviceAccountName;
            }
            // lib.optionalAttrs (coredns.priorityClassName != null) {
              priorityClassName = coredns.priorityClassName;
            }
            // lib.optionalAttrs (coredns.isClusterService) {
              dnsPolicy = "Default";
            }
            // lib.optionalAttrs (coredns.affinity != null) {
              affinity = coredns.affinity;
            }
            // lib.optionalAttrs (coredns.topologySpreadConstraints != null) {
              topologySpreadConstraints = coredns.topologySpreadConstraints;
            }
            // lib.optionalAttrs (coredns.tolerations != null) {
              tolerations = coredns.tolerations;
            }
            // lib.optionalAttrs (coredns.nodeSelector != null) {
              nodeSelector = coredns.nodeSelector;
            }
            // lib.optionalAttrs (coredns.image.pullSecrets != null) {
              imagePullSecrets = coredns.image.pullSecrets;
            }
            // lib.optionalAttrs (coredns.initContainers != null) {
              initContainers = coredns.initContainers;
            }
            // {
              containers = [
                (
                  {
                    name = "coredns";
                    image = "${coredns.image.repository}:${
                      if coredns.image.tag != "" then coredns.image.tag else imageTag
                    }";
                    imagePullPolicy = coredns.image.pullPolicy;
                    args = [
                      "-conf"
                      "/etc/coredns/Corefile"
                    ];
                    volumeMounts = (
                      [
                        {
                          name = "config-volume";
                          mountPath = "/etc/coredns";
                        }
                      ]
                      ++ (map (s: {
                        name = s.name;
                        mountPath = s.mountPath;
                        readOnly = true;
                      }) coredns.extraSecrets)
                      ++ (coredns.extra.extraVolumeMounts or [ ])
                    );
                    env = coredns.env;
                    resources = coredns.resources;
                    ports = renderContainerPorts;
                  }
                  // lib.optionalAttrs coredns.livenessProbe.enabled {
                    livenessProbe = {
                      httpGet = {
                        path = "/health";
                        port = 8080;
                        scheme = "HTTP";
                      };
                      initialDelaySeconds = coredns.livenessProbe.initialDelaySeconds;
                      periodSeconds = coredns.livenessProbe.periodSeconds;
                      timeoutSeconds = coredns.livenessProbe.timeoutSeconds;
                      successThreshold = coredns.livenessProbe.successThreshold;
                      failureThreshold = coredns.livenessProbe.failureThreshold;
                    };
                  }
                  // lib.optionalAttrs coredns.readinessProbe.enabled {
                    readinessProbe = {
                      httpGet = {
                        path = "/ready";
                        port = 8181;
                        scheme = "HTTP";
                      };
                      initialDelaySeconds = coredns.readinessProbe.initialDelaySeconds;
                      periodSeconds = coredns.readinessProbe.periodSeconds;
                      timeoutSeconds = coredns.readinessProbe.timeoutSeconds;
                      successThreshold = coredns.readinessProbe.successThreshold;
                      failureThreshold = coredns.readinessProbe.failureThreshold;
                    };
                  }
                  // lib.optionalAttrs (coredns.securityContext != { }) {
                    securityContext = coredns.securityContext;
                  }
                )
              ]
              ++ (coredns.extraContainers or [ ]);
            };

          volumes = [
            {
              name = "config-volume";
              configMap = {
                name = fullname;
                items = [
                  {
                    key = "Corefile";
                    path = "Corefile";
                  }
                ]
                ++ (map (z: {
                  key = z.filename;
                  path = z.filename;
                }) coredns.zoneFiles);
              };
            }
          ]
          ++ (map (s: {
            name = s.name;
            secret = {
              secretName = s.name;
              defaultMode = s.defaultMode or 400;
            };
          }) coredns.extraSecrets)
          ++ (coredns.extra.extraVolumes or [ ])
          ++ (coredns.deployment.extraVolumes or [ ]);
        };
      };
  };

  deploymentDrv = pkgs.writeText "deployment.json" (builtins.toJSON deployment);

  #  hpa.yaml

  Capabilities = {
    "APIVersions" = [
      "autoscaling/v2"
      "autoscaling/v2beta2"
    ];
  };

  apiVersion =
    if lib.elem "autoscaling/v2" (Capabilities.APIVersions or [ ]) then
      "autoscaling/v2"
    else
      "autoscaling/v2beta2";

  hpa = {
    apiVersion = apiVersion;
    kind = "HorizontalPodAutoscaler";
    metadata = {
      name = (coredns.deployment.name or coredns.fullname or "coredns"); # helm: default (include "coredns.fullname" .)
      namespace = chart.release.namespace;
      labels = (coredns.labels or { }); # helm: include "coredns.labels"
    }
    // (coredns.customLabels or { })
    // (
      if coredns ? customAnnotations && coredns.customAnnotations != { } then
        { annotations = coredns.customAnnotations; }
      else
        { }
    );

    spec = {
      scaleTargetRef = {
        apiVersion = "apps/v1";
        kind = "Deployment";
        name = (coredns.deployment.name or coredns.fullname or "coredns");
      };
      minReplicas = coredns.hpa.minReplicas;
      maxReplicas = coredns.hpa.maxReplicas;
      metrics = coredns.hpa.metrics;
    }
    // (if coredns.hpa ? behavior then { behavior = coredns.hpa.behavior; } else { });
  };

  hpaDrv = pkgs.writeText "hpa.json" (builtins.toJSON hpa);

  #  poddisruptionbudget.yaml

  # TODO: dependencies
  podDisruptionBudget = {
    apiVersion = "policy/v1";
    kind = "PodDisruptionBudget";
    metadata = {
      # You can decide how to generate fullname; here just use release name + chart name
      name = "${chart.release.name}-coredns";
      namespace = chart.release.namespace;

      labels = (coredns.labels or { }) // (coredns.customLabels or { });

      annotations = coredns.customAnnotations or { };
    };

    spec =
      let
        baseSelector =
          if coredns.podDisruptionBudget ? selector then
            { }
          else
            {
              selector.matchLabels = {
                "app.kubernetes.io/instance" = chart.release.name;
                "app.kubernetes.io/name" = "coredns";
              }
              // lib.optionalAttrs (coredns.isClusterService or false) {
                "k8s-app" = "kube-dns";
              };
            };
      in
      baseSelector // coredns.podDisruptionBudget;
  };

  podDisruptionBudgetDrv = pkgs.writeText "poddisruptionbudget.json" (
    builtins.toJSON podDisruptionBudget
  );

  #  service-metrics.yaml

  serviceMetrics = {
    apiVersion = "v1";
    kind = "Service";
    metadata = {
      name = "${coredns.name or "coredns"}-metrics"; # would use fullname template in Helm
      namespace = chart.release.namespace;
      labels =
        (coredns.labels or { })
        // {
          "app.kubernetes.io/component" = "metrics";
        }
        // (coredns.customLabels or { });
      annotations =
        (coredns.prometheus.service.annotations or { })
        // (coredns.service.annotations or { })
        // (coredns.customAnnotations or { });
    };
    spec = {
      selector =
        if (coredns.prometheus.service.selector or null) != null then
          coredns.prometheus.service.selector
        else
          {
            "app.kubernetes.io/instance" = chart.release.name;
            "app.kubernetes.io/name" = chart.name or coredns.name or "coredns";
          }
          // (lib.optionalAttrs (coredns.isClusterService or false) {
            "k8s-app" = coredns.k8sAppLabelOverride or "coredns";
          });

      ports = [
        {
          name = "metrics";
          port = 9153;
          targetPort = 9153;
        }
      ];
    };
  };
  serviceMetricsDrv = pkgs.writeText "service-metrics.json" (builtins.toJSON serviceMetrics);

  #  service.yaml

  svcName = coredns.service.name or "coredns";
  annotations = (coredns.service.annotations or { }) // (coredns.customAnnotations or { });
  selector =
    if coredns.service.selector or null != null then
      coredns.service.selector
    else
      {
        "app.kubernetes.io/instance" = chart.release.name;
        "app.kubernetes.io/name" = "coredns";
      }
      // lib.optionalAttrs (coredns.isClusterService or false) {
        k8s-app = coredns.k8sAppLabelOverride or "coredns";
      };
  service = {
    apiVersion = "v1";
    kind = "Service";
    metadata = {
      name = svcName;
      namespace = chart.release.namespace;
      inherit labels annotations;
    };
    spec = {
      inherit selector;
      type = coredns.serviceType or "ClusterIP";
      ports = renderServicePorts;
    }
    // lib.optionalAttrs (coredns.service.clusterIP or null != null) {
      clusterIP = coredns.service.clusterIP;
    }
    // lib.optionalAttrs (coredns.service.clusterIPs or null != null) {
      clusterIPs = coredns.service.clusterIPs;
    }
    // lib.optionalAttrs (coredns.service.externalIPs or null != null) {
      externalIPs = coredns.service.externalIPs;
    }
    // lib.optionalAttrs (coredns.service.externalTrafficPolicy or null != null) {
      externalTrafficPolicy = coredns.service.externalTrafficPolicy;
    }
    // lib.optionalAttrs (coredns.service.loadBalancerIP or null != null) {
      loadBalancerIP = coredns.service.loadBalancerIP;
    }
    // lib.optionalAttrs (coredns.service.loadBalancerClass or null != null) {
      loadBalancerClass = coredns.service.loadBalancerClass;
    }
    // lib.optionalAttrs (coredns.service.ipFamilyPolicy or null != null) {
      ipFamilyPolicy = coredns.service.ipFamilyPolicy;
    }
    // lib.optionalAttrs (coredns.service.trafficDistribution or null != null) {
      trafficDistribution = coredns.service.trafficDistribution;
    };
  };

  serviceDrv = pkgs.writeText "service.json" (builtins.toJSON service);

  #  servicemonitor.yaml

  serviceMonitor = {
    apiVersion = "monitoring.coreos.com/v1";
    kind = "ServiceMonitor";

    metadata = {
      name = fullname;
      labels = labels // (coredns.prometheus.monitor.additionalLabels or { });
    }
    // lib.optionalAttrs (coredns.prometheus.monitor ? namespace) {
      namespace = coredns.prometheus.monitor.namespace;
    }
    // lib.optionalAttrs (coredns ? customAnnotations) {
      annotations = coredns.customAnnotations;
    };

    spec =
      { }
      //
        lib.optionalAttrs
          ((coredns.prometheus.monitor.namespace or chart.release.namespace) != chart.release.namespace)
          {
            namespaceSelector.matchNames = [ chart.release.namespace ];
          }
      // {
        selector =
          if coredns.prometheus.monitor ? selector then
            coredns.prometheus.monitor.selector
          else
            {
              matchLabels = {
                "app.kubernetes.io/instance" = chart.release.name;
                "app.kubernetes.io/name" = chart.name;
                "app.kubernetes.io/component" = "metrics";
              }
              // lib.optionalAttrs (coredns.isClusterService or false) {
                k8s-app = "kube-dns"; # like template "coredns.k8sapplabel"
              };
            };

        endpoints = [
          (
            {
              port = "metrics";
            }
            // lib.optionalAttrs (coredns.prometheus.monitor ? interval) {
              interval = coredns.prometheus.monitor.interval;
            }
          )
        ];
      };
  };
  serviceMonitorDrv = pkgs.writeText "servicemonitor.json" (builtins.toJSON serviceMonitor);

in
{
  # Export the options for module system integration
  inherit imports options;

  # Export manifests only if the service is enabled
  config = {
    services.coredns.applicationName = fullname;
    services.coredns.namespace = chart.release.namespace;
    manifests =
        lib.optionalAttrs
          (!config.services.coredns.autoscaler.enabled && config.services.coredns.hpa.enabled)
          {
            "hpa.json" = hpaDrv;
          }
      // lib.optionalAttrs (config.services.coredns.deployment.enabled) {
        "deployment.json" = deploymentDrv;
        "service.json" = serviceDrv;
      }
      //
        lib.optionalAttrs
          (config.services.coredns.deployment.enabled && config.services.coredns.rbac.create)
          {
            "clusterrole.json" = clusterRoleBindingDrv;
          }
      //
        lib.optionalAttrs
          (config.services.coredns.deployment.enabled && !config.services.coredns.deployment.skipConfig)
          {
            "configmap.json" = configMapDrv;
          }
      //
        lib.optionalAttrs
          (
            config.services.coredns.deployment.enabled && (config.services.coredns.podDisruptionBudget != null)
          )
          {
            "poddisruptionbudget.json" = podDisruptionBudgetDrv;
          }
      //
        lib.optionalAttrs
          (config.services.coredns.deployment.enabled && config.services.coredns.prometheus.service.enabled)
          {
            "servicemetrics.json" = serviceMetricsDrv;
          }

      //
        lib.optionalAttrs
          (config.services.coredns.deployment.enabled && config.services.coredns.prometheus.monitor.enabled)
          {
            "servicemonitor.json" = serviceMonitorDrv;
          };
  };
}
