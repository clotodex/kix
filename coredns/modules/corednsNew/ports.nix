{ lib, servers }:

let
  inherit (lib)
    flatten
    mapAttrsToList
    concatMap
    groupBy
    mapAttrs
    any
    optional
    ;
  inherit (builtins) toString attrValues;

  # Extract protocol requirements from a single zone
  zoneToProtocol =
    server:
    {
      scheme ? "dns://",
      use_tcp ? false,
    }@zone:
    {
      port = toString server.port;
      hostPort = server.hostPort or null;
      istcp = use_tcp || scheme == "tls://" || scheme == "grpc://" || scheme == "https://";
      isudp = scheme == "dns://" || scheme == "";
    };

  # Extract prometheus port from plugin if applicable
  # TODO: this seems stupid and should either be auto-generated through the prometheus integration or the other way around
  pluginToProtocol =
    plugin:
    if plugin.name == "prometheus" then
      let
        addr = toString plugin.parameters;
        port = lib.last (lib.splitString ":" addr);
      in
      [
        {
          inherit port;
          hostPort = null;
          istcp = true;
          isudp = false;
        }
      ]
    else
      [ ];

  # Expand server into all its protocol requirements
  expandServer =
    server: (map (zoneToProtocol server) server.zones) ++ (concatMap pluginToProtocol server.plugins);

  # Merge multiple protocol requirements for same port
  mergeProtocols =
    port: requirements:
    let
      anyTcp = any (r: r.istcp) requirements;
      anyUdp = any (r: r.isudp) requirements;
      hostPort = (lib.findFirst (r: r.hostPort != null) { } requirements).hostPort or null;
    in
    {
      inherit port;
      istcp = anyTcp;
      isudp = anyUdp || (!anyTcp && !anyUdp); # Default to UDP
      inherit hostPort;
    };

  # Group requirements by port number
  groupByPort = requirements: groupBy (req: req.port) requirements;

  # Merge grouped requirements into single config per port
  mergeGroupedPorts = groups: mapAttrs mergeProtocols groups;

  # Generate Kubernetes port spec from protocol config
  protocolToPortSpec =
    portConfig:
    let
      basePort = {
        containerPort = lib.toInt portConfig.port;
      };

      addHostPort =
        spec:
        if portConfig.hostPort != null then spec // { hostPort = lib.toInt portConfig.hostPort; } else spec;

      udpSpec = optional portConfig.isudp (
        addHostPort (
          basePort
          // {
            protocol = "UDP";
            name = "udp-${portConfig.port}";
          }
        )
      );

      tcpSpec = optional portConfig.istcp (
        addHostPort (
          basePort
          // {
            protocol = "TCP";
            name = "tcp-${portConfig.port}";
          }
        )
      );
    in
    udpSpec ++ tcpSpec;

  # Main pipeline
  portSpecs =
    servers
    |> concatMap expandServer
    |> groupByPort
    |> mergeGroupedPorts
    |> attrValues
    |> concatMap protocolToPortSpec;

in
portSpecs
