{ 
lib
, config
, ...
}:
let cfg = config.midugh.kubernetes;
in {
  config.virtualisation.containerd = lib.mkIf cfg.enable {
    enable = true;
    settings = {
      plugins."io.containerd.cri.v1.runtime".containerd.runtimes.runc = {
        options.SystemdCgroup = true;
      };
    };
  };
}
