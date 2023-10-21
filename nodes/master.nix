{
    address,
    hostName ? "cluster-master",
    authorizedKeys ? [],
    apiPort ? 6443,
    etcdPort ? 2379,
}:
{
    ...
}:
{
    imports = [
        (import ./node.nix {
            inherit hostName apiPort authorizedKeys;
            ipv4 = address;
            extraPorts = [ apiPort etcdPort ];
            kubernetesRoles = [ "master" "node" ];
        })
    ];

    services.etcd = {
        listenClientUrls = ["http://${address}:${toString etcdPort}"];
        advertiseClientUrls = ["http://${address}:${toString etcdPort}"];
    };
}
