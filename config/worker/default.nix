{
    masterAddress,
    masterAPIServerPort,
    masterHostName,
    ...
}:
{
    networking.extraHosts = ''
    ${masterAddress}    ${masterHostName}
    '';
    services.kubernetes = 
    let
        api = "https://${masterAddress}:${toString masterAPIServerPort}";
    in {
        roles = ["node"];
        kubelet.kubeconfig.server = api;
    };
}
