{
  pkgs ? import <nixpkgs> { },
}:
with pkgs;

let
    buildDeps = with pkgs; [
        clang-tools
        cmake
        pkg-config
        ninja
        makeWrapper
        clang
        zig_0_15
    ];

    runtimeDeps = with pkgs; [
        (pkgs.writeShellScriptBin "qemu-system-x86_64-uefi" ''
          qemu-system-x86_64 \
            -bios ${pkgs.OVMF.fd}/FV/OVMF.fd \
            "$@"
        '')
    ];

    libraryPath = pkgs.lib.makeLibraryPath runtimeDeps;
in
mkShell.override { stdenv = zigStdenv; } {
    nativeBuildInputs = with pkgs; [
    ] ++ buildDeps;

    buildInputs = with pkgs; [
    ] ++ runtimeDeps;
}
