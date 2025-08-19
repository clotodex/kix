{
  lib,
  pkgs,
  config,
  ...
}:

let
  types = lib.types;

  options.manifests = lib.mkOption {
    type = types.attrsOf types.anything;
    default = { };
  };

in
{
  # Export the options for module system integration
  inherit options;

  # Export manifests only if the service is enabled
  config = {
  };
}
