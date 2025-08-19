{ pkgs, lib, ... }:
{
  services = {
    nginx.enable = false;

    coredns =
      /* lib.recursiveUpdate
        {
          # INFO: defaults since I am lazy with good typing
          autoscaler.enabled = false;
          hpa.enabled = false;
          podDisruptionBudget = { };
          prometheus.monitor.enabled = false;
          customAnnotations = { };
          customLabels = { };
          image = {
            repository = "registry.k8s.io/cpa/cluster-proportional-autoscaler";
            tag = "v1.9.0";
            pullPolicy = "IfNotPresent";
            pullSecrets = [ ];
          };
          zoneFiles = [ ];
          rollingUpdate = {
            maxUnavailable = 1;
            maxSurge = "25%";
          };
        podAnnotations = { };
        podSecurityContext = {};
        priorityClassName = "";
        affinity = { };
        topologySpreadConstraints = { };
        tolerations = { };
        nodeSelector = { };
        initContainers = [];
        livenessProbe.enabled = false;
        readinessProbe.enabled = false;
        securityContext = {};
        env = {};
        extraSecrets = {};
        terminationGracePeriodSeconds = {};
          deployment = {
            skipConfig = false;
            enabled = true;
            #name = "";
            annotations = { };
            selector = { };
            #initContainers = [ ];
            #affinity = { };
            #topologySpreadConstraints = [ ];
            #nodeSelector = { };
            #tolerations = [ ];
            #podDisruptionBudget = { };
            #extraContainers = [ ];
            #extraVolumes = [ ];
            #extraVolumeMounts = [ ];
            #extraSecrets = [ ];
            #env = [ ];
          };
          rbac.create = true;
        } */
        {
          enable = true;
          isClusterService = true;
          replicaCount = 3;

          serviceAccount = {
            create = true;
            name = "coredns-external";
          };

          serviceType = "ClusterIP";
          service.clusterIP =
            let
              # TODO: Make this configurable.
              cluster_ip = "{{ service_cidr_ipv4 | lithus_platform.combined.make_address(10) | string }}";
            in
            cluster_ip;

          prometheus.service.enabled = true;

          resources.limits = {
            cpu = "500m";
            memory = "256Mi";
          };

          servers =
            let
              domain = "cluster.local";
              external_recursive_nameservers = [
                "8.8.8.8"
                "1.1.1.1"
              ];
            in
            [
              {
                port = 53;
                zones = [
                  {
                    zone = ".";
                    use_tcp = false;
                    scheme = "dns://";
                  }
                ];

                plugins = [
                  {
                    name = "errors";

                  }
                  {
                    name = "health";
                    configBlock = ''
                      lameduck 5s
                    '';
                  }

                  {
                    name = "ready";

                    # Services which we give nice internal domains;
                  }
                  {
                    name = "rewrite";
                    parameters = "name s3.${domain} public.nginx-system.svc.${domain}";
                  }
                  {

                    name = "rewrite";
                    parameters = "name console.s3.${domain} public.nginx-system.svc.${domain}";

                  }
                  {
                    name = "rewrite";
                    parameters = "name harbor.${domain} public.nginx-system.svc.${domain}";

                  }
                  {
                    # Resolve the internal domain root (+ cluster.local, as usual) using kubernetes.;
                    name = "kubernetes";
                    parameters = "${domain} cluster.local in-addr.arpa ip6.arpa";
                    configBlock = ''
                      pods insecure

                      fallthrough ${domain} in-addr.arpa ip6.arpa
                      ttl 30
                    '';

                  }
                  {
                    name = "prometheus";
                    parameters = "0.0.0.0:9153";

                  }
                  {
                    name = "forward";
                    parameters = ". ${builtins.elemAt external_recursive_nameservers 0}:53 ${builtins.elemAt external_recursive_nameservers 1}:53";

                  }
                  {
                    name = "loop";
                  }
                  {
                    name = "reload";
                  }
                  {
                    name = "loadbalance";
                  }
                ];
              }
            ];
        };
  };
}
