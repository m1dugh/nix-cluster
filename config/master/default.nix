{ config
, lib
, pkgs
, ...
}:
with lib;
let
  secrets = config.sops.secrets;

  gatewayPorts = {
    internal = {
      http = 30272;
      https = 31561;
    };
    external = {
      http = 30080;
      https = 30443;
    };
  };
in
{
  imports = [
    ./secrets.nix
  ];

  networking.firewall.allowedTCPPorts = [
    80
    443
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

  networking.firewall.filterForward = true;
  networking.firewall.extraForwardRules = ''
    iifname wg0 ip daddr {192.168.1.145,192.168.1.146,192.168.1.147,192.168.1.148} log prefix "accepted traffic to cluster node: " level notice accept comment "accept cluster nodes"
    ip daddr {192.168.1.155-192.168.1.162} log prefix "accepted traffic to load balancers: " level notice accept comment "accept cluster load balancers";
    iifname wg0 ip daddr 192.168.1.0/24 log prefix "traffic dropped to non cluster node: " level info drop comment "drop non cluster nodes"
  '';

  midugh.load-balancer = {
    enable = true;
    addresses.internal = {
      interface = "eth0";
      address = "192.168.1.161";
      targets = [
        "192.168.1.145"
        "192.168.1.146"
        "192.168.1.147"
        "192.168.1.148"
      ];
      ports.https = {
        port = 443;
        targetPort = 31561;
        type = "tcp";
      };
      ports.http = {
        port = 80;
        targetPort = 30272;
        type = "tcp";
      };
    };
    addresses.external = {
      interface = "eth0";
      address = "192.168.1.162";
      targets = [
        "192.168.1.145"
        "192.168.1.146"
        "192.168.1.147"
        "192.168.1.148"
      ];
      ports.https = {
        port = 443;
        targetPort = 30443;
        type = "tcp";
      };
      ports.http = {
        port = 80;
        targetPort = 30080;
        type = "tcp";
      };
    };
  };

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
