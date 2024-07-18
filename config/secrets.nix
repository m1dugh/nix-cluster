{
    config,
    ...
}:
let user = config.users.users.root;
in {
    sops.secrets."k8s/server.crt" = {
        mode = "0440";
        owner = user.name;
        group = user.group;
    };

    sops.secrets."k8s/server.key" = {
        mode = "0440";
        owner = user.name;
        group = user.group;
    };

    sops.secrets."k8s/ca.key" = {
        mode = "0440";
        owner = user.name;
        group = user.group;
    };

    sops.secrets."k8s/ca.crt" = {
        mode = "0440";
        owner = user.name;
        group = user.group;
    };

    sops.defaultSopsFile = ./secrets/secrets.yaml;

    sops.age.sshKeyPaths = [
        ./secrets/hosts.key
    ];
}
