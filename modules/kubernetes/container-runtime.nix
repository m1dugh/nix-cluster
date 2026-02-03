{ ...
}:
{
  virtualisation.containerd = {
    enable = true;
    settings = {
      plugins."io.containerd.cri.v1.runtime".containerd.runtimes.runc = {
        options.SystemdCgroup = true;
      };
    };
  };
}
