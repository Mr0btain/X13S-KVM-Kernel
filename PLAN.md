# EL2 (KVM) kernel with working DSPs for the ThinkPad X13s

## Status

| Phase | State |
|---|---|
| 0 Repo + baseline | done (baseline = AndroidEmulator EL2 boot logs) |
| 1 qebspil smoke test (stock kernel) | skipped: went straight to Phase 4 |
| 2 Kernel source + takeover patches | done: **base switched to mainline v7.3.1**; all 11 patches apply cleanly (`scripts/apply-patches.sh`) |
| 3 Build `-el2` kernel | done: `out/linux-image-7.3.1-el2_7.3.1-1el2_arm64.deb` (+ headers); ~65 min full build |
| 4 Boot integration | **done 2026-11-06**: EL2 entry boots 7.3.1-el2, DSPs attached |
| 5 Test checklist | in progress: see `notes/boot-log.md` |
| 6 Leftovers (venus, EFI vars) | optional |

Goal: a kernel and boot path where the "Ubuntu (EL2 KVM)" entry has **KVM and**
battery, charging, USB-C, audio and the rest, so the EL2 entry can become the
daily boot. The normal (EL1) entry stays untouched as the fallback.

Builds on `../AndroidEmulator` Phase 6 (slbounce, `scripts/el2-install.sh`,
`notes/phase6-kvm.md`).

## What breaks at EL2 today (journal, EL2 boot `-b -11`, kernel 7.0.0-42)

| Symptom | Cause |
|---|---|
| No battery / AC / USB power supplies (`/sys/class/power_supply` empty) | ADSP not running; battery info comes from ADSP firmware via `pmic_glink` / `qcom_battmgr` |
| No USB-C orientation, DP alt mode, UCSI | same: `pmic_glink` altmode/ucsi are served by ADSP |
| No sound (`snd-sc8280xp: WCD Playback: error getting cpu dai name`) | audio DSP = ADSP |
| SLPI (sensors), CDSP (compute) down | same failure |
| `qcom_q6v5_pas ...: error -22 initializing firmware` for adsp/cdsp/slpi | PAS `auth_and_reset` SCM call refused: normally Qualcomm's hypervisor (QHEE/Gunyah) sets up the DSPs' SMMU and memory; at EL2 there's no hypervisor |
| `qcom-venus ...: error -22 initializing firmware qcvss8280.mbn` | same PAS failure for the video codec, so no HW video decode |
| `qcom_qseecom: probe ... failed with error -22` | uefisecapp unavailable: **no EFI variables from Linux at EL2** (`efibootmgr` won't work there; run `el2-install.sh` from the normal boot) |

Working at EL2: GPU (no zap shader, `SECVID_TRUST_CNTL` instead), display, USB
host, Bluetooth, PCIe (with `pcie_smmu` from the -el2 dtb), KVM (VHE).
Wi-Fi: not checked, so check it in Phase 0.

## Research summary (2026-11-06)

There are two ways to get the DSPs running without Qualcomm's hypervisor.

**A. Start the DSPs from UEFI, then Linux attaches. (chosen)**
- [qebspil](https://github.com/stephan-gh/qebspil) (Stephan Gerhold) is a UEFI
  driver that boots the remoteprocs via PIL just before `ExitBootServices()`,
  while the firmware/hypervisor environment can still do it. SC8280XP is
  listed as supported; its README uses the X13s (`LENOVO/21BX`) as the example.
  - Build: `git submodule update --init --recursive && make` (native gcc;
    upstream docs cross-compile) -> `out/qebspilaa64.efi`.
  - Load from the UEFI shell: `load qebspilaa64.efi`. It only acts when the
    bootloader installs a DT, which our `grubel2.efi` does (`devicetree`).
  - Firmware is read from the **same ESP**: `\firmware\qcom\sc8280xp\LENOVO\21BX\`
    `qcadsp8280.mbn`, `qccdsp8280.mbn`, `qcslpi8280.mbn` (uncompressed. Ours
    are `.mbn.zst` in `/lib/firmware`). ESP has 992 MB free.
  - By default it only starts remoteprocs whose DT node has `qcom,broken-reset`.
    Build with `QEBSPIL_ALWAYS_START=1` to start all enabled ones, or add the
    property in our dtb.
- The kernel then needs the **takeover/attach patches** (not upstream yet). The
  original branches (`codelinaro stephan.gerhold/linux wip/qcom-laptops-6.17-el2`)
  are gone. A maintained copy is in
  [jglathe/linux_ms_dev_kit](https://github.com/jglathe/linux_ms_dev_kit),
  branch `jg/rproc_nohyp_attach` (7.3-rc based, X1E-focused):
  - `07678bb` remoteproc: core: Allow restarting detached remoteprocs with new firmware
  - `fa7a100` remoteproc: qcom_q6v5: Allow detecting detached state during boot
  - `27c7f8a` remoteproc: qcom_q6v5: Add qcom_q6v5_attach()
  - `9e265b7` remoteproc: qcom_q6v5_pas: Add pure-attach path when PAS/SCM unavailable
  - `437da4d` wip: remoteproc: qcom_q6v5_pas: Avoid using broken reset when running bare-metal
  - `8b1a294` remoteproc: qcom_q6v5_pas: add debug for the pas_available check
  - `77d29e5` remoteproc: qcom_q6v5_pas: limit PAS use at EL2 to capable platforms
  - `b1482e1` remoteproc: qcom_q6v5_pas: set RPROC_DETACHED for non-PAS path
  - `a607ff5`, `27ffd5b` rpmsg: core fixes; `1efd5ae` net: qrtr: smd race fix
  - `524c3da` media: iris: Port firmware loading without TZ/PAS from venus (X1E, not needed: we use venus)
  - Reported (qebspil issue #2, X1P): with these patches, "remoteprocN: attached",
    sound works, no `-22`. Nobody has reported SC8280XP yet, so we'd be first.
- Expected limits: a DSP that crashes can't be restarted (no PAS at EL2),
  so recovery means a reboot. Suspend/resume with attached DSPs is untested.

**B. Linux owns the DSP IOMMU (upstream "PIL at EL2" series, Mukesh Ojha, v10).**
- Already in our 7.0 kernel (`qcom_q6v5_pas.ko` has `qcom_scm_pas_get_rsc_table`,
  `qcom_scm_pas_prepare_and_auth_reset`). It turns on when the remoteproc node
  has `iommus`. The X13s -el2 dtb has none (upstream `sc8280xp-el2.dtso` only
  touches the GPU zap shader and the PCIe SMMU).
- It was built for SA8775P/Lemans, where TrustZone supports it; X1E got
  `iommus` in its EL2 dts in 2026. On SC8280XP, TZ may not support the
  "no-QHEE" PAS calls (`77d29e5` exists because some platforms can't). We'd
  also need the DSP stream IDs. Use this as a **cheap side experiment**
  (DT-only, no kernel build), not the main path.

## Ground rules (same as AndroidEmulator)

- Plain git. `src/` and `out/` are git-ignored; this repo tracks scripts,
  patches, notes and dts overlays.
- Patches live in `patches/linux/NNNN-*.patch` (and `patches/qebspil/` if
  needed), applied by `scripts/apply-patches.sh`.
- **Never touch the normal boot path.** Only `\EFI\slbounce\` on the ESP,
  `/boot/grub/el2.cfg` and `/boot/el2/` change. The normal Ubuntu entry and
  stock `-generic` kernels stay the default and the fallback.
- EFI variable changes (`efibootmgr`) only from the normal EL1 boot.
- Every hardware boot test gets a line in `notes/boot-log.md` with the date,
  kernel, what loaded, and the result.

## Repo layout

```
PLAN.md
scripts/
  fetch-sources.sh     clone Ubuntu kernel tag + qebspil into src/
  apply-patches.sh     apply patches/ onto src/
  build-kernel.sh      config + bindeb-pkg -> out/*.deb
  build-qebspil.sh     -> out/qebspilaa64.efi
  install-esp.sh       qebspil + DSP firmware onto ESP, update startup.nsh
dts/                   x13s EL2 dtb overlay(s) (broken-reset / iommus experiments)
patches/linux/         backported takeover patches
notes/                 findings, boot-log.md
src/  (ignored)        linux (Ubuntu-7.0.0-43.43), qebspil, linux_ms_dev_kit (sparse)
out/  (ignored)        debs, efi binaries, logs
```

---

## Phase 0: Repo and baseline

1. `git init`, `.gitignore` (`src/ out/ *.log`).
2. Install the kernel build deps:
   `sudo apt install libelf-dev libdw-dev dwarves debhelper-compat rsync cpio kmod zstd libncurses-dev device-tree-compiler`
   (`gcc make bison flex bc libssl-dev` are already installed).
3. Record the baseline at EL1 and at EL2 (current stock kernel) in `notes/baseline.md`:
   `ls /sys/class/power_supply`, `upower -d`, `cat /sys/class/remoteproc/*/{name,state}`,
   `aplay -l`, `ls /sys/class/typec`, `ip link`/`nmcli` (Wi-Fi), `bluetoothctl show`,
   `ls /sys/firmware/efi/efivars | wc -l`, `dmesg | grep -iE "error|fail"`.

**Done when:** the repo exists and we have a list of what works at EL2 and what doesn't.

## Phase 1: qebspil smoke test with the stock kernel (no kernel build yet)

This tells us whether qebspil + slbounce can bring up the DSPs on this machine
at all, before we spend hours on kernel work.

1. Clone + build qebspil natively. Build two variants: default, and `QEBSPIL_ALWAYS_START=1`.
2. Copy the DSP firmware, decompressed, to the ESP:
   `\firmware\qcom\sc8280xp\LENOVO\21BX\{qcadsp,qccdsp,qcslpi}8280.mbn`.
3. Copy `qebspilaa64.efi` to `\EFI\slbounce\` and edit `startup.nsh` so it does
   `load qebspilaa64.efi` before `load slbounce.efi` (`scripts/install-esp.sh`).
   Load order doesn't matter: qebspil runs as an ExitBootServices event
   callback (TPL_CALLBACK-1) *inside* the real ExitBootServices(); slbounce
   replaces `BS->ExitBootServices` and switches to EL2 only after the real
   call returns (`slbounce/src/bounce_main.c`).
   The X13s dtb has no `qcom,broken-reset`, so the smoke test uses the
   `QEBSPIL_ALWAYS_START=1` build (`out/qebspil/qebspilaa64-always.efi`).
4. Boot the EL2 entry with the stock `7.0.0-43` kernel. Expected: the UEFI shell
   shows qebspil output. Linux then still tries PAS and fails (no attach
   patches), but the DSP state (`/sys/class/remoteproc/*/state`, `dmesg`)
   shows whether they were running. Battery may even show up briefly.
5. If slbounce or qebspil hangs: power off. The normal entry is unaffected,
   and from it, revert `startup.nsh`.

**Done when:** we know whether qebspil starts ADSP/CDSP/SLPI under the slbounce
chain (photo of the shell output + dmesg in `notes/boot-log.md`).

## Phase 2: Kernel source + takeover patches

> **2026-11-06 decision: base = mainline stable v7.3.1, not Ubuntu 7.0.** The
> patches sit on the new generic PAS layer (`linux/firmware/qcom/qcom_pas.h`,
> `qcom_pas_is_available()`, 7.2/7.3 era); in Ubuntu 7.0 `qcom_q6v5_pas.c` is
> ~500 lines different, so a backport would mean porting that refactor too.
> On v7.3.1 all 11 apply with no changes. Config = Ubuntu's `/boot/config-*`
> + olddefconfig (`scripts/build-kernel.sh`). `src/linux` (Ubuntu 7.0) is
> kept only for reference. Steps 1–3 below describe the original 7.0 plan.
>
> Probe logic after the patches (`qcom_q6v5_pas.c`): at EL2 on a platform not
> in `el2_pas_capable_compats` (X13s isn't), `use_pas=0`; with
> `qcom,broken-reset` it reads the SMP2P state and registers the rproc as
> `RPROC_DETACHED` (attach-only ops); without it the probe **defers forever**.
> At EL1 the normal PAS path is used, so one kernel serves both entries.
> Compile check: only `-Wenum-conversion` warnings in imx/xlnx rproc
> (bool -> enum, same values; irrelevant here).

1. Source: Ubuntu's tree for the running kernel, shallow:
   `git clone --depth 1 -b Ubuntu-7.0.0-43.43 https://git.launchpad.net/~ubuntu-kernel/ubuntu/+source/linux/+git/resolute src/linux`.
   Same base as the running kernel, so Ubuntu config, firmware paths and
   userspace all match.
2. Fetch only the patch commits: shallow `git fetch` of `jg/rproc_nohyp_attach`
   from `jglathe/linux_ms_dev_kit` into a separate checkout, then
   `git format-patch -1 <sha>` for each commit listed above. Read each commit
   message: they say which DT properties (`qcom,broken-reset`, `firmware-name`)
   and which conditions trigger the attach path.
3. Backport onto 7.0: `git am -3`, fix conflicts (the base is 7.3-rc, so
   expect remoteproc/smp2p churn; the issue #2 author hit one conflict on
   next-20260626). Pull in any prerequisite commit they depend on
   (e.g. `qcom_q6v5_read_smp2p_state()`). Save to `patches/linux/`.
4. Check the SC8280XP specifics: `77d29e5` gates PAS by platform. Make sure
   `sc8280xp-{adsp,nsp0,slpi}-pas` take the attach path at EL2 and keep the
   normal PAS path at EL1. **The same kernel must boot both ways** (it's
   handy, and it proves EL1 hasn't regressed).
5. DT: **required.** The attach-only path (0007/0010) only turns on when the
   node has `qcom,broken-reset` (and the machine isn't on the EL2-PAS-capable
   list). `dts/x13s-el2-dsp.dtso` adds it to slpi/adsp/cdsp;
   `scripts/build-dtb.sh [base.dtb]` -> `out/dtb/sc8280xp-lenovo-thinkpad-x13s-el2-dsp.dtb`.
   With this dtb the default (non-"always") qebspil build is enough too.

**Done when:** the patches apply cleanly via `scripts/apply-patches.sh` and the tree builds `drivers/remoteproc/`.

## Phase 3: Build the `-el2` kernel

1. Config = `/boot/config-$(uname -r)`, `LOCALVERSION=-el2`, then
   `make olddefconfig`. Turn off `DEBUG_INFO_BTF` only if `pahole` causes
   trouble. Turn off module signing / `SYSTEM_TRUSTED_KEYS`
   (Secure Boot is already off).
2. `make -j6 bindeb-pkg` (14 GB RAM; watch for OOM, add swap if needed)
   -> `out/linux-image-7.3.1-el2_*.deb`, `linux-headers-*`.
   Packaging needs `sudo apt install debhelper libdw-dev libelf-dev`.
   Expect about 1.5–3 h with ccache off. Rebuilds use `make -j6` + reinstall.
3. Build dtbs from the same tree (`make dtbs`) so the -el2 dtb matches the kernel.

Build gotchas (2026-11-06):
- `CONFIG_BUILTIN_MODULE_RANGES` needs `gawk` (not installed): disabled.
- Release came out `7.3.1-el2+` (commits on top of the tag): build with
  `LOCALVERSION=` so it's `7.3.1-el2`.
- `bindeb-pkg` failed in `dtbs_install` (parallel `install -D` race):
  patch 0012 (`.NOTPARALLEL: __dtbs_install`, from the same jglathe branch).
- `out/linux-libc-dev_*.deb` is a by-product. **Don't install it**
  (`install-kernel.sh` only takes image + headers).
- `CONFIG_EFI_ZBOOT=y`: vmlinuz is a compressed EFI PE, booted by GRUB; it
  keeps the dtb GRUB installs (no stubble swap like Ubuntu's image).

**Done when:** the debs exist and `dpkg -c` shows the Image, modules and dtbs.

## Phase 4: Boot integration

1. `sudo dpkg -i` the image + headers (DKMS modules, if any, rebuild).
2. **Keep stock as the normal default.** Our kernel sorts as "newer" than
   `7.0.0-43-generic`, so set `GRUB_FLAVOUR_ORDER=generic` in
   `/etc/default/grub.d/` (or `GRUB_DEFAULT` to the stock entry) and check
   `update-grub` output.
3. `scripts/el2-grubcfg.sh` (replaces AndroidEmulator's hook via `scripts/install-kernel.sh`):
   prefer the newest `*-el2` kernel, fall back to `-generic`. Our kernel is a
   plain Image, not a stubble PE, so no `.linux` extraction needed (keep it
   for the fallback). Use the dtb from Phase 2.5. Also add a second menu
   entry for the stock kernel at EL2 (the current behaviour) as a fallback.
4. Make `startup.nsh` load qebspil (Phase 1 order) and copy the firmware.
   Fold this into `scripts/install-esp.sh` / `el2-install.sh --remove`.

**Done when:** F12 → "Ubuntu (EL2 KVM)" boots `7.0.x-el2` at EL2 and the normal entry still boots stock at EL1.

## Phase 5: Test checklist (EL2 boot, record in notes/boot-log.md)

- [x] `CPU: All CPU(s) started at EL2`, `/dev/kvm` + AVD `-accel on` (user-tested)
- [x] `remoteproc*: attached` / state `attached` or `running` for adsp, cdsp, slpi
- [x] Battery % + charging state (both ports) (`upower -d`, GNOME indicator); AC plug/unplug events
- [ ] USB-C: both ports (2nd port's PHY timed out on boot #1, see boot-log), both orientations, USB3 speed; DP alt mode to a monitor
- [x] Audio (user-tested): speakers, headphone jack, internal mics (`alsaucm`, pipewire)
- [x] Wi-Fi + Bluetooth
- [x] Suspend/resume (s2idle): works **without cluster idle** (dtb `domain-idle-states` removed from the cluster PD; cluster collapse resets at EL2). DSPs survive. [ ] repeat x3 via normal `systemctl suspend` with the modem present; [ ] measure overnight drain: DSPs still alive afterwards, battery still updating
- [ ] Lid close, brightness, keyboard backlight, thermals (`sensors`), fan
- [ ] Uptime soak: a day of normal use + an emulator session, no DSP crashes
- [ ] Same kernel at EL1 (normal entry, if installed there): no regressions

**Done when:** every box is ticked, or the item is written up as a known limitation.

## Phase 6 (optional): Leftovers

- **Venus (HW video decode):** venus has a non-TZ firmware-load path (the
  `video-firmware` subnode with `iommus`). Check whether it works on
  sc8280xp at EL2 with a DT change. Low priority: software decode works.
- **EFI variables (qseecom/uefisecapp `-22`):** cosmetic for daily use but
  `efibootmgr`/fwupd won't work at EL2. Look into whether newer kernels or
  the X1E EL2 work solved it. Otherwise document "do EFI changes from EL1".
- **Side experiment B:** add `iommus` (DSP stream IDs, from ACPI IORT dump
  `acpidump`/Windows DSDT or the downstream dts) to the remoteproc nodes and
  see if TZ accepts the Linux-managed PAS path. If it does, qebspil isn't needed.
- Send results upstream / to qebspil issue tracker (first SC8280XP report).

## Risks / open questions

- **Cluster power collapse is off at EL2** (it resets on s2idle). Costs some
  idle/suspend power. A real fix would need the warm-boot path to return
  to Linux without the Qualcomm hypervisor; worth asking upstream/slbounce.
- WWAN modem (T99W175/X55, PCIe 0004) drops its link across suspend
  (pciehp unplug/replug, `pci_disable_device` WARNING, `mhi_pci_suspend` -16
  if suspended again too soon).
- 2nd USB-C PHY times out on some boots (seen at EL1 too).

- ~~Ordering of qebspil vs slbounce~~: resolved, see Phase 1.3.
- The patches target 7.3-rc + X1E, so backporting to 7.0 may drag in
  dependencies. Fallback: build Ubuntu's `7.1`/mainline instead, but the
  phase6 notes say the upstream -el2 dtb remoteproc `iommus` hang 7.1+
  kernels (seen on X1E, check sc8280xp).
- A DSP crash means no recovery without a reboot (no PAS restart at EL2).
- Charging is done by PMIC hardware even without ADSP, so the risk today is
  only in what we can *see*, not battery safety. Still, don't leave the EL2
  boot running flat out on battery without a reading.
- Kernel updates: Ubuntu updates won't rebase our kernel. Re-run Phases 2–3 per
  Ubuntu tag, or pin `7.0.x-el2` until the patches land upstream.

## Sources

- qebspil: https://github.com/stephan-gh/qebspil (README, issue #2)
- Takeover patches: https://github.com/jglathe/linux_ms_dev_kit/commits/jg/rproc_nohyp_attach
- Upstream PIL-at-EL2 series v10: https://ratatoskr.run/lkml/2026/01/3352912/t
- Earlier version: https://patchew.org/linux/20251121-kvm._5Frproc._5Fv8-v8-0-8e8e9fb0eca0@oss.qualcomm.com/
- Upstream overlay: arch/arm64/boot/dts/qcom/sc8280xp-el2.dtso (GPU zap + PCIe SMMU only)
- Ubuntu kernel git: https://git.launchpad.net/~ubuntu-kernel/ubuntu/+source/linux/+git/resolute (tag Ubuntu-7.0.0-43.43)
- Phase 6 notes: ../AndroidEmulator/notes/phase6-kvm.md
