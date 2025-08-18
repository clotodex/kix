{
  lib,
  pkgs,
  config,
  ...
}:

let
  types = lib.types;

  options.services.coredns = {
    autoscaler = lib.mkOption {
      type = types.attrs;
      default = {
        enabled = false;
      };
      apply =
        userValue:
        lib.mkMerge [
          {
            enabled = false;
            coresPerReplica = 256;
            nodesPerReplica = 16;
            min = 0;
            max = 0;
            includeUnschedulableNodes = false;
            preventSinglePointFailure = true;
            podAnnotations = { };
            customFlags = [ ]; # list of strings like "--nodelabels=..."
            image = {
              repository = "registry.k8s.io/cpa/cluster-proportional-autoscaler";
              tag = "v1.9.0";
              pullPolicy = "IfNotPresent";
              pullSecrets = [ ];
            };
            priorityClassName = "";
            affinity = { };
            nodeSelector = { };
            tolerations = [ ];
            resources = {
              requests = {
                cpu = "20m";
                memory = "10Mi";
              };
              limits = {
                cpu = "20m";
                memory = "10Mi";
              };
            };
            configmap = {
              annotations = { };
            };
            livenessProbe = {
              enabled = true;
              initialDelaySeconds = 10;
              periodSeconds = 5;
              timeoutSeconds = 5;
              failureThreshold = 3;
              successThreshold = 1;
            };
            extraContainers = [ ];
          }
          userValue
        ];
      description = "Cluster-proportional-autoscaler (CPA) configuration for CoreDNS deployment.";
    };
    deployment = lib.mkOption {
      type = types.attrs;
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
        podDisruptionBudget = { };
        extraContainers = [ ];
        extraVolumes = [ ];
        extraVolumeMounts = [ ];
        extraSecrets = [ ];
        env = [ ];
      };
      description = "Deployment-level configuration for CoreDNS (pods, selectors, topologySpreadConstraints, extra volumes, env, etc).";
    };

    hpa = lib.mkOption {
      type = types.attrs;
      default = {
        enabled = false;
        minReplicas = 1;
        maxReplicas = 2;
        metrics = [ ];
      };
      description = "Optional Horizontal Pod Autoscaler (HPA) configuration for CoreDNS.";
    };
    extra = lib.mkOption {
      type = types.attrs;
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
      type = types.attrs;
      default = {
        repository = "coredns/coredns";
        tag = ""; # defaults to chart appVersion in helm
        pullPolicy = "IfNotPresent";
        pullSecrets = [ ]; # list of { name = "..." } or string names
      };
      description = "Container image configuration for CoreDNS.";
    };
    livenessProbe = lib.mkOption {
      type = types.attrs;
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
      type = types.attrs;
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
      type = types.attrs;
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
      type = types.attrs;
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
      type = types.attrs;
      default = { };
      description = "Pod-level securityContext for CoreDNS pods.";
    };

    securityContext = lib.mkOption {
      type = types.attrs;
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
      type = types.attrs;
      default = { };
      description = "Annotations applied to CoreDNS pods.";
    };
    servers = lib.mkOption {
      type = types.listOf types.attrs;
      default = [
        {
          zones = [
            {
              zone = ".";
              use_tcp = true;
            }
          ];
          port = 53;
          # servicePort / nodePort / hostPort can be null/unset
          servicePort = null;
          nodePort = null;
          hostPort = null;
          plugins = [
            { name = "errors"; }
            {
              name = "health";
              configBlock = ''lameduck 10s'';
            }
            { name = "ready"; }
            {
              name = "kubernetes";
              parameters = [
                "cluster.local"
                "in-addr.arpa"
                "ip6.arpa"
              ];
              configBlock = ''pods insecure\nfallthrough in-addr.arpa ip6.arpa\nttl 30'';
            }
            {
              name = "prometheus";
              parameters = [ "0.0.0.0:9153" ];
            }
            {
              name = "forward";
              parameters = [
                "."
                "/etc/resolv.conf"
              ];
            }
            {
              name = "cache";
              parameters = [ 30 ];
            }
            { name = "loop"; }
            { name = "reload"; }
            { name = "loadbalance"; }
          ];
        }
      ];
      description = "List of server blocks (CoreDNS servers). Each item is an attribute set describing zones, port and plugins.";
    };

    extraConfig = lib.mkOption {
      type = types.attrs;
      default = { };
      description = "Additional CoreDNS configuration applied outside the default zone block (e.g. import parameters).";
    };

    zoneFiles = lib.mkOption {
      type = types.listOf types.attrs;
      default = [ ];
      description = "Custom zone files to configure CoreDNS. Entries should be { filename, domain, contents }.";
    };
    service = lib.mkOption {
      type = types.attrs;
      default = {
        name = "";
        annotations = { };
        selector = { };
        serviceType = "ClusterIP";
        # Unset/optional Kubernetes Service fields mirrored from values.yaml:
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
      type = types.attrs;
      default = {
        create = false;
        name = "";
        annotations = { };
      };
      description = "ServiceAccount settings for CoreDNS pods.";
    };

    rbac = lib.mkOption {
      type = types.attrs;
      default = {
        create = true;
      };
      description = "RBAC-related settings for CoreDNS (create roles/rolebindings).";
    };

    clusterRole = lib.mkOption {
      type = types.attrs;
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
      type = types.attrs;
      default = { };
      description = "Custom labels added to Deployment/Pod/ConfigMap/Service/ServiceMonitor (and autoscaler) resources.";
    };

    customAnnotations = lib.mkOption {
      type = types.attrs;
      default = { };
      description = "Custom annotations added to Deployment/Pod/ConfigMap/Service/ServiceMonitor (and autoscaler) resources.";
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
  name = chart.name;
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

  clusterroleAutoscaler = {
    apiVersion = "rbac.authorization.k8s.io/v1";
    kind = "ClusterRole";
    metadata = {
      name = "${fullname}-autoscaler";
      labels = labelsAutoscaler;
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

  clusterRoleAutoScalerBinding = {
    apiVersion = "rbac.authorization.k8s.io/v1";
    kind = "ClusterRoleBinding";
    metadata = {
      name = "${fullname}-autoscaler";
      labels = labelsAutoscaler;
      annotations = coredns.customAnnotations // {
        "nix.kix.dev/configmap-dependency" = "${clusterRoleAutoScalerDrv}";
      };
    };
    roleRef = {
      apiGroup = "rbac.authorization.k8s.io";
      kind = "ClusterRole";
      name = "${fullname}-autoscaler";
    };
    subjects = [
      {
        kind = "ServiceAccount";
        name = "${fullname}-autoscaler";
        namespace = chart.release.name;
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
      name = "${fullname}-autoscaler";
      namespace = chart.release.namespace;
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
      name = "${fullname}-autoscaler";
      namespace = chart.release.namespace;
      labels = labelsAutoscaler;
      annotations = coredns.customAnnotations;
    };
    spec = {
      replicas = 1; # TODO: make configurable
      selector = {
        matchLabels = {
          "app.kubernetes.io/instance" = chart.release.name;
          "app.kubernetes.io/name" = "${chart.name}-autoscaler"; # FIXME: not fully following chart
        }
        // lib.optionalAttrs coredns.isClusterService {
          "k8s-app" = lib.mkDefault (lib.strings.toLower (coredns.k8sAppLabelOverride or chart.name));
        };
      };
      template = {
        metadata = {
          labels =
            lib.optionalAttrs coredns.isClusterService {
              "k8s-app" = lib.mkDefault (lib.strings.toLower (coredns.k8sAppLabelOverride or chart.name));
            }
            // {
              "app.kubernetes.io/name" = "${chart.name}-autoscaler";
              "app.kubernetes.io/instance" = chart.release.name;
            }
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
          serviceAccountName = "${fullname}-autoscaler"; # TODO: think about how to make this reference more effective
        }
        // lib.optionalAttrs (coredns.autoscaler.priorityClassName != "") {
          priorityClassName = coredns.autoscaler.priorityClassName;
        }
        // lib.optionalAttrs (coredns.autoscaler.affinity != { }) {
          affinity = coredns.autoscaler.affinity;
        }
        // lib.optionalAttrs (coredns.autoscaler.tolerations != [ ]) {
          tolerations = coredns.autoscaler.tolerations;
        }
        // lib.optionalAttrs (coredns.autoscaler.nodeSelector != { }) {
          nodeSelector = coredns.autoscaler.nodeSelector;
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
                  "--namespace=${chart.release.namespace}"
                  "--configmap=${fullname}-autoscaler"
                  "--target=Deployment/${coredns.deployment.name or fullname}"
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
          ++ coredns.autoscaler.extraContainers
          ++ lib.lists.optional (coredns.autoscaler.affinity != { }) {
            affinity = coredns.autoscaler.affinity;
          }
          ++ lib.lists.optional (coredns.autoscaler.tolerations != [ ]) {
            tolerations = coredns.autoscaler.tolerations;
          }
          ++ lib.lists.optional (coredns.autoscaler.nodeSelector != { }) {
            nodeSelector = coredns.autoscaler.nodeSelector;
          }
          ++ lib.lists.optional (coredns.autoscaler.image.pullSecrets != [ ]) {
            imagePullSecrets = coredns.autoscaler.image.pullSecrets;
          };
        };
      };
    };
  };

  deploymentAutoscalerDrv = pkgs.writeText "deployment-autoscaler.json" (
    builtins.toJSON deploymentAutoscaler
  );

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

  clusterRoleBinding = {
    apiVersion = "rbac.authorization.k8s.io/v1";
    kind = "ClusterRoleBinding";
    metadata = {
      name = fullname;
      labels = labels;
      annotations = coredns.customAnnotations // {
        "nix.kix.dev/configmap-dependency" = "${clusterRoleDrv}";
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

  # TODO: app.kubernetes.io/version: {{ .Values.image.tag | default .Chart.AppVersion | replace ":" "-" | replace "@" "_" | trunc 63 | trimSuffix "-" | quote }}
  imageTag = if coredns.image.tag == "" then chart.version else coredns.image.tag;

  servers = coredns.servers or [];

  # classify a scheme into udp/tcp flags
  classify = scheme:
    if scheme == "dns://" || scheme == "" then { isudp = true; istcp = false; }
    else if scheme == "tls://" || scheme == "grpc://" || scheme == "https://" then { isudp = false; istcp = true; }
    else { isudp = false; istcp = false; };

  ####################################
  # Service ports map construction
  ####################################
  buildServiceMap = builtins.foldl' (m: srv:
    let
      portKey = toString (srv.port);
      existing = m."${portKey}" or {
        isudp = false; istcp = false;
        serviceport = (if srv ? servicePort then srv.servicePort else srv.port);
      };

      afterZones = builtins.foldl' (inner: z:
        let
          s = if z ? scheme then z.scheme else "";
          cls = classify s;
          inner1 = inner // (if cls.isudp then { isudp = true; } else {});
          inner2 = inner1 // (if cls.istcp then { istcp = true; } else {});
          inner3 = if (z ? use_tcp) && z.use_tcp then inner2 // { istcp = true; } else inner2;
        in inner3
      ) existing (srv.zones or []);

      afterDefault = if (!afterZones.isudp && !afterZones.istcp) then afterZones // { isudp = true; } else afterZones;
      afterNode = if srv ? nodePort then afterDefault // { nodePort = srv.nodePort; } else afterDefault;
    in
      m // { "${portKey}" = afterNode; }
  ) {} servers;

  renderServicePorts =
    let ports = buildServiceMap; keys = builtins.attrNames ports;
    in builtins.concatLists (map (k:
      let p = ports."${k}";
          make = proto:
            let base = {
              port = p.serviceport;
              protocol = proto;
              name = (if proto == "UDP" then "udp-" else "tcp-") + k;
              targetPort = k; # string to avoid parsing issues
            };
            in if p ? nodePort then base // { nodePort = p.nodePort; } else base;
      in (if p.isudp then [ (make "UDP") ] else []) ++ (if p.istcp then [ (make "TCP") ] else [])
    ) keys);

  ####################################
  # Container ports map construction
  ####################################
  buildContainerMap = builtins.foldl' (m: srv:
    let
      portKey = toString (srv.port);
      existing = m."${portKey}" or { isudp = false; istcp = false; };
      afterZones = builtins.foldl' (inner: z:
        let
          s = if z ? scheme then z.scheme else "";
          cls = classify s;
          inner1 = inner // (if cls.isudp then { isudp = true; } else {});
          inner2 = inner1 // (if cls.istcp then { istcp = true; } else {});
          inner3 = if (z ? use_tcp) && z.use_tcp then inner2 // { istcp = true; } else inner2;
        in inner3
      ) existing (srv.zones or []);

      afterDefault = if (!afterZones.isudp && !afterZones.istcp) then afterZones // { isudp = true; } else afterZones;
      afterHost = if srv ? hostPort then afterDefault // { hostPort = srv.hostPort; } else afterDefault;

      withSrv = m // { "${portKey}" = afterHost; };

      # handle prometheus plugin(s) — add/overwrite prometheus port as tcp-only
      withProm = builtins.foldl' (acc: pl:
        if pl.name == "prometheus" then
          let
            parts = lib.splitString ":" (toString (pl.parameters or ""));
            pport = if builtins.length parts > 1 then builtins.elemAt parts 1 else null;
          in if pport == null then acc else acc // { "${pport}" = { isudp = false; istcp = true; }; }
        else acc
      ) withSrv (srv.plugins or []);
    in
      withProm
  ) {} servers;

  renderContainerPorts =
    let ports = buildContainerMap; keys = builtins.attrNames ports;
    in builtins.concatLists (map (k:
      let p = ports."${k}";
          make = proto:
            let base = {
              containerPort = k;
              protocol = proto;
              name = (if proto == "UDP" then "udp-" else "tcp-") + k;
            };
            in if p ? hostPort then base // { hostPort = p.hostPort; } else base;
      in (if p.isudp then [ (make "UDP") ] else []) ++ (if p.istcp then [ (make "TCP") ] else [])
    ) keys);

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
in
{
  # Export the options for module system integration
  inherit options;

  # Export manifests only if the service is enabled
  manifests =
    lib.optionalAttrs (coredns.autoscaler.enabled && !coredns.hpa.enabled) {
      "deployment-autoscaler.json" = deploymentAutoscalerDrv;
    }
    // lib.optionalAttrs (coredns.deployment.enabled) {
      "deployment.json" = deploymentDrv;
    }
    // lib.optionalAttrs (coredns.deployment.enabled && coredns.rbac.create) {
      "clusterrole.json" = clusterRoleBindingDrv;
    }
    // lib.optionalAttrs (coredns.deployment.enabled && !coredns.deployment.skipConfig) {
      "configmap.json" = configMapDrv;
    };
}
