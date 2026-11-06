# KVM via slbounce (EL2 boot), research + setup (2026-10-29)

Moved from AndroidEmulator (its Phase 6) on 2026-11-06. Scripts: `scripts/el2-install.sh`,
`scripts/el2/`. Build artifacts (slbounce, grubel2.efi, tcblaunch.exe builds) in `out/el2/`.

## Already in place on this machine
- Kernel 7.0.0-42 has `CONFIG_KVM=y` and ships
  `/lib/firmware/7.0.0-42-generic/device-tree/qcom/sc8280xp-lenovo-thinkpad-x13s-el2.dtb`
  (upstream EL2 variant, 6.16+). No overlay needs to be built.
- Secure Boot is disabled (slbounce requires that).
- GRUB loads the DTB from `/boot/dtb` (symlink to the normal EL1 DTB).
- BIOS N3HET88W (1.60).

## What the EL2 DTB changes vs normal
- Enables the apps SMMU (`iommu@15000000`: reserved -> okay) and adds
  `iommu-map` for all PCIe controllers (no hypervisor to do stage-2 for them).
- Disables the GPU `zap-shader` (the hypervisor normally does the secure handoff).

## Expected losses when booted at EL2
- Remoteprocs (ADSP/CDSP/SLPI): the Qualcomm hypervisor normally boots them;
  Linux can't yet at EL2. ADSP carries audio, battery reporting and USB-C
  orientation/DP altmode on these machines. `qebspil` (stephan-gh/qebspil,
  supports SC8280XP) can start them from UEFI before the switch; kernel
  takeover needs extra patches (codelinaro 6.16/6.17 branches). Treat the EL2
  boot as a "dev mode" boot entry; keep the normal entry as the daily one.

## tcblaunch.exe
- From a Windows arm64 image: `sources/install.wim` (or `install.esd`) in the
  ISO, path inside the image `Windows/System32/tcblaunch.exe`.
  Extract: `7z x install.wim 1/Windows/System32/tcblaunch.exe` or
  `wimlib-imagex extract install.wim 1 /Windows/System32/tcblaunch.exe`.
- Newer builds removed error handling slbounce relies on. Reported working:
  26100.1742 (24H2 RTM), 26100.1, 22621.4317. Reported failing: 22621.2715,
  Canary. Always verify with `sltest.efi` (green line = EL2 reached).
- Ours: `Windows11_Client_arm64_en-us_26300_9457.iso` -> `install.wim` image 1
  -> tcblaunch.exe **10.0.26100.9457**, sha256
  `04b694994054b3e491de9185eaeb842bee629535dc7fef1f9d68c0375d45d954`
  (saved in `out/win/`). Much newer than the reported-good builds: untested.
- WinSxS has a reverse delta (`.../tcbboot_.../r/tcblaunch.exe`) back to
  26100.1, but it's MSDelta **PA31**, which needs Windows'
  UpdateCompression.dll; no Linux tool applies it.
- winbindex only indexes **x64** tcblaunch.exe; no use for arm64.
- arm64 builds come from Microsoft's symbol server:
  `https://msdl.microsoft.com/download/symbols/tcblaunch.exe/<id>/tcblaunch.exe`
  (id = PE timestamp + SizeOfImage). IDs/hashes from LukeMech/hp-omnibook-x14-fe0
  (`rootfs/usr/bin/omnibook-kvm`, TCB_VERSIONS). Downloaded to `out/el2/tcb/<ver>/`:

  | version | id | sha256 | reports |
  |---|---|---|---|
  | 26100.1742 | EC74C165f6000 | 5dfcd025...4770d03d | works on X1E (Yoga Slim 7x), resets OmniBook |
  | 22621.4317 | BEB81838ed000 | 799c8cee...3cf7ff81e | works on sc8280xp (**X13s**) |
  | 26100.4351 | 66A7C7F3100000 | 463520e1...1333e548 | works on X1E |

  **Result 2026-10-29: 22621.4317 passes sltest on this X13s (green line).** 26100.1742 untested, kept as fallback.
- Same script's notes: Fedora GRUB can't chainload EFI drivers so they put
  systemd-boot first; kernel args `id_aa64mmfr0.ecv=1` (X1E firmware resets on
  CNTPOFF_EL2) and `cpuidle.off=1` (input lag at EL2); upstream -el2 DTB's
  remoteproc `iommus` hang 7.1+ kernels (we're on 7.0).
- /tmp is a 7 GB tmpfs: extract install.wim under out/, not the scratchpad.

## Steps
1. Get tcblaunch.exe, check its version.
2. Build slbounce (`make`, native gcc works), copy `slbounce.efi`,
   `sltest.efi`, `tcblaunch.exe` to the ESP.
3. Get a UEFI shell (`Shell.efi`, e.g. from edk2) onto the ESP/USB; run
   `sltest.efi tcblaunch.exe` once (needs the user at the keyboard).
4. Load slbounce before GRUB (UEFI Driver#### entry via `efibootmgr -r`, or a
   chainloading EFI step) and add a GRUB entry with `devicetree` pointing at
   the `-el2.dtb`. slbounce only switches when the loaded DTB is EL2-capable,
   so the normal entry is unaffected.
5. Boot the EL2 entry, check `dmesg | grep -i kvm`, `/dev/kvm`, `kvm` group.
6. `emulator -avd arm64-35 -accel on` (patch #6 picks `-cpu host` automatically).

## Boot path (scripts/el2-install.sh)
firmware entry "Ubuntu (EL2 KVM)" (last in BootOrder; F12 menu) ->
`\EFI\slbounce\shellaa64.efi` -> `startup.nsh` (`load slbounce.efi`, run
`grubel2.efi`) -> `/boot/grub/el2.cfg` (newest kernel, `-el2.dtb`, no quiet/splash)
-> slbounce switches at ExitBootServices because the dtb has zap-shader disabled.
- slbounce reads `tcblaunch.exe` from the **root** of its volume: `\tcblaunch.exe` on the ESP.
- `grubel2.efi`: `grub-mkimage -O arm64-efi` with `scripts/el2/grubel2-embed.cfg`
  (Ubuntu's GRUB menu is hidden/timeout 0 and its signed image can't load EFI drivers).
- `/etc/kernel/postinst.d/zz-el2-grubcfg` regenerates el2.cfg on kernel updates.
- `sudo scripts/el2-install.sh --remove` undoes it all.

## Gotcha: Ubuntu's kernel replaces the dtb (2026-10-29)
First EL2 boot came up at EL1 ("HYP mode not available") with the *normal*
dtb (iommu@14f80000 reserved). GRUB diagnostics: firmware has no DTB table
and GRUB loaded the -el2.dtb fine. Cause: `/boot/vmlinuz-*` is a
stubble/systemd-stub PE (`.dtbauto` x32, `.hwids`, `.linux`): it installs the
dtb matching the machine's CHID over whatever the bootloader passed.
Fix: el2-grubcfg extracts `.linux` (`objcopy -O binary --only-section=.linux`)
to `/boot/el2/vmlinuz-<ver>` and the EL2 entry boots that.

**Result 2026-10-29: EL2 boot works.** `CPU: All CPU(s) started at EL2`,
`kvm [1]: VHE mode initialized successfully`, `/dev/kvm` present (GICv3 only:
"no GICV resource entry, disabling GICv2 emulation" is expected).

**AVD under KVM (2026-10-29):** `emulator -avd arm64-35 -accel on -no-window
-gpu swiftshader_indirect -no-snapshot` cold boots to `sys.boot_completed=1` in
**41 s** (TCG: ~39 min plus Watchdog restart loops). Guest sees the host core
(`CPU part 0xd4b`, Cortex-A78C), no Watchdog kills. `/dev/kvm` access comes
from the logind seat ACL; add the user to `kvm` for non-seat sessions.
