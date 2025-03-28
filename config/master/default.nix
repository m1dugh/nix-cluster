{ config
, lib
, pkgs
, ...
}:
with lib;
let secrets = config.sops.secrets;
in {
  imports = [
    ./secrets.nix
  ];

  midugh.gateway = {
    enable = true;
    internalInterface = "wg0";
    externalInterface = "eth0";
    ipAddresses = lists.singleton "10.200.0.1/24";
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
      iifname wg0 ip daddr {192.168.1.145,192.168.1.146,192.168.1.147,192.168.1.148} accept comment "accept cluster nodes"
      iifname wg0 ip daddr 192.168.1.0/24 drop comment "drop non cluster nodes"
  '';

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
