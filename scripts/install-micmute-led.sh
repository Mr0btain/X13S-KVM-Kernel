#!/usr/bin/env bash
# Make the X13s F4 (mic-mute) LED follow the PipeWire microphone mute.
#   - /usr/local/bin/x13s-micmute-led          (scripts/x13s-micmute-led)
#   - /etc/systemd/user/x13s-micmute-led.service (enabled for all users)
#   - /etc/udev/rules.d/90-x13s-micmute-led.rules: trigger "none" and a
#     user-writable brightness on platform::micmute
# Only does anything when the lenovo-thinkpad-x13s EC driver has registered
# the LED (EL2 boot with the EC overlay); elsewhere the service is skipped.
# Needs root. --remove undoes all of it.
set -euo pipefail
TOP="$(cd "$(dirname "$0")/.." && pwd)"
BIN=/usr/local/bin/x13s-micmute-led
UNIT=/etc/systemd/user/x13s-micmute-led.service
RULE=/etc/udev/rules.d/90-x13s-micmute-led.rules
LED=/sys/class/leds/platform::micmute

[ "$(id -u)" = 0 ] || { echo "run with sudo" >&2; exit 1; }

user_systemctl() {
	# Act on the invoking user's running session too, if there is one.
	[ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ] || return 0
	systemctl --user -M "$SUDO_USER@" "$@" 2>/dev/null || true
}

if [ "${1:-}" = "--remove" ]; then
	user_systemctl stop x13s-micmute-led.service
	systemctl --global disable x13s-micmute-led.service 2>/dev/null || true
	rm -f "$BIN" "$UNIT" "$RULE"
	udevadm control --reload
	if [ -e "$LED" ]; then
		echo 0 > "$LED/brightness"
		chmod 0644 "$LED/brightness"
		echo audio-micmute > "$LED/trigger"
	fi
	user_systemctl daemon-reload
	echo "removed"
	exit 0
fi

install -m 0755 "$TOP/scripts/x13s-micmute-led" "$BIN"

cat > "$RULE" <<'EOF'
# X13s F4 mic-mute LED: driven from userspace by x13s-micmute-led (the
# audio-micmute trigger never fires on this machine). Installed by
# kernel-work scripts/install-micmute-led.sh.
ACTION=="add", SUBSYSTEM=="leds", KERNEL=="platform::micmute", ATTR{trigger}="none", RUN+="/bin/chmod 0666 /sys%p/brightness"
EOF

cat > "$UNIT" <<'EOF'
[Unit]
Description=Mirror microphone mute onto the ThinkPad X13s F4 LED
ConditionPathExists=/sys/class/leds/platform::micmute
After=wireplumber.service pipewire.service

[Service]
ExecStart=/usr/local/bin/x13s-micmute-led
Restart=always
RestartSec=3

[Install]
WantedBy=default.target
EOF

udevadm control --reload
if [ -e "$LED" ]; then udevadm trigger --action=add "$LED"; fi
systemctl --global enable x13s-micmute-led.service
user_systemctl daemon-reload
user_systemctl restart x13s-micmute-led.service

echo "installed. LED: $(ls -l "$LED/brightness" 2>/dev/null || echo 'not present (not an EL2 boot with the EC driver?)')"
if [ -n "${SUDO_USER:-}" ]; then
	echo "service: $(systemctl --user -M "$SUDO_USER@" is-active x13s-micmute-led.service 2>/dev/null || echo unknown)"
fi
