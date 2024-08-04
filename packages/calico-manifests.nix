{
    pkgs,
    stdenv,
    calicoUser ? "calico-cni",
    ...
}:
let
    inherit (pkgs.callPackage ../lib {}) writeJSONText;
    calico-cluster-information = writeJSONText "calico-cluster-information.json" {
        apiVersion = "crd.projectcalico.org/v1";
        kind = "ClusterInformation";
        metadata.name = "default";
        spec = {
            calicoVersion = "v3.28.0";
            clusterType = "k8s,bgp,kubeadm,kdd";
            datastoreReady = true;
        };
    };
    calico-cni-cluster-role-binding = writeJSONText "calico-cni-cluster-role-binding" {
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
    calico-cni-cluster-role = writeJSONText "calico-cni-cluster-role" {
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
        mkdir -p $out/manifests/
        cp $src/manifests/crds.yaml $out/manifests/crds.yaml
        cp ${calico-cni-cluster-role} $out/manifests/calico-cni-clusterrole.json
        cp ${calico-cni-cluster-role-binding} $out/manifests/calico-cni-clusterrole-binding.json
        cp ${calico-cluster-information} $out/manifests/calico-cni-cluster-information.json
        '';
}
