{
    mkPoetryApplication,
    ...
}: {
    kube-certs = mkPoetryApplication {
        projectDir = ./certs;
    };
}
