{
  lib,
  pkgs,
  config,
  kixlib,
  ...
}:

let
  types = lib.types;

  #imports = [
  #  ./autoscaler.nix
  #  ./deployment.nix
  #];

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
