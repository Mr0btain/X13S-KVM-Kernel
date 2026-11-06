#!/usr/bin/env bash
# Download a GitHub release of this repo into out/ (the layout the install
# scripts use), verifying SHA256SUMS. Then, from the normal (EL1) boot:
#   sudo scripts/el2-install.sh     (needs out/el2/tcblaunch.exe, see notes/slbounce-el2.md)
#   sudo scripts/install-esp.sh
#   sudo scripts/install-kernel.sh
# Usage: scripts/download-release.sh <tag> [owner/repo]   (repo default: git remote origin)
set -euo pipefail
TOP="$(cd "$(dirname "$0")/.." && pwd)"
tag="${1:?usage: download-release.sh <tag> [owner/repo]}"
repo="${2:-$(git -C "$TOP" remote get-url origin | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')}"
base="${RELEASE_BASE_URL:-https://github.com/$repo/releases/download/$tag}"
dl="$TOP/out/download/$tag"
mkdir -p "$dl"
curl -fsSL -o "$dl/SHA256SUMS" "$base/SHA256SUMS"
awk '{print $2}' "$dl/SHA256SUMS" | while read -r f; do
  echo "get   $f"; curl -fsSL -o "$dl/$f" "$base/$f"
done
(cd "$dl" && sha256sum -c SHA256SUMS)
mkdir -p "$TOP/out/qebspil" "$TOP/out/slbounce"
cp "$dl"/linux-*.deb "$TOP/out/"
cp "$dl"/qebspilaa64*.efi "$TOP/out/qebspil/"
cp "$dl"/slbounce.efi "$dl"/sltest.efi "$TOP/out/slbounce/"
echo "installed $tag assets into out/"
