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

  function toJsonCerts () {
      name="$1"
      folder=$name
      filename="certs.json"
      tmpfile="$filename.tmp"

      if [ ! -f $filename ]; then
          echo '{}' > $filename
      fi
      pushd $folder > /dev/null
      for f in *.pem *-key.pem; do
          ${jq} --rawfile content "$f" ".$name.\"$f\"=\$content" ../$filename  > ../$tmpfile
          mv ../$tmpfile ../$filename
      done
      if ls *.kubeconfig > /dev/null; then
          for f in *.kubeconfig; do
              ${jq} --rawfile content "$f" ".$name.\"$f\"=\$content" ../$filename  > ../$tmpfile
              mv ../$tmpfile ../$filename
          done
      fi
      popd > /dev/null
  }

  out=''${1:-./generated-certs}
  mkdir -p $out
  (
  cd $out

  # generates ca.csr, ca-key.pem and ca.pem
  ${pkgs.callPackage ./etcd.nix defaultArgs}
  ${pkgs.callPackage ./kubernetes.nix defaultArgs}


  )
  (
   cd $out/kubernetes
   ${getExe buildConfig} .
  )
''
