{
    pkgs,
    lib,
}:
with lib; {
    hostType = types.attrsOf (types.submodule ({name, config, ...}: {
        options = {
            proxyUrl =  mkOption {
                description = "The url to proxy to port 443";
                type = types.nullOr types.str;
                default = null;
                example = ''
                    https://127.0.0.1:32252
                '';
            };

            forceSsl = mkOption {
                default = false;
                type = types.bool;
                description = "Whether to force ssl";
            };
        };
    }));
}
