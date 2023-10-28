{
    lib,
    pkgs,
    config,
    ...
}:
with lib;
let cfg = config.services.forward-proxy;
    forEachHost = func: builtins.mapAttrs func cfg.hosts;
    inherit (import ./lib.nix {
        inherit lib pkgs;
    }) hostType;
in {
    options.services.forward-proxy = {
        enable = mkEnableOption "nginx forward proxy";
        hosts = mkOption {
            description = "The list of urls to forward";
            type = hostType;
            default = {};
        };
    };

    config = mkIf cfg.enable {
        networking.firewall.allowedTCPPorts = [
            80
            443
        ];

        services.nginx = {
            recommendedProxySettings = true;
            enable = true;

            virtualHosts = forEachHost (host: hostConfig: {
                forceSSL = hostConfig.forceSsl;
                locations."/" = {
                    proxyPass = hostConfig.proxyUrl;
                };
            });
        };
    };
}
