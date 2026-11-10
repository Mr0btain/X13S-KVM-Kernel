# X13s EL2 kernel: KVM with battery, audio and suspend

Boots the **Lenovo ThinkPad X13s** (Snapdragon 8cx Gen 3 / SC8280XP) Linux at
**EL2**, so `/dev/kvm` works (e.g. for the Android Emulator with `-accel on`).
The usual cost of doing that is avoided: battery, charging, USB-C, audio and
suspend all keep working.

Normally Qualcomm's hypervisor owns EL2. slbounce takes it over, but that also
removes what boots the DSPs, and the battery/charger (ADSP via `pmic_glink`),
audio, USB-C altmode and sensors go with them. This repo puts it back:

| Piece | What it does |
|---|---|
| [slbounce](https://github.com/TravMurav/slbounce) | switches to EL2 at ExitBootServices (needs Windows' `tcblaunch.exe`) |
| [qebspil](https://github.com/stephan-gh/qebspil) | UEFI driver that boots ADSP/CDSP/SLPI just before that switch |
| `patches/linux/` on stable **v7.3.1** | lets Linux *attach* to the already-running DSPs at EL2 instead of trying (and failing) to boot them |
| `dts/x13s-el2-dsp.dtso` | marks the DSPs `qcom,broken-reset` (selects the attach path); enables the embedded controller on i2c8 |
| `scripts/el2-grubcfg.sh` | also drops the cluster idle state from the EL2 dtb (entering it in s2idle reset the machine at EL2) |

The normal boot entry is never changed. EL2 is a separate firmware boot entry,
"Ubuntu (EL2 KVM)", picked from the F12 menu, so the stock setup stays as the
fallback.

## Status (Ubuntu 26.04, BIOS N3HET88W 1.60)

Works at EL2: KVM (VHE), all DSPs attached, battery % and charging on both
USB-C ports, UCSI, speakers/headphones/mics, Wi-Fi, Bluetooth, the 5G modem,
s2idle suspend/resume, GPU/display, the Android Emulator with `-accel on`.

Known issues:

- No hardware video decode: iris firmware load fails (`-22`). The fix is
  still to do.
- No EFI variable access at EL2 (`qseecom -22`). Run `efibootmgr` / these
  install scripts from the normal boot.
- No cluster power collapse at EL2, so idle and suspend drain is somewhat
  higher than at EL1.
- The 2nd USB-C port's PHY sometimes times out at boot. This has also been
  seen at EL1.
- A crashed DSP can't be restarted at EL2. Reboot to recover.

Full test log: `notes/boot-log.md`. Plan and reasoning: `PLAN.md`.

## Install from a release

From the **normal** boot, with Secure Boot disabled:

```sh
sudo apt install efi-shell-aa64 grub-efi-arm64-bin device-tree-compiler efibootmgr
git clone <this repo> && cd <repo>
scripts/download-release.sh <tag>          # e.g. v7.3.1-el2-1 -> out/
```

`tcblaunch.exe` is a Microsoft binary, so it can't be redistributed. Get the
arm64 build **10.0.22621.4317** (tested on the X13s) as described in
`notes/slbounce-el2.md` (Microsoft symbol server or a Windows 11 arm64 ISO) and
put it at `out/el2/tcblaunch.exe`. Then run:

```sh
sudo scripts/el2-install.sh     # slbounce + UEFI shell + "Ubuntu (EL2 KVM)" boot entry
sudo scripts/install-esp.sh     # qebspil + DSP firmware on the ESP
sudo scripts/install-kernel.sh  # kernel debs, DSP dtb, EL2 GRUB menu
sudo scripts/install-micmute-led.sh  # optional: F4 LED follows mic mute (EL2, EC driver)
```

Reboot, press **F12**, choose **Ubuntu (EL2 KVM)**, then
"Linux 7.3.1-el2 (EL2 / KVM + DSPs)". The second entry boots the stock
Ubuntu kernel at EL2 (KVM only, no DSPs).

Check it worked:

```sh
dmesg | grep -E "started at EL2|remoteproc.*attached"
cat /sys/class/remoteproc/*/state       # attached x3
ls /dev/kvm; upower -d | grep percentage
```

Undo: `sudo scripts/install-kernel.sh --remove`, `sudo scripts/install-esp.sh --remove`,
`sudo scripts/el2-install.sh --remove`, `sudo scripts/install-micmute-led.sh --remove`.

## Build from source

On arm64 Ubuntu 26.04 (≈ 8 GB kernel tree, ~65 min on 8 cores):

```sh
scripts/ci-build.sh            # apt packages + everything below (SKIP_APT=1 to skip apt)
# or step by step:
scripts/fetch-sources.sh       # pinned in sources.env: linux v7.3.1, qebspil, slbounce
scripts/apply-patches.sh       # patches/linux -> branch "el2" in src/linux-7.3
scripts/build-efi.sh           # out/qebspil/*.efi, out/slbounce/*.efi
scripts/build-kernel.sh -j8    # out/linux-image-7.3.1-el2_*.deb (+ headers)
scripts/package-release.sh     # out/release/ + SHA256SUMS
```

The kernel config is `config/7.3.1-el2.config`: Ubuntu's 7.0 config +
`olddefconfig`, renamed `-el2`, no debug info, no Ubuntu signing certs.
`scripts/build-kernel.sh --from-host` regenerates it from the running kernel.

To move to a newer kernel, change `LINUX_TAG` / `LINUX_DIR` in `sources.env`,
then re-apply the patches (`git am -3` and fix conflicts in the tree, then
`git format-patch` back into `patches/linux/`). After that, rebuild and
re-test with `notes/boot-log.md`'s checklist.

## CI and releases

`.github/workflows/build.yml` runs `scripts/ci-build.sh` in an `ubuntu:26.04`
container on GitHub's free arm64 runner (`ubuntu-24.04-arm`; public repos
only), with ccache kept between runs.

- **Manual run** (Actions → *Run workflow*): build only; the files are
  attached to the run.
- **Release**: push a tag `v<kernel>-el2-<n>`, e.g.
  `git tag v7.3.1-el2-1 && git push origin v7.3.1-el2-1`. The workflow
  publishes the kernel debs, qebspil, slbounce/sltest and `SHA256SUMS`.

## The kernel patches

All from [jglathe/linux_ms_dev_kit](https://github.com/jglathe/linux_ms_dev_kit)
branch `jg/rproc_nohyp_attach` (authors: Stephan Gerhold, Jens Glathe):

| # | Change |
|---|---|
| 0001–0002 | rpmsg core: endpoint creation/teardown fixes the attach path relies on |
| 0003 | qrtr smd: open/close race fix |
| 0004 | remoteproc core: allow restarting detached remoteprocs with new firmware |
| 0005–0006 | qcom_q6v5: detect an already-running DSP at boot; `qcom_q6v5_attach()` |
| 0007–0011 | qcom_q6v5_pas: attach-only path at EL2 when the platform's TZ can't do PAS there (gated by `qcom,broken-reset`) |
| 0012 | kbuild: fix a parallel `dtbs_install` race in `bindeb-pkg` |
| 0013 | new `lenovo-thinkpad-x13s` EC driver: Modern Standby notifications (power LED and lid dot breathe in suspend, as on Windows) and the mic-mute LED; see `notes/x13s-ec.md` |

## Repo layout

```
sources.env            pinned upstream sources (kernel tag, qebspil, slbounce)
config/                kernel .config for the pinned tag
patches/linux/         kernel patches (git am)
dts/                   DT overlay for the DSPs and the EC
scripts/
  fetch-sources.sh  apply-patches.sh  build-efi.sh  build-kernel.sh
  build-dtb.sh       package-release.sh  download-release.sh  ci-build.sh
  el2-install.sh     slbounce boot path (ESP + firmware boot entry)
  install-esp.sh     qebspil + DSP firmware on the ESP
  install-kernel.sh  kernel debs + DSP dtb + EL2 GRUB menu hook
  install-micmute-led.sh  F4 mic-mute LED sync (udev rule + user service)
  x13s-micmute-led   the LED sync daemon (PipeWire mute -> platform::micmute)
  el2-grubcfg.sh     generates /boot/grub/el2.cfg (kernel postinst hook)
  suspend-test.sh    bisect suspend problems (pm_test levels)
  el2/               startup.nsh (UEFI shell), grubel2 embed config
notes/                 slbounce/EL2 research, boot + suspend test logs
PLAN.md                plan, decisions, checklist
src/ out/              sources and build output (git-ignored)
```

## Credits

slbounce by Nikita Travkin, qebspil and the remoteproc attach work by Stephan
Gerhold, EL2 attach-path patches by Jens Glathe. The kernel and patches are
GPL-2.0; see each project for its license.
