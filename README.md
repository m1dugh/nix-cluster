# NixOS k8s cluster

This project is an kubernetes high-availability cluster powering my infrastructure.

## Network

### Nodes

- 192.168.1.145 : control-plane, gateway to external traffic
- 192.168.1.146 : control-plane, worker
- 192.168.1.147 : control-plane, worker
- 192.168.1.148 : worker

### Extra addresses

- 192.168.1.161 : internal traffic (only reachable through vpn)
- 192.168.1.162 : external traffic (reachable through gateway)

## Deploying

### Secret Generation

To properly work, the following secrets are required :

- ./secrets/servers.key : The rsa private key used to decrypt all the secrets
- ./secrets/secrets.yaml : the encoded secrets
- ./secrets/certs.json : The encoded certificates for kubernetes to run

The certs secrets can be generated using ./pkgs/certs/


### Building the sd card

The initial deployment is meant to be with a preflashed sdCard.

```bash
nix build .\#nixosConfigurations.<image>.config.system.build.sdImage
```

Which will build a zstd compressed image flashable on an sdCard

### Deploying keys via colmena

To deploy the keys via colmena, use the following commands :

```bash
colmena upload-keys
```

### Redeploying derivations via colmena

```bash
colmena apply --no-keys
```
