#!/usr/bin/env bash
# out/dtb/sc8280xp-lenovo-thinkpad-x13s-el2-dsp.dtb =
#   <kernel>'s X13s -el2 dtb + dts/x13s-el2-dsp.dtso
# Usage: build-dtb.sh [base.dtb]   (default: running kernel's packaged dtb)
set -euo pipefail
TOP="$(cd "$(dirname "$0")/.." && pwd)"
BASE="${1:-/lib/firmware/$(uname -r)/device-tree/qcom/sc8280xp-lenovo-thinkpad-x13s-el2.dtb}"
mkdir -p "$TOP/out/dtb"
dtc -q -@ -I dts -O dtb -o "$TOP/out/dtb/x13s-el2-dsp.dtbo" "$TOP/dts/x13s-el2-dsp.dtso"
fdtoverlay -i "$BASE" -o "$TOP/out/dtb/sc8280xp-lenovo-thinkpad-x13s-el2-dsp.dtb" "$TOP/out/dtb/x13s-el2-dsp.dtbo"
for a in 2400000 3000000 1b300000; do
  fdtget "$TOP/out/dtb/sc8280xp-lenovo-thinkpad-x13s-el2-dsp.dtb" /soc@0/remoteproc@$a qcom,broken-reset >/dev/null
done
echo "$TOP/out/dtb/sc8280xp-lenovo-thinkpad-x13s-el2-dsp.dtb (from $BASE)"
