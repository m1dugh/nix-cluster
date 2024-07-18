{
    config,
    options,
    lib,
    ...
}:
with lib;
let cfg = config.midugh.kubernetes;
in {
   options.midugh.kubernetes = { 
        enable = mkEnableOption "kubernetes overlay";
        roles = options.services.kubernetes.roles;
   };

   config = mkIf cfg.enable {
    services.kubernetes = {
        enable = true;
    };
   };
}
