{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  nativeBuildInputs = 
    let
      fundament-terra = import (pkgs.fetchFromGitHub {
        owner = "Fundament-Software";
        repo = "terra";
        rev = "89b5c7cb71fa4aaaeb2b4ff5d3fe0389fec15268";
        sha256 = "05drwz75ah774g6b70d01v2glg8aj6p0ahz4cb88inr6jijzd57g";
      }) { inherit pkgs; };
    in
      [ fundament-terra ];
}
