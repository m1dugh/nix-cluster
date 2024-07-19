{
    pkgs,
    lib,
    ...
}:
with lib;
let
    workerNodes = [
        {
            name = "cluster-node-1";
            altNames = [
                "IP:192.168.1.146"
            ];
        }
        {
            name = "cluster-node-2";
            altNames = [
                "IP:192.168.1.147"
            ];
        }
        {
            name = "cluster-node-3";
            altNames = [
                "IP:192.168.1.147"
            ];
        }
    ];
    certs = [
        "admin"
        "kube-proxy"
        "kube-scheduler"
        "kube-controller-manager"
        "kube-api-server"
        "service-accounts"
    ] ++ builtins.map (n: n.name) workerNodes;
    caConf = pkgs.callPackage ./ca-conf.nix {
        nodes = workerNodes;
    };
    openssl = "${pkgs.openssl}/bin/openssl";

    generateKubeCerts = strings.concatStringsSep "\n" (
        builtins.map (name: ''
            printerr generating "$out/${name}.key"
            ${openssl} genrsa -out "$out/${name}.key" 4096

            printerr generating "$out/${name}.csr"
            ${openssl} req -new -key "$out/${name}.key" -sha256 \
                -config ${caConf} -section "${name}" \
                -out "$out/${name}.csr"

            printerr generating "$out/${name}.crt"
            ${openssl} x509 -req -days 3653 -in "$out/${name}.csr" \
                -copy_extensions copyall \
                -sha256 -CA "$out/ca.crt" \
                -CAkey "$out/ca.key" \
                -CAcreateserial \
                -out "$out/${name}.crt"
        '') certs
    );
    gen-certs = pkgs.writeShellScriptBin "gen-certs" ''
    set -e

    out=''${2:-./generated-certs}

    function printerr () {
        echo $* >&2
    }

    mkdir -p $out
    printerr generating files in $out

    function genCaKey () {
        if [ ! -f ca.key ]; then
            printerr generating $out/ca.key
            ${openssl} genrsa -out $out/ca.key 4096
        fi
    }

    function genCaCrt () {
        if [ ! -f ca.crt ]; then
            printerr generating $out/ca.crt
            ${openssl} req -x509 -new -sha512 -noenc \
                -key $out/ca.key -days 3653 \
                -config ${caConf} \
                -out $out/ca.crt
        fi
    }

    function genKubeCerts () {
        ${generateKubeCerts}
    }

    genCaKey
    genCaCrt
    genKubeCerts
'';
in {
    inherit gen-certs;
}
