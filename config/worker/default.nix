{ masterAddress
, masterAPIServerPort
, masterHostName
, ...
}:
{
  networking.extraHosts = ''
    ${masterAddress}    ${masterHostName}
  '';
}
