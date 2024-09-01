{ pkgs
, ...
}: {
  fileSystems."/nfs" = {
    label = "KUBE";
    fsType = "btrfs";
    options = [
      "nofail"
    ];
  };

  services.nfs = {
    server = {
      enable = true;
      exports = ''
        /nfs    192.168.1.0/24(rw,fsid=0,no_subtree_check)
        /nfs/shared    192.168.1.0/24(rw,fsid=0,no_subtree_check)
      '';
    };
    settings = {
      nfsd.vers3 = "no";
    };
  };

  environment.systemPackages = with pkgs; [
    btrfs-progs
  ];

  networking.firewall.allowedTCPPorts = [ 2049 ];
}
