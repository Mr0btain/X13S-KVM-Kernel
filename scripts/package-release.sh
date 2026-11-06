#!/usr/bin/env bash
# Collect release assets into out/release/ (flat, as uploaded to GitHub):
#   linux-image-*-el2_*.deb, linux-headers-*-el2_*.deb
#   qebspilaa64.efi, qebspilaa64-always.efi, slbounce.efi, sltest.efi
#   SHA256SUMS
# Not included: tcblaunch.exe (Microsoft binary, see notes/slbounce-el2.md)
# and linux-libc-dev (would replace the distro's kernel headers).
set -euo pipefail
TOP="$(cd "$(dirname "$0")/.." && pwd)"
R="$TOP/out/release"
rm -rf "$R"; mkdir -p "$R"
cp "$TOP"/out/linux-image-*el2*.deb "$TOP"/out/linux-headers-*el2*.deb "$R/"
cp "$TOP"/out/qebspil/qebspilaa64.efi "$TOP"/out/qebspil/qebspilaa64-always.efi "$R/"
cp "$TOP"/out/slbounce/slbounce.efi "$TOP"/out/slbounce/sltest.efi "$R/"
(cd "$R" && sha256sum -- * > SHA256SUMS)
ls -lh "$R"
