{ lib
, ...
}: {

    gateway = {
        node = "cluster-master-1";
    };

    etcd = {
        initialNodes = [
            "cluster-master-1"
            "cluster-master-2"
        ];
    };

    kubernetes = {
        masterAddress = "192.168.1.145";
    };

    nodes = {
        cluster-master-1 = {
            address = "192.168.1.145";
            roles = [ "master" ];
        };
        cluster-master-2 = {
            address = "192.168.1.146";
            roles = [ "master" "worker" ];
        };
        cluster-master-3 = {
            address = "192.168.1.147";
            roles = [ "master" "worker" ];
        };
        cluster-worker-1 = {
            address = "192.168.1.148";
            roles = [ "worker" ];
        };
    };
}
