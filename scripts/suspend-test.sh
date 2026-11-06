#!/usr/bin/env bash
# Bisect the EL2 suspend reset, one level per run (a reset ends the run).
#   sudo scripts/suspend-test.sh freezer    freeze tasks only, resume after 5 s
#   sudo scripts/suspend-test.sh devices    + suspend all drivers, resume after 5 s
#   sudo scripts/suspend-test.sh platform   + platform/genpd suspend hooks, resume after 5 s
#   sudo scripts/suspend-test.sh shallow    real s2idle, CPU deep idle disabled (WFI only)
#   sudo scripts/suspend-test.sh full       real s2idle (what crashes today)
# For shallow/full, wake with the power button / a key / opening the lid.
# Results append to notes/suspend-tests.log (synced before suspending).
set -uo pipefail
TOP="$(cd "$(dirname "$0")/.." && pwd)"
LOG="$TOP/notes/suspend-tests.log"
lvl="${1:?level: freezer|devices|platform|shallow|full}"
[ "$(id -u)" = 0 ] || { echo "run with sudo" >&2; exit 1; }

{ echo; echo "== $(date -Is) $(uname -r) level=$lvl el2=$(journalctl -k -b0 -o cat | grep -c 'started at EL2')"; } >> "$LOG"
echo "STARTED (if this is the last line for this run, the machine reset)" >> "$LOG"
sync

restore_idle() { for d in /sys/devices/system/cpu/cpu*/cpuidle/state[1-9]*/disable; do echo 0 > "$d"; done; }
case "$lvl" in
  freezer|devices|platform) echo "$lvl" > /sys/power/pm_test ;;
  shallow) echo none > /sys/power/pm_test
           for d in /sys/devices/system/cpu/cpu*/cpuidle/state[1-9]*/disable; do echo 1 > "$d"; done ;;
  full)    echo none > /sys/power/pm_test ;;
  *) echo "bad level" >&2; exit 1 ;;
esac
sync; sleep 1

t0=$(date +%s)
echo mem > /sys/power/state; rc=$?
t1=$(date +%s)
echo none > /sys/power/pm_test
[ "$lvl" = shallow ] && restore_idle

{ echo "RESUMED rc=$rc after $((t1 - t0)) s"
  journalctl -k -b0 -o cat --since "@$t0" | grep -E "PM:|suspend|resume|error|fail|timeout|remoteproc|glink|WARNING" | head -40
} >> "$LOG"
sync
tail -n 45 "$LOG"
