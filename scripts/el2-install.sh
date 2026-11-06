#!/usr/bin/env bash
# Install the EL2 (KVM) boot path next to the normal Ubuntu boot
# (notes/slbounce-el2.md). Then: install-esp.sh (qebspil) + install-kernel.sh.
#
#   firmware entry "Ubuntu (EL2 KVM)" -> \EFI\slbounce\shellaa64.efi
#     -> startup.nsh: load slbounce.efi, run grubel2.efi
#     -> /boot/grub/el2.cfg: newest kernel + X13s -el2.dtb
#     -> slbounce sees the EL2 dtb at ExitBootServices and Secure-Launches to EL2
#
# BootOrder is kept (normal Ubuntu stays first); pick "Ubuntu (EL2 KVM)" from
# the F12 boot menu. Each run also sets it as BootNext for one test boot.
# Needs root. --remove undoes everything.
set -euo pipefail

TOP="$(cd "$(dirname "$0")/.." && pwd)"
EL2="$TOP/out/el2"
ESP="${ESP:-/boot/efi}"
DST="$ESP/EFI/slbounce"
LABEL="Ubuntu (EL2 KVM)"
OLD_LABEL="UEFI Shell (slbounce)"   # old one-shot sltest entry (removed)
HOOK=/etc/kernel/postinst.d/zz-el2-grubcfg
DISK=/dev/nvme0n1 PART=1

[ "$(id -u)" = 0 ] || { echo "run with sudo" >&2; exit 1; }

entries() { efibootmgr | sed -n "s/^Boot\([0-9A-F]\{4\}\)\*\{0,1\} $1\(	.*\)\{0,1\}$/\1/p"; }
delete_entries() { for n in $(entries "$1"); do efibootmgr -q -b "$n" -B; done; }

if [ "${1:-}" = "--remove" ]; then
  delete_entries "$LABEL"
  delete_entries "$OLD_LABEL"
  rm -rf "$DST" "$ESP/tcblaunch.exe" "$HOOK" /boot/grub/el2.cfg /boot/el2
  echo "removed EL2 boot path"
  exit 0
fi

# Standalone GRUB that only reads /boot/grub/el2.cfg (Ubuntu's menu is hidden).
mkdir -p "$EL2/grub"
grub-mkimage -O arm64-efi -o "$EL2/grub/grubel2.efi" -p /boot/grub \
  -c "$TOP/scripts/el2/grubel2-embed.cfg" \
  normal configfile search search_fs_file search_fs_uuid part_gpt fat ext2 linux fdt \
  gzio echo test efi_gop all_video gfxterm font reboot halt efifwsetup lsefisystab sleep

for f in "$EL2/slbounce/out/slbounce.efi" "$EL2/grub/grubel2.efi" "$EL2/tcblaunch.exe" \
         /usr/share/efi-shell-aa64/shellaa64.efi; do
  [ -e "$f" ] || { echo "missing $f" >&2; exit 1; }
done

# slbounce opens tcblaunch.exe from the root of the volume it was loaded from.
cp -L "$EL2/tcblaunch.exe" "$ESP/tcblaunch.exe"
mkdir -p "$DST"
cp "$EL2/slbounce/out/slbounce.efi" "$EL2/grub/grubel2.efi" \
   /usr/share/efi-shell-aa64/shellaa64.efi "$TOP/scripts/el2/startup.nsh" "$DST/"
sync

install -m 755 "$TOP/scripts/el2-grubcfg.sh" "$HOOK"
"$HOOK"

# Labels go into a sed BRE as-is: there ( and ) are literal.
delete_entries "$OLD_LABEL"
n="$(entries "$LABEL")"
if [ -z "$n" ]; then
  order="$(efibootmgr | sed -n 's/^BootOrder: //p')"
  efibootmgr -q -c -d "$DISK" -p "$PART" -L "$LABEL" -l '\EFI\slbounce\shellaa64.efi'
  n="$(entries "$LABEL")"
  efibootmgr -q -o "$order,$n"   # -c put it first; normal Ubuntu stays first
fi
efibootmgr -q -n "$n"            # next boot only: test it

ls -l "$ESP/tcblaunch.exe" "$DST"
efibootmgr | grep -E "^Boot(Next|Order|Current)"
efibootmgr | grep -F "$LABEL"
