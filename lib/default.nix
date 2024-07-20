{ pkgs
, ...
}:
{
  writeJSONText = name: obj: pkgs.writeText "${name}.json" (builtins.toJSON obj);
}
