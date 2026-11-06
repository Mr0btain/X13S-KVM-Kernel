#!/usr/bin/env bash
# Full build from a clean checkout, as run by .github/workflows/build.yml in
# an ubuntu:26.04 arm64 container (works the same on an arm64 Ubuntu 26.04
# machine): packages -> fetch -> patches -> EFI tools -> kernel -> release dir.
#
#   JOBS=n          parallel jobs (default: nproc)
#   CCACHE_DIR=dir  enable ccache for the kernel build (CI caches it)
#   SKIP_APT=1      don't install packages
set -euo pipefail
TOP="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TOP"

if [ -z "${SKIP_APT:-}" ]; then
  export DEBIAN_FRONTEND=noninteractive
  SUDO=; [ "$(id -u)" = 0 ] || SUDO=sudo
  $SUDO apt-get update -q
  $SUDO apt-get install -y -q --no-install-recommends \
    ca-certificates git curl xz-utils zstd file ccache python3 \
    build-essential bc bison flex libssl-dev libelf-dev libdw-dev dwarves \
    libncurses-dev debhelper dpkg-dev rsync cpio kmod gawk \
    device-tree-compiler
fi

git config --global --get-all safe.directory 2>/dev/null | grep -qx '\*' || git config --global --add safe.directory '*'
export JOBS="${JOBS:-$(nproc)}"
[ -n "${CCACHE_DIR:-}" ] && export CCACHE_MAXSIZE="${CCACHE_MAXSIZE:-4G}"

echo "::group::fetch sources"
scripts/fetch-sources.sh
echo "::endgroup::"

echo "::group::apply patches"
scripts/apply-patches.sh
echo "::endgroup::"

echo "::group::EFI tools (qebspil, slbounce)"
scripts/build-efi.sh
echo "::endgroup::"

echo "::group::kernel"
command -v ccache >/dev/null && ccache -z >/dev/null || true
scripts/build-kernel.sh "-j$JOBS"
command -v ccache >/dev/null && [ -n "${CCACHE_DIR:-}" ] && ccache -s || true
echo "::endgroup::"

scripts/package-release.sh
