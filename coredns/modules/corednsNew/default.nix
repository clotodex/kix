{
  lib,
  pkgs,
  config,
  ...
}:

let
  types = lib.types;

  #imports = [
  #  ./autoscaler.nix
  #  ./deployment.nix
  #];

  kixlib =

    let
      removeNulls = lib.filterAttrs (_: v: v != null);
      # TODO: mkResource = x: extra: removeNulls (lib.recursiveUpdate x extra);

      # TODO: this could be the main "magic" and one could involve any postprocessors, filtering by kind, etc, in this step
      # could also verify crds
      # how do i install crds?

      # TODO: needs to be overridable, extendable and injectable from the outside
      preProcessResource = resource: resource; # no-op for now

      # TODO: could actually turn this into a set:
      # {
      #   data: attrset
      #   drv: storePath
      # }
      # This type would have the advantage of still using data if relevant, and otherwise being clear on the read-onlyness
      # On the other-hand non-typing has the advantage of generating a second store path if something was changed => at least debuggable

      # TODO: can add some preValidation (needs to have kind field, crd registered, etc) -> error will fail inline which is great
      mkManifest =
        resource:
        pkgs.writeText "${resource.kind}.json" (
          resource |> removeNulls |> preProcessResource |> removeNulls |> builtins.toJSON
        );

      addDependency =
        drv: resource:
        let
          # Get current annotations, defaulting to empty set if they don't exist
          currentAnnotations = resource.metadata.annotations or { };

          # Get current dependencies string, defaulting to empty string
          currentDeps = currentAnnotations."build.kix.dev/dependencies" or "";

          # Create new dependencies string
          newDeps = if currentDeps == "" then drv else "${currentDeps},${drv}";

          # Create updated annotations
          newAnnotations = currentAnnotations // {
            "build.kix.dev/dependencies" = newDeps;
          };
        in
        # Use recursiveUpdate to merge deeply, or manual path construction
        lib.recursiveUpdate resource {
          metadata = (resource.metadata or { }) // {
            annotations = newAnnotations;
          };
        };
    in
    rec {
      inherit mkManifest addDependency;

      # TODO: helm loader
      # this could actually be patched a bit
      # - values passed as module config (unsafe but ok)
      # - remove name from everything - find name in all other resources, then replace with derivation hash => while no maintenance gain, you have tracability

      rbac = {

        mkClusterRole =
          {
            rules,
            metadata ? { },
          }:
          {
            apiVersion = "rbac.authorization.k8s.io/v1";
            kind = "ClusterRole";
            metadata = metadata;
            rules = rules;
          };

        bind =
          clusterRole: serviceAccount:
          mkManifest {
            apiVersion = "rbac.authorization.k8s.io/v1";
            kind = "ClusterRoleBinding";
            roleRef = {
              apiGroup = lib.elemAt (lib.strings.split "/" clusterRole.apiVersion) 0;
              kind = clusterRole.kind;
              name = mkManifest clusterRole;
            };
            subjects = [
              {
                kind = serviceAccount.kind;
                name = mkManifest serviceAccount;
              }
            ];
          };

        mkServiceAccount =
          {
            metadata ? null,
            imagePullSecrets ? null,
            ...
          }:
          {
            apiVersion = "v1";
            kind = "ServiceAccount";
            metadata = metadata;
            imagePullSecrets = imagePullSecrets;
          };
      };
      pod = {

        # TODO: will this be smarter?
        mkPodTemplate =
          args@{
            metadata ? { },
            spec,
            ...
          }:
          args;

        mkContainer =
          {
            name,
            image,
            imagePullPolicy ? null,
            command ? null,
            args ? null,
            env ? null,
            resources ? null,
            volumeMounts ? [ ],
            ports ? null,
            securityContext ? null,
            ...
          }:
          {
            name = name;
            image = image;
            imagePullPolicy = imagePullPolicy;
            command = command;
            args = args;
            env = env;
            resources = resources;
            volumeMounts = volumeMounts;
            ports = ports;
            securityContext = securityContext;
          };

        withVolumeMount =
          {
            name,
            mountPath,
            subPath ? null,
            readOnly ? null,
          }:
          container:
          lib.recursiveUpdate container {
            volumeMounts = (container.volumeMounts or [ ]) ++ [
              {
                name = name;
                mountPath = mountPath;
                subPath = subPath;
                readOnly = readOnly;
              }
            ];
          };

        withLivenessProbe =
          probeConfig: container:
          lib.recursiveUpdate container {
            livenessProbe = probeConfig;
          };

        withReadinessProbe =
          probeConfig: container:
          lib.recursiveUpdate container {
            readinessProbe = probeConfig;
          };
      };

      networking = {
        mkService =
          {
            metadata ? { },
            spec,
            ...
          }:
          {
            apiVersion = "v1";
            kind = "Service";
            metadata = metadata;
            spec = spec;
          };
      };

      workload = {

        # TODO: the template might need the preprocessor to run as well - otherwise the pods will not "look right"
        mkDeployment =
          {
            replicas ? 1,
            strategy ? null,
            selector ? null,
            template,
            ...
          }:
          {
            apiVersion = "apps/v1";
            kind = "Deployment";
            spec = {
              inherit replicas strategy template;

              # TODO: this might be too extensive
              selector = selector ? template.metadata.labels;
            };
          };

        withServiceAccount =
          serviceAccount: deployment:
          lib.recursiveUpdate deployment {
            spec = (deployment.spec or { }) // {
              template = (deployment.spec.template or { }) // {
                spec = (deployment.spec.template.spec or { }) // {
                  serviceAccountName = mkManifest serviceAccount;
                };
              };
            };
          };

        # INFO: could also be called intoSameSelectorService
        intoService =
          serviceArgs: deployment:
          networking.mkService (lib.recursiveUpdate serviceArgs { spec.selector = deployment.spec.selector; })
          |> addDependency (mkManifest deployment);
      };

      configMap = {
        mkConfigMap =
          {
            data ? { },
            immutable ? null,
            ...
          }:
          {
            apiVersion = "v1";
            kind = "ConfigMap";
            data = data;
            immutable = immutable;
          };

        withEntry =
          key: value: configMap:
          lib.recursiveUpdate configMap {
            data = (configMap.data or { }) // {
              "${key}" = value;
            };
          };

        withEntries =
          entries: configMap: lib.foldl' (cm: pair: with pair; withEntry key value cm) configMap entries;

        # TODO: as valuefrom as env etc.. https://kubernetes.io/docs/concepts/configuration/configmap/

        asVolume =
          {
            name ? null,
            items ? null,
          }:
          configMap:
          let
            hashForName = builtins.hashString "md5" (builtins.toJSON configMap);
          in
          {
            name = name ? "v${hashForName}"; # TODO: check if this is allowed or if we should derive the vol name differently
            configMap = {
              name = mkManifest configMap;
              items = items;
            };
          };
      };

    };

  coredns = { };

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

  deploySA = kixlib.rbac.mkServiceAccount { };
  roleBind = kixlib.rbac.bind (kixlib.rbac.mkClusterRole {
    rules = [
      "read"
      "write"
    ];
  }) deploySA;

  configMapVol =
    with kixlib.configMap;
    mkConfigMap { }
    |> withEntry "Corefile" (buildCorefile { })
    |> withEntries (
      map (zonefile: {
        key = zonefile.filename;
        value = zonefile.contents;
      }) (coredns.zoneFiles or [ ])
    )
    |> asVolume { };

  cContainer =
    with kixlib.pod;
    mkContainer {
      name = "coredns";
      image = "coredns/coredns:latest";
      imagePullPolicy = "IfNotPresent";
    }
    |> withVolumeMount {
      name = configMapVol.name;
      mountPath = "/etc/coredns";
    }
    # TODO: add extra secrets as volume mounts
    |> withLivenessProbe (coredns.livenessProbe or { })
    |> withReadinessProbe (coredns.livenessProbe or { })
    |> lib.recursiveUpdate config.containerOverrides or { };

  cService =
    kixlib.workload.mkDeployment {
      replicas = coredns.replicaCount or 1;
      strategy = {
        type = "RollingUpdate";
        rollingUpdate = coredns.rollingUpdate or { };
      };
      template =
        kixlib.pod.mkPodTemplate {
          metadata = { };
          spec = {
            containers = [ cContainer ];
            volumes = [ configMapVol ];
          };
        }
        |> lib.recursiveUpdate config.podOverrides or { };
    }
    |> kixlib.addDependency roleBind # FIXME: instead of this roll that as (forced) argument into withSA
    |> kixlib.workload.withServiceAccount deploySA
    |> kixlib.workload.intoService { };

  #  - monitor it
  #      - Servicemonitor
  #      - Service to select prometheus pods??
  #  - With hpa
  #      - Hpa
  #  - Or with autoscaler
  #      - Deployment
  #          - Service account
  #              - Clusterrolebinding
  #                  - Clusterrole
  #  - And disruption budget
in
{
  config.manifests = {
    "coredns" = kixlib.mkManifest cService;
  };
}
