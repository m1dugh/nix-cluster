{ pkgs
, ...
}:
let
  utils = pkgs.callPackage ../lib { };
  csrDefaults = {
    key = {
      algo = "rsa";
      size = 2048;
    };
  };
in
{ }
