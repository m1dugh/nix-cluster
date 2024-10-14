{ pkgs
, lib
, ...
}@inputs:
with lib;
let
  buildConfig = pkgs.callPackage ./build-config.nix inputs;
  cfssl = "${pkgs.cfssl}/bin/cfssl";
  cfssljson = "${pkgs.cfssl}/bin/cfssljson";
  jq = "${pkgs.jq}/bin/jq";
  defaultArgs = attrsets.recursiveUpdate inputs {
    inherit cfssljson cfssl jq;
  };
in
pkgs.writeShellScriptBin "gen-certs" ''
    function printErr()
    {
        echo "$@" >&2
    }

  function genCert () {
      profilename=$1
      profileconf=$2
      outname=$3
      csrjson=$4

      if [ -f $outname.pem ]; then
          printErr "skipping generation of $outname for ''${PWD##*/}"
          return 0
      fi

      ${cfssl} gencert -ca=ca.pem -ca-key=ca-key.pem -config=$profileconf -profile=$profilename $csrjson | ${cfssljson} -bare $outname
  }

  function genCa () {
      if [ -f ca.pem ]; then
          printErr "skipping generation of ca for ''${PWD##*/}"
          return 0
      fi

      caconf=$1
      ${cfssl} gencert -initca $caconf | ${cfssljson} -bare ca -
  }

  out=''${1:-./generated-certs}
  mkdir -p $out
  (
  cd $out

  # generates ca.csr, ca-key.pem and ca.pem
  ${pkgs.callPackage ./etcd.nix defaultArgs}
  ${pkgs.callPackage ./kubernetes.nix defaultArgs}
  ${pkgs.callPackage ./kube-front-proxy.nix defaultArgs}


  )
  (
   cd $out/kubernetes
   ${getExe buildConfig} .
  )
''
