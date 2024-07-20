{ pkgs
, lib
, ...
}:
with lib;
let
  expiry = "87600h";
  utils = pkgs.callPackage ../lib { };
  csrDefaults = {
    key = {
      algo = "rsa";
      size = 2048;
    };
  };
in
{
    mkProfile = name: profiles:
    utils.writeJSONText name {
        signing = {
            default.expiry = expiry;
            profiles = attrsets.mapAttrs (name: usages: {
                inherit usages expiry;
            }) profiles;
        };
    };

    mkCsr = name:
    {
        cn,
        hosts ? null,
        country ? "FR",
        state ? "France",
        location ? "Paris",
        organization ? null,
    }: utils.writeJSONText name (attrsets.recursiveUpdate csrDefaults {
        CN = cn;
        inherit hosts;
        names =
        let cfg = mkMerge [
        (mkIf (! isNull organization) {
            O = organization;
        })
        {
            C = country;
            L = location;
            ST = state;
        }
        ];
        in lib.lists.singleton cfg;
    });
}
