#!/usr/bin/env bash
# Install the -el2 kernel and wire it into the EL2 boot entry (PLAN.md Phase 4).
#   - dpkg -i out/linux-image-*-el2*.deb (+ headers)
#   - keep the normal GRUB menu on stock -generic kernels (GRUB_FLAVOUR_ORDER)
#   - DSP dtb overlay -> /usr/local/share/kernel-work/
#   - scripts/el2-grubcfg.sh as the zz-el2-grubcfg kernel hook
# Needs root. --remove purges the -el2 packages and restores the old hook.
set -euo pipefail
TOP="$(cd "$(dirname "$0")/.." && pwd)"
HOOK=/etc/kernel/postinst.d/zz-el2-grubcfg
GRUBD=/etc/default/grub.d/90-kernel-work.cfg
SHARE=/usr/local/share/kernel-work


[ "$(id -u)" = 0 ] || { echo "run with sudo" >&2; exit 1; }

if [ "${1:-}" = "--remove" ]; then
  pkgs=$(dpkg-query -W -f '${Package}\n' 'linux-image-*-el2' 'linux-headers-*-el2' 2>/dev/null || true)
  [ -n "$pkgs" ] && apt-get purge -y $pkgs
  rm -rf "$SHARE" "$GRUBD"
  "$HOOK"   # el2.cfg falls back to the stock kernel at EL2
  update-grub
  exit 0
fi

debs=$(ls "$TOP"/out/linux-image-*el2*.deb "$TOP"/out/linux-headers-*el2*.deb 2>/dev/null | grep -v dbg || true)
[ -n "$debs" ] || { echo "no -el2 debs in out/ (run scripts/build-kernel.sh)" >&2; exit 1; }

# Normal boot keeps booting the stock kernel even though 7.3.x-el2 sorts newer.
echo 'GRUB_FLAVOUR_ORDER="generic"' > "$GRUBD"

mkdir -p "$SHARE"
dtc -q -@ -I dts -O dtb -o "$SHARE/x13s-el2-dsp.dtbo" "$TOP/dts/x13s-el2-dsp.dtso"
install -m 755 "$TOP/scripts/el2-grubcfg.sh" "$HOOK"

dpkg -i $debs        # runs postinst.d: initramfs, update-grub, our hook
"$HOOK"
update-grub

echo; grep -E "^menuentry|linux|devicetree" /boot/grub/el2.cfg
echo; echo "normal GRUB default:"; grep -m1 -E "^\s*menuentry " /boot/grub/grub.cfg
