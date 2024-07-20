{ pkgs
, lib
, ...
}:
with lib;
let
    hosts = [
        {
            cn = "cluster-master-1";
            altNames = [ "192.168.1.145" ];
        }
        {
            cn = "cluster-master-2";
            altNames = [ "192.168.1.146" ];
        }
    ];
  inherit (pkgs.callPackage ./lib.nix {}) mkCsr;
  cfssl = "${pkgs.cfssl}/bin/cfssl";
  cfssljson = "${pkgs.cfssl}/bin/cfssljson";
  defaultArgs = {
    inherit cfssljson cfssl;
  };
in pkgs.writeShellScriptBin "gen-certs" ''
function genCert () {
    profilename=$1
    profileconf=$2
    outname=$3
    csrjson=$4

    ${cfssl} gencert -ca=ca.pem -ca-key=ca-key.pem -config=$profileconf -profile=$profilename $csrjson | ${cfssljson} -bare $outname
}

function genCa () {
    caconf=$1
    ${cfssl} gencert -initca $caconf | ${cfssljson} -bare ca -
}

out=''${1:-./generated-certs}
mkdir -p $out
(
cd $out

# generates ca.csr, ca-key.pem and ca.pem
${pkgs.callPackage ./etcd.nix (attrsets.recursiveUpdate defaultArgs {inherit hosts;})}
)
''
