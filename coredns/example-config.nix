{
  services = {
    nginx.enable = false;
    coredns = {
      enable = true;
      image = {
        repository = "coredns/coredns";
        tag = "";
        pullPolicy = "IfNotPresent";
        pullSecrets = [ ];
      };

      replicaCount = 1;

      resources = {
        limits = {
          cpu = "100m";
          memory = "128Mi";
        };
        requests = {
          cpu = "100m";
          memory = "128Mi";
        };
      };

      rollingUpdate = {
        maxUnavailable = 1;
        maxSurge = "25%";
      };

      terminationGracePeriodSeconds = 30;

      podAnnotations = { };

      serviceType = "ClusterIP";

      prometheus = {
        service = {
          enabled = false;
          annotations = {
            "prometheus.io/scrape" = "true";
            "prometheus.io/port" = "9153";
          };
          selector = { };
        };
        monitor = {
          enabled = false;
          additionalLabels = { };
          namespace = "";
          interval = "";
          selector = { };
        };
      };

      service = {
        name = "";
        annotations = { };
        selector = { };
      };

      serviceAccount = {
        create = false;
        name = "";
        annotations = { };
      };

      rbac = {
        create = true;
      };

      clusterRole = {
        nameOverride = "";
      };

      isClusterService = true;

      priorityClassName = "";

      podSecurityContext = { };

      securityContext = {
        allowPrivilegeEscalation = false;
        capabilities = {
          add = [ "NET_BIND_SERVICE" ];
          drop = [ "ALL" ];
        };
        readOnlyRootFilesystem = true;
      };

      servers = [
        {
          zones = [
            {
              zone = ".";
              use_tcp = true;
            }
          ];
          port = 53;
          plugins = [
            { name = "errors"; }
            {
              name = "health";
              configBlock = "lameduck 10s";
            }
            { name = "ready"; }
            {
              name = "kubernetes";
              parameters = "cluster.local in-addr.arpa ip6.arpa";
              configBlock = ''
                pods insecure
                fallthrough in-addr.arpa ip6.arpa
                ttl 30
              '';
            }
            {
              name = "prometheus";
              parameters = "0.0.0.0:9153";
            }
            {
              name = "forward";
              parameters = ". /etc/resolv.conf";
            }
            {
              name = "cache";
              parameters = "30";
            }
            { name = "loop"; }
            { name = "reload"; }
            { name = "loadbalance"; }
          ];
        }
      ];

      extraConfig = { };

      livenessProbe = {
        enabled = true;
        initialDelaySeconds = 60;
        periodSeconds = 10;
        timeoutSeconds = 5;
        failureThreshold = 5;
        successThreshold = 1;
      };

      readinessProbe = {
        enabled = true;
        initialDelaySeconds = 30;
        periodSeconds = 5;
        timeoutSeconds = 5;
        failureThreshold = 1;
        successThreshold = 1;
      };

      affinity = { };

      topologySpreadConstraints = [ ];

      nodeSelector = { };

      tolerations = [ ];

      podDisruptionBudget = { };

      zoneFiles = [ ];

      extraContainers = [ ];

      extraVolumes = [ ];

      extraVolumeMounts = [ ];

      extraSecrets = [ ];

      env = [ ];

      customLabels = { };

      customAnnotations = { };

      hpa = {
        enabled = false;
        minReplicas = 1;
        maxReplicas = 2;
        metrics = [ ];
      };

      autoscaler = {
        enabled = true;
        coresPerReplica = 256;
        nodesPerReplica = 16;
        min = 0;
        max = 0;
        includeUnschedulableNodes = false;
        preventSinglePointFailure = true;
        podAnnotations = { };
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
      };

      deployment = {
        skipConfig = false;
        enabled = true;
        name = "";
        annotations = { };
        selector = { };
      };

      initContainers = [ ];
    };
  };
}
