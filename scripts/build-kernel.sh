#!/usr/bin/env bash
# Build the -el2 kernel as .debs into out/ (PLAN.md Phase 3).
# Config: the running Ubuntu kernel's, updated with olddefconfig.
#   - LOCALVERSION=-el2
#   - no Ubuntu cert files (Secure Boot is off), module signing key auto-generated
#   - DEBUG_INFO off: saves hours and ~1 GB of -dbg package (BTF goes with it)
# Usage: build-kernel.sh [-jN]   (default -j6: 14 GB RAM)
set -euo pipefail
TOP="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${SRC:-$TOP/src/linux-7.3}"
JOBS="${1:--j6}"
cd "$SRC"
if [ ! -e .config ]; then
  cp "/boot/config-$(uname -r)" .config
  scripts/config --set-str LOCALVERSION "-el2" \
                 --disable LOCALVERSION_AUTO \
                 --set-str SYSTEM_TRUSTED_KEYS "" \
                 --set-str SYSTEM_REVOCATION_KEYS "" \
                 --undefine DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT \
                 --undefine DEBUG_INFO_DWARF4 --undefine DEBUG_INFO_DWARF5 \
                 --enable DEBUG_INFO_NONE \
                 --disable BUILTIN_MODULE_RANGES \
                 --module QCOM_Q6V5_PAS
  make olddefconfig
fi
grep -E "^CONFIG_(LOCALVERSION|KVM|QCOM_Q6V5_PAS|DEBUG_INFO_NONE)=" .config
start=$(date +%s)
rc=0
make "$JOBS" LOCALVERSION= KDEB_PKGVERSION="$(make -s kernelversion)-1el2" bindeb-pkg > "$TOP/out/kernel-build.log" 2>&1 || rc=$?
grep -E "error:|\*\*\*|dpkg-deb: building" "$TOP/out/kernel-build.log" | grep -v "error-inject" | tail -20 || true
echo "build took $(( ($(date +%s) - start) / 60 )) min"
mv -f ../linux-*el2*.deb ../linux-*el2*.buildinfo ../linux-*el2*.changes "$TOP/out/" 2>/dev/null || true
ls -l "$TOP"/out/*.deb
exit $rc
