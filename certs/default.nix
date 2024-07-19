{
    pkgs,
    ...
}:
let
    master = {
        name = "cluster-master";
        address = "192.168.1.145";
    };
    workerNodes = [
        {
            name = "cluster-node-1";
            address = "192.168.1.146";
        }
        {
            name = "cluster-node-2";
            address = "192.168.1.147";
        }
        {
            name = "cluster-node-3";
            address = "192.168.1.147";
        }
    ];
in
{
    gen-certs = pkgs.callPackage ./gen-certs.nix {
        nodes = workerNodes;
    };

    deploy-certs = pkgs.callPackage ./deploy-certs.nix {
        nodes = workerNodes;
        inherit master;
    };
}
