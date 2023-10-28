{
    pkgs,
    config,
    lib,
    ...
}:
with lib;
let kubeConfig = config.services.rpi-kubernetes;
    ismaster = elem "master" kubeConfig.kubernetesConfig.roles;
in {
    imports = [
        ./wireguard
        ./rpi-kubernetes
        ./forward-proxy
        ./config
    ];

    config = {
        midugh.rpi-config.enable = mkDefault true;
        services.rpi-wireguard.enable = mkDefault true;
        services.rpi-kubernetes.enable = mkDefault true;
        services.forward-proxy.enable = mkDefault (kubeConfig.enable && ismaster);

        system.stateVersion = "23.11";

        environment.systemPackages = with pkgs; [
            nfs-utils
        ];
    };
}
