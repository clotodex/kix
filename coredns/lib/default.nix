{
  pkgs,
  lib,
  ...
}:
rec {
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
}
