{ config
, lib
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
    clients = {
      "10.200.0.2" = "192.168.1.146";
      "10.200.0.3" = "192.168.1.147";
      "10.200.0.4" = "192.168.1.148";
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
