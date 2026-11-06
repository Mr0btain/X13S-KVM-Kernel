# Boot log

## 2026-11-06 #1: 7.3.1-el2 + qebspil (always-start) + x13s-el2-dsp dtb — WORKS

Path: F12 "Ubuntu (EL2 KVM)" -> shell -> qebspil + slbounce -> grubel2 ->
"Linux 7.3.1-el2 (EL2 / KVM + DSPs)".

| Check | Result |
|---|---|
| EL2 / KVM | `CPU: All CPU(s) started at EL2`, `VHE mode initialized`, `/dev/kvm` ok |
| DSPs | slpi, adsp, cdsp `attached` (`pas_avail=1 scm_avail=1 in_el2=1 el2_pas_capable=0 use_pas=0 broken_reset=1`) |
| Battery | `qcom-battmgr-bat`: Discharging, 100 %, 42.4 Wh, -9.1 W, 8.38 V; upower sees battery + AC/USB/UCSI supplies |
| USB-C / UCSI | `/sys/class/typec/port0`, `port1`; pmic_glink altmode + ucsi_glink loaded |
| Audio | card SC8280XP-LENOVO-X13S; PipeWire: speaker, headphones, internal + headset mics. One `qcom-apm ... CMD timeout [1001021]` at boot. Playback not tested yet |
| Wi-Fi | ath11k, connected |
| Bluetooth | powered |
| WWAN | `wwan0mbim0` present |

Problems this boot:
- **Second USB-C controller down:** `qcom-qmp-combo-phy 8903000.phy: phy initialization timed-out`
  -> `dwc3 a800000.usb: ... -ETIMEDOUT`, plus clk "already disabled" WARNINGs
  (`gcc_usb3_sec_phy_pipe_clk`). Also seen once on stock 7.0 at EL1 (boot -2),
  so intermittent and probably not EL2-related. Track across boots.
- **iris (video codec) `-22`** x14: PAS firmware load, same root cause as before.
  7.3 uses iris (not venus) for sc8280xp. jglathe `524c3da` "media: iris: Port
  firmware loading without TZ/PAS from venus" is the candidate fix (Phase 6).
- `qcom_qseecom -22`: no EFI variables at EL2 (expected, Phase 6).
- `bpf-restrict-fs: Failed to load BPF object`: systemd's RestrictFileSystems
  needs BTF; we built with `DEBUG_INFO_NONE`. Fix: rebuild with
  `DEBUG_INFO_DWARF5` + `DEBUG_INFO_BTF` (needs `dwarves`/pahole).

### Follow-up tests, same kernel (2026-11-06, boot at 13:49)
- **Sound**: works (user test). **Emulator `-accel on`**: works (user test).
- **Charger**: plug/unplug on both USB-C ports detected; `qcom-battmgr-usb`
  online 0->1, status Discharging -> Charging -> "Not charging" (battery at
  100 %, expected), UCSI shows the correct port (`ucsi=01` / `10`). Charging
  power goes through even on the port whose dwc3 failed (PD is PMIC/ADSP).
- **Suspend: hard reset.** Two EL2 boots (-3, -1): last persisted line is
  `kernel: PM: suspend entry (s2idle)`, then the machine resets into the
  normal boot entry. Not yet tested: stock 7.0 at EL2, 7.3.1-el2 at EL1.
  Runtime per-CPU deep idle (`cpu-sleep-0-0`, ~37k entries) is fine; PSCI is
  identical at EL1/EL2 (OSI mode, "failed to set PC mode: -3" in both).
  Bisect with `scripts/suspend-test.sh` -> `notes/suspend-tests.log`.
