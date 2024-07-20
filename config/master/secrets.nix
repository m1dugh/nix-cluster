{ config
, ...
}:
let userInfo = config.users.users.root;
in {
  sops.secrets."gateway/wg0.key" = {
    mode = "0440";
    owner = userInfo.name;
    group = userInfo.group;
  };
}
