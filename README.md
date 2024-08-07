# NixOS k8s cluster

## Introduction

This project has been described in a medium article that can be found
[here](https://midugh.medium.com/build-your-kubernetes-cluster-with-raspberry-pis-using-nixos-745ed11e5b70).
It gives more explanation about the whole construction of the project.

## Building the project

### Building the SD image

To build an sd image, run the following command.

```shell
$ ./runner-wrapper.sh nix build .#nixosConfigurations.<host>.config.system.build.sdImage
```

Where `<host>` is the name of the nixosConfiguration.

### Deploying to target

To deploy to an existing nixos host, run the following command

```shell
$ ./runner-wrapper.sh nixos-rebuild switch --fast \
    --flake .#<host> \
    --target-host root@<address> \
    --build-host root@<address>
```

Where `<host>` is the name of the nixos config, and `<address>`, is the network address of the target host.

## Components

### Calico

Calico is the cni used on each machine.

To install calico, the following [guide](https://docs.tigera.io/calico/latest/getting-started/bare-metal/installation/binary)
was used.

## Modules

### Gateway

The gateway module is a wireguard server that serves as
entrypoint for the cluster.

The subnet for the vpn is `10.200.0.0/24`.
The IP Addresses for the nodes are
`10.200.0.1-10.200.0.99`, and the remaining range
is for other clients.

## Deploying secrets

To deploy secrets, you need to upload an ssh key that has been used to encrypt
the secrets onto the node.

Push key `secrets/servers.key` to `/var/lib/nixos/servers.key` on the remote
node to allow it.
