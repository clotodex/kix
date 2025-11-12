{
  pkgs,
  lib,
  ...
}:

lib.makeExtensible (self: {
  _defaultMetadata = { };

  # Simple builder API
  withMetadata =
    metadata:
    self.extend (
      self: super: {
        _defaultMetadata = lib.recursiveUpdate super._defaultMetadata metadata;
      }
    );

  # Internal state
  _preprocessors = [ ];

  # Simple builder API
  withPreprocessor =
    preprocessor:
    self.extend (
      self: super: {
        _preprocessors = super._preprocessors ++ [ preprocessor ];
      }
    );

  # Batch for convenience
  withPreprocessors = preprocessors: lib.foldl' (l: p: l.withPreprocessor p) self preprocessors;

  # Named registration for debuggability
  addPreprocessor = name: fn: self.withPreprocessor (lib.setFunctionArgs fn { __name = name; });

  # Inspection (useful for debugging)
  listPreprocessors = map (fn: fn.__name or "<anonymous>") self._preprocessors;

  removeNulls2 =
    attrs:
    lib.filterAttrs (_: v: v != null) (
      builtins.mapAttrs (
        _: v: if builtins.isAttrs v && !(lib.isDerivation v) && !(v ? type) then self.removeNulls v else v
      ) attrs
    );

  removeNulls5 =
    attrs:
    builtins.mapAttrs (
      _: v: if builtins.isAttrs v && !(lib.isDerivation v) && !(v ? type) then self.removeNulls v else v
    ) (lib.filterAttrs (_: v: v != null) attrs);

  removeNulls =
    attrs:
    builtins.mapAttrs
      (
        _: v:
        let
          cleanValue =
            if builtins.isAttrs v && !(lib.isDerivation v) && !(v ? type) then
              self.removeNulls v
            else if builtins.isList v then
              builtins.map (x: if builtins.isAttrs x && !(lib.isDerivation x) then self.removeNulls x else x) v
            else
              v;
        in
        cleanValue
      ) # (lib.filterAttrs (_: v: v != null) attrs);
      (
        lib.filterAttrs (
          _: v:
          v != null
          && !(
            (builtins.isAttrs v && !(lib.isDerivation v) && !(v ? type) && v == { })
            || (builtins.isList v && v == [ ])
          )
        ) attrs
      );

  removeNulls3 =
    attrs:
    builtins.listToAttrs (
      builtins.filter (nameValue: nameValue.value != null) (
        map (name: {
          inherit name;
          value =
            let
              val = attrs.${name};
            in
            if builtins.isAttrs val && !lib.isDerivation val then self.removeNulls val else val;
        }) (builtins.attrNames attrs)
      )
    );

  removeNulls4 = lib.filterAttrsRecursive (name: value: value != null);

  # TODO: mkResource = x: extra: removeNulls (lib.recursiveUpdate x extra);

  # TODO: this could be the main "magic" and one could involve any postprocessors, filtering by kind, etc, in this step
  # could also verify crds
  # how do i install crds?

  # TODO: needs to be overridable, extendable and injectable from the outside
  # list of resource -> resource mappers
  preProcessors = [ ];

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
      resource
      |> self.removeNulls
      |> (x: lib.foldl' (res: f: f res) x self._preprocessors)
      |> self.removeNulls
      |> builtins.toJSON
    );

  mkResource =
    {
      kind,
      apiVersion ? "v1",
      metadata ? { },
      ...
    }@args:
    args
    // {
      inherit apiVersion kind;
      metadata = lib.recursiveUpdate self._defaultMetadata metadata;
    };

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
        ...
      }@r:
      self.mkResource (
        lib.recursiveUpdate r {
          apiVersion = "rbac.authorization.k8s.io/v1";
          kind = "ClusterRole";
          rules = rules;
          metadata = {
            namespace = null;
          };
        }
      );

    bind =
      clusterRole: serviceAccount:
      self.mkManifest (
        self.mkResource {
          apiVersion = "rbac.authorization.k8s.io/v1";
          kind = "ClusterRoleBinding";
          metadata = {
            namespace = null;
          };
          roleRef = {
            apiGroup = lib.elemAt (lib.strings.split "/" clusterRole.apiVersion) 0;
            kind = clusterRole.kind;
            name = self.mkManifest clusterRole;
          };
          subjects = [
            {
              kind = serviceAccount.kind;
              name = self.mkManifest serviceAccount;
              namespace = serviceAccount.metadata.namespace or "default";
            }
          ];
        }
      );

    mkServiceAccount =
      {
        metadata ? { },
        imagePullSecrets ? null,
        ...
      }:
      self.mkResource {
        kind = "ServiceAccount";
        metadata = metadata;
        imagePullSecrets = imagePullSecrets;
      };
  };
  pod = {

    # TODO: will this be smarter?
    # TODO: mkResource?
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
      self.mkResource {
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
        metadata ? { },
        template,
        ...
      }:
      self.mkResource {
        inherit metadata;
        apiVersion = "apps/v1";
        kind = "Deployment";
        spec = {
          inherit replicas strategy template;

          # TODO: this might be too extensive
          #selector = selector ? template.metadata.labels;
          selector.matchLabels = template.metadata.labels;

        };
      };

    withServiceAccount =
      serviceAccount: deployment:
      lib.recursiveUpdate deployment {
        spec = (deployment.spec or { }) // {
          template = (deployment.spec.template or { }) // {
            spec = (deployment.spec.template.spec or { }) // {
              serviceAccountName = self.mkManifest serviceAccount;
            };
          };
        };
      };

    # INFO: could also be called intoSameSelectorService
    intoService =
      serviceArgs: deployment:
      self.networking.mkService (
        lib.recursiveUpdate serviceArgs { spec.selector = deployment.spec.template.metadata.labels; }
      )
      |> self.addDependency (self.mkManifest deployment);
  };

  configMap = {
    mkConfigMap =
      {
        data ? { },
        immutable ? null,
        ...
      }:
      self.mkResource {
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
        # TODO: name
        items ? null,
      }:
      configMap:
      let
        hashForName = builtins.hashString "md5" (builtins.toJSON configMap);
      in
      {
        name = "cfgmap-${hashForName}"; # TODO: check if this is allowed or if we should derive the vol name differently
        configMap = {
          name = self.mkManifest configMap;
          items = items;
        };
      };
  };
})
