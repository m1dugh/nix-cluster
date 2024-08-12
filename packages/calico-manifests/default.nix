{
    pkgs,
    stdenv,
    calicoUser ? "calico-cni",
    ...
}:
let
    calico-cluster-information = builtins.toJSON {
        apiVersion = "crd.projectcalico.org/v1";
        kind = "ClusterInformation";
        metadata.name = "default";
        spec = {
            calicoVersion = "v3.28.0";
            clusterType = "k8s,bgp,kubeadm,kdd";
            datastoreReady = true;
        };
    };
    calico-cni-cluster-role-binding = builtins.toJSON {
        apiVersion = "rbac.authorization.k8s.io/v1";
        kind = "ClusterRoleBinding";
        metadata.name = "calico-cni";
        roleRef = {
            apiGroup = "rbac.authorization.k8s.io";
            kind = "ClusterRole";
            name = calicoUser;
        };
        subjects = [{
            apiGroup = "rbac.authorization.k8s.io";
            kind = "User";
            name = calicoUser;
        }];
    };
    calico-cni-cluster-role = builtins.toJSON {
        apiVersion = "rbac.authorization.k8s.io/v1";
        kind = "ClusterRole";
        metadata.name = calicoUser;
        rules = [
            {
                apiGroups = [""];
                resources = [
                    "pods"
                    "nodes"
                    "namespaces"
                ];
                verbs = [
                    "get"
                ];
            }
            {
                apiGroups = [""];
                resources = [
                    "pods/status"
                ];
                verbs = [
                    "patch"
                ];
            }
            {
                apiGroups = ["crd.projectcalico.org"];
                resources = [
                    "blockaffinities"
                    "ipamblocks"
                    "ipamhandles"
                    "ipreservations"
                    "ipamconfigs"
                    "clusterinformations"
                    "ippools"
                ];
                verbs = [
                    "get"
                    "list"
                    "create"
                    "update"
                    "delete"
                ];
            }
        ];
    };
in stdenv.mkDerivation {
    name = "calico-manifests";

    buildInputs = with pkgs; [
        git
        libuuid
    ];

    src = pkgs.fetchFromGitHub {
        owner = "projectcalico";
        repo = "calico";
        rev = "v3.28.0";
        hash = "sha256-nrA9rveZQ7hthXnPn86+J2ztFnG/VwOL772HnF3AvGY=";
        sparseCheckout = [
            "manifests"
        ];
    };

    phases = [
        "unpackPhase"
        "installPhase"
    ];

    installPhase = ''
        addEntry() {
            echo "---"   
            cat /dev/stdin
        } >> $out
        cat $src/manifests/crds.yaml > $out
        echo '${calico-cni-cluster-role}' | addEntry
        echo '${calico-cni-cluster-role-binding}' | addEntry
        echo '${calico-cluster-information}' | addEntry
        cat ${./calico-node-cluster-role.yaml} | addEntry
        cat ${./calico-node-daemon-set.yaml} | addEntry
        '';
}
