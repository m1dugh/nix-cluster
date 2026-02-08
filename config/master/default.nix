{ config
, lib
, pkgs
, ...
}:
with lib;
let secrets = config.sops.secrets;

    gatewayPorts = {
        internal = {
            http = 30272;
            https = 31561;
        };
        external = {
            http = 30272;
            https = 31561;
        };
    };
in {
  imports = [
    ./secrets.nix
  ];

  midugh.gateway = {
    enable = true;
    internalInterface = "wg0";
    externalInterface = "eth0";
    ipAddresses = lists.singleton "10.200.0.1/24";
    port = 42420;
  };

  environment.systemPackages = with pkgs; [
    ddclient
  ];

  services.ddclient = {
    enable = true;
    passwordFile = secrets."gateway/cloudflare-token".path;
    protocol = "cloudflare";
    zone = "midugh.fr";
    domains = [
      "gateway.infra.midugh.fr"
    ];
    ssl = true;
    extraConfig = ''
      usev4=webv4,webv4=ifconfig.me
    '';
  };

  networking.firewall.interfaces.eth0.allowedTCPPorts = [
        gatewayPorts.internal.http
        gatewayPorts.internal.https
        gatewayPorts.external.http
        gatewayPorts.external.https
    ];

  networking.firewall.filterForward = true;
  networking.firewall.extraForwardRules = ''
    iifname wg0 ip daddr {192.168.1.145,192.168.1.146,192.168.1.147,192.168.1.148} log prefix "accepted traffic to cluster node: " level notice accept comment "accept cluster nodes"
    ip daddr {192.168.1.155-192.168.1.160} log prefix "accepted traffic to load balancers: " level notice accept comment "accept cluster load balancers";
    iifname wg0 ip daddr 192.168.1.0/24 log prefix "traffic dropped to non cluster node: " level info drop comment "drop non cluster nodes"
  '';

    services.haproxy = {
        enable = true;
        config = ''
        frontend internalHTTP
            mode tcp
            bind 192.168.1.161:80
            default_backend internalHTTP
        backend internalHTTP
            mode tcp
            balance roundrobin
            server cluster-master-1 192.168.1.145:${toString gatewayPorts.internal.http} check
            server cluster-master-2 192.168.1.146:${toString gatewayPorts.internal.http} check
            server cluster-master-3 192.168.1.147:${toString gatewayPorts.internal.http} check
            server cluster-worker-1 192.168.1.148:${toString gatewayPorts.internal.http} check

        frontend internalHTTPs
            mode tcp
            bind 192.168.1.161:443
            default_backend internalHTTPs
        backend internalHTTPs
            mode tcp
            balance roundrobin
            server cluster-master-1 192.168.1.145:${toString gatewayPorts.internal.https} check
            server cluster-master-2 192.168.1.146:${toString gatewayPorts.internal.https} check
            server cluster-master-3 192.168.1.147:${toString gatewayPorts.internal.https} check
            server cluster-worker-1 192.168.1.148:${toString gatewayPorts.internal.https} check

        frontend externalHTTP
            mode tcp
            bind 192.168.1.162:80
            default_backend externalHTTP
        backend externalHTTPs
            mode tcp
            balance roundrobin
            server cluster-master-1 192.168.1.145:${toString gatewayPorts.external.http} check
            server cluster-master-2 192.168.1.146:${toString gatewayPorts.external.http} check
            server cluster-master-3 192.168.1.147:${toString gatewayPorts.external.http} check
            server cluster-worker-1 192.168.1.148:${toString gatewayPorts.external.http} check

        frontend externalHTTPs
            mode tcp
            bind 192.168.1.162:443
            default_backend externalHTTPs
        backend externalHTTPs
            mode tcp
            balance roundrobin
            server cluster-master-1 192.168.1.145:${toString gatewayPorts.external.https} check
            server cluster-master-2 192.168.1.146:${toString gatewayPorts.external.https} check
            server cluster-master-3 192.168.1.147:${toString gatewayPorts.external.https} check
            server cluster-worker-1 192.168.1.148:${toString gatewayPorts.external.https} check
        '';
    };

    networking.interfaces.eth0.ipv4.addresses = [{
        address = "192.168.1.161";
        prefixLength = 32;
    }
    {
        address = "192.168.1.162";
        prefixLength = 32;
    }];

  networking.wireguard.interfaces."wg0" = {
    privateKeyFile = secrets."gateway/wg0.key".path;

    peers = [
      {
        # Midugh pc
        publicKey = "jVWVndscDaTe2YtVKGxOozWx+O2fd9rxWYVr9+wCEiQ=";
        allowedIPs = [
          "10.200.0.100/32"
        ];
      }
      {
        # Midugh phone
        publicKey = "Hpb87xmb9sTOjT4t/13BITP6l6NzQdAjOaL9f1LABk8=";
        allowedIPs = [
          "10.200.0.101/32"
        ];
      }
    ];
  };
}
