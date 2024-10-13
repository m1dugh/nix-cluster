{ pkgs
, lib
, ...
}:
rec {
  writeJSONText = name: obj: pkgs.writeText "${name}.json" (builtins.toJSON obj);

  mkExtraOpts = elems: lib.strings.concatStringsSep " " (lib.attrsets.mapAttrsToList (key: value: "${key}=${value}") elems);

  mkScheme = tls: if tls then "https" else "http";

  getEtcdNodes = builtins.filter (node: node.etcd.enable);
  etcdHasTls = nodeConfig:
    let
      inherit (nodeConfig.etcd) enable tls;
    in
    enable && tls;

  mkEtcdAddress =
    { address
    , etcd
    , ...
    }:
    if etcd.address != null then etcd.address else address;

  mkEtcdEndpoint =
    { address
    , etcd
    , ...
    }@node:
    let
      address = mkEtcdAddress node;
    in
    "${mkScheme etcd.tls}://${address}:${toString etcd.port}";

  mkApiserverAddress =
    { address
    , port
    , ...
    }: "https://${address}:${toString port}";
}
