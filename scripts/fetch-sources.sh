#!/usr/bin/env bash
# Fetch the pinned sources from sources.env into src/:
#   $LINUX_DIR        shallow clone of LINUX_TAG
#   src/qebspil       at QEBSPIL_REV (+ submodules)
#   src/slbounce      at SLBOUNCE_REV (+ submodules)
# Idempotent: existing checkouts are moved to the pinned revision.
set -euo pipefail
TOP="$(cd "$(dirname "$0")/.." && pwd)"
. "$TOP/sources.env"
mkdir -p "$TOP/src"

linux="$TOP/$LINUX_DIR"
if [ ! -d "$linux/.git" ]; then
  git -c advice.detachedHead=false clone -q --depth 1 -b "$LINUX_TAG" "$LINUX_URL" "$linux"
elif ! git -C "$linux" rev-parse -q --verify "refs/tags/$LINUX_TAG" >/dev/null; then
  git -C "$linux" fetch -q --depth 1 origin tag "$LINUX_TAG"
fi
echo "ok    linux $LINUX_TAG -> $linux"

fetch_rev() {  # <dir> <url> <rev>
  local dir="$1" url="$2" rev="$3"
  [ -d "$dir/.git" ] || git clone -q "$url" "$dir"
  git -C "$dir" cat-file -e "$rev^{commit}" 2>/dev/null || git -C "$dir" fetch -q origin
  git -C "$dir" -c advice.detachedHead=false checkout -q --force "$rev"
  git -C "$dir" submodule update -q --init --recursive
  echo "ok    $(basename "$dir") $(git -C "$dir" rev-parse --short HEAD)"
}
fetch_rev "$TOP/src/qebspil"  "$QEBSPIL_URL"  "$QEBSPIL_REV"
fetch_rev "$TOP/src/slbounce" "$SLBOUNCE_URL" "$SLBOUNCE_REV"
