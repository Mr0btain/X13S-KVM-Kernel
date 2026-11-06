#!/usr/bin/env bash
# Add qebspil to the EL2 boot path (see PLAN.md Phase 1):
#   \EFI\slbounce\qebspilaa64.efi        (QEBSPIL_ALWAYS_START=1 build)
#   \EFI\slbounce\startup.nsh            (loads qebspil before slbounce, if present)
#   \firmware\qcom\sc8280xp\LENOVO\21BX\  (uncompressed DSP firmware qebspil reads)
# Needs ../AndroidEmulator/scripts/el2-install.sh to have run first.
# The normal Ubuntu boot entry is not touched. --remove undoes it
# (startup.nsh stays; it skips qebspil when the .efi is gone).
set -euo pipefail

TOP="$(cd "$(dirname "$0")/.." && pwd)"
ESP="${ESP:-/boot/efi}"
DST="$ESP/EFI/slbounce"
FWSRC=/lib/firmware/qcom/sc8280xp/LENOVO/21BX
FWDST="$ESP/firmware/qcom/sc8280xp/LENOVO/21BX"
EFI="${QEBSPIL_EFI:-$TOP/out/qebspil/qebspilaa64-always.efi}"
FW="qcadsp8280.mbn qccdsp8280.mbn qcslpi8280.mbn"

[ "$(id -u)" = 0 ] || { echo "run with sudo" >&2; exit 1; }
[ -e "$DST/slbounce.efi" ] || { echo "no $DST/slbounce.efi: run AndroidEmulator/scripts/el2-install.sh first" >&2; exit 1; }

if [ "${1:-}" = "--remove" ]; then
  rm -f "$DST/qebspilaa64.efi"
  rm -rf "$ESP/firmware"
  sync
  echo "removed qebspil + ESP firmware"
  exit 0
fi

[ -e "$EFI" ] || { echo "missing $EFI (build qebspil first)" >&2; exit 1; }

mkdir -p "$FWDST"
for f in $FW; do
  if [ -e "$FWSRC/$f.zst" ]; then zstd -qdcf "$FWSRC/$f.zst" > "$FWDST/$f"
  elif [ -e "$FWSRC/$f.xz" ]; then xz -dc "$FWSRC/$f.xz" > "$FWDST/$f"
  else cp "$FWSRC/$f" "$FWDST/$f"; fi
done

[ -e "$DST/startup.nsh.orig" ] || cp "$DST/startup.nsh" "$DST/startup.nsh.orig"
cp "$EFI" "$DST/qebspilaa64.efi"
cp "$TOP/scripts/el2/startup.nsh" "$DST/startup.nsh"
sync

ls -l "$DST" "$FWDST"
echo "next: reboot, F12 -> 'Ubuntu (EL2 KVM)'; photograph the qebspil lines in the UEFI shell"
