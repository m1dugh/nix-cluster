{ pkgs
, etcdHosts
, masterHosts
, workerHosts
, lib
, ...
}:
with lib;
let
  cfssl = "${pkgs.cfssl}/bin/cfssl";
  cfssljson = "${pkgs.cfssl}/bin/cfssljson";
  jq = "${pkgs.jq}/bin/jq";
  defaultArgs = {
    inherit cfssljson cfssl jq;
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

function toJsonCerts () {
    name="$1"
    folder=$name
    filename="certs.json"
    tmpfile="$filename.tmp"

    if [ ! -f $filename ]; then
        echo '{}' > $filename
    fi
    pushd $folder > /dev/null
    for f in *.pem *-key.pem *.csr; do
        ${jq} --rawfile content "$f" ".$name.\"$f\"=\$content" ../$filename  > ../$tmpfile
        mv ../$tmpfile ../$filename
    done
    popd > /dev/null
}

out=''${1:-./generated-certs}
mkdir -p $out
(
cd $out

# generates ca.csr, ca-key.pem and ca.pem
${pkgs.callPackage ./etcd.nix (attrsets.recursiveUpdate defaultArgs { inherit etcdHosts; })}
${pkgs.callPackage ./kubernetes.nix (attrsets.recursiveUpdate defaultArgs { inherit masterHosts workerHosts ; })}
)
''
