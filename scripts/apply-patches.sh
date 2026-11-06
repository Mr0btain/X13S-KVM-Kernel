#!/usr/bin/env bash
# Apply patches/linux/*.patch onto $LINUX_DIR as commits on branch "el2"
# (recreated from LINUX_TAG each run). Paths/tag come from sources.env.
set -euo pipefail
TOP="$(cd "$(dirname "$0")/.." && pwd)"
. "$TOP/sources.env"
SRC="${SRC:-$TOP/$LINUX_DIR}"
BASE="${BASE:-$LINUX_TAG}"
cd "$SRC"
git -c advice.detachedHead=false checkout -q "$BASE" 2>/dev/null || git checkout -q "$(git rev-list --max-parents=0 HEAD | tail -1)"
git checkout -q -B el2
git -c user.name="${GIT_AUTHOR_NAME:-kernel-work}" -c user.email="${GIT_AUTHOR_EMAIL:-kernel-work@localhost}" \
  am -q --committer-date-is-author-date "$TOP"/patches/linux/*.patch
git log --oneline "$BASE"..el2 2>/dev/null || git log --oneline -n "$(ls "$TOP"/patches/linux/*.patch | wc -l)"
