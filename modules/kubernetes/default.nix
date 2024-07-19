{
    config,
    lib,
    ...
}:
with lib;
let
    k8sConfig = config.services.kubernetes;
    cfg = config.midugh.k8s-cluster;
in {
}
