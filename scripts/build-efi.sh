#!/usr/bin/env bash
# Build the UEFI pieces of the EL2 boot path from src/ (scripts/fetch-sources.sh):
#   out/qebspil/qebspilaa64.efi          starts DSPs with qcom,broken-reset (our dtb)
#   out/qebspil/qebspilaa64-always.efi   starts all enabled DSPs (stock dtb)
#   out/slbounce/{slbounce,sltest}.efi   EL2 switch via tcblaunch.exe
# Native arm64 gcc; "aarch64-linux-gnu-" is the native triplet on Ubuntu arm64.
set -euo pipefail
TOP="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$TOP/out/qebspil" "$TOP/out/slbounce"

cd "$TOP/src/qebspil"
make -s clean >/dev/null 2>&1 || true
make -s -j"$(nproc)"
cp out/qebspilaa64.efi "$TOP/out/qebspil/qebspilaa64.efi"
make -s clean >/dev/null 2>&1 || true
make -s -j"$(nproc)" QEBSPIL_ALWAYS_START=1
cp out/qebspilaa64.efi "$TOP/out/qebspil/qebspilaa64-always.efi"

cd "$TOP/src/slbounce"
make -s -j"$(nproc)" CROSS_COMPILE=aarch64-linux-gnu- all
cp out/slbounce.efi out/sltest.efi "$TOP/out/slbounce/"

ls -l "$TOP"/out/qebspil/*.efi "$TOP"/out/slbounce/*.efi
