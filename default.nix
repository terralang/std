{ pkgs ? import <nixpkgs> { }, stdenv ? pkgs.stdenv, ... }:

stdenv.mkDerivation {
  pname = "terra-std";
  version = "0.0.1";

  src = ./.;

  dontConfigure = true;
  dontBuild = true;
  installPhase = ''
    install -m 444 -Dt $out/share/terra/std *.t
    install -m 444 -Dt $out/share/terra/std/meta meta/*.t
  '';
}
