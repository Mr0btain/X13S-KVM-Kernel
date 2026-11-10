# X13s embedded controller (EC)

Found 2026-11-10 while chasing the lid-dot "breathing" LED in suspend (see
boot-log.md, "EC on i2c8 / lid LED investigation").

## Access
- I2C: 0x28 on `i2c8` (`a80000`, QUP1 SE0, gpio43 SDA / gpio44 SCL, function
  `qup8`). Disabled in the stock X13s DT; enabled bare by `dts/x13s-el2-dsp.dtso`
  (shows up as i2c-23 at EL2). ACPI name `\_SB.I2C9`.
- 0x28 on `a8c000` (i2c-22, ACPI `IC12`) is the WWAN SAR sensor `QCOM06A5`, not the EC.
- Firmware string at 0xf0: `N3HHT49W(1.23)`.
- Protocol (DSDT `ECRD`/`ECWR`, same as T14s Gen6 `lenovo-thinkpad-t14s.c`):
  - read:  write `02 <reg> 00 01`, STOP, read 1 byte
  - write: `03 <reg> 00 01 <val>`
  - 16-bit address variants (`ECMR`/`ECMW`): `00|01 <lo> <hi> 01 [val]`
  ```
  i2ctransfer -y 23 w4@0x28 0x02 0xc0 0x00 0x01; i2ctransfer -y 23 r1@0x28
  i2ctransfer -y 23 w5@0x28 0x03 0xc0 0x00 0x01 0x61
  ```

## Register map (partial)
| Reg | Meaning | Evidence |
|---|---|---|
| 0x0b bit6 | AC present | charger diff |
| 0x70 bit5, 0x77 bit4, 0x7f bit6 | AC / charging status | charger diff |
| 0x8a / 0x8b | AC unplug / plug event latch | charger diff |
| 0xa0-0xa7 | temp sensors, 0x80 (-128) = not present | thinkpad EC convention |
| 0xa8-0xad | temp sensors, degC (0xa9 rose 36->55 while charging) | charger diff |
| 0x80 | **standby notify** (write): 0x66 display off, 0x55 sleep entry, 0xaa sleep exit, 0xbb display on. 0x55 alone: power LED breathes, lid dot off; 0x55 + GPIO 176 low: both breathe | DSDT `ECNT`; **verified by write** |
| 0xc0 bit0 | mic-mute LED (F4) | DSDT `MMTS`; **verified by write** |
| 0xc0 bits4-5 | written by DSDT `MLCS` (keyboard/light mode?) | DSDT |
| 0xca bits2-3 | written by DSDT `MLCS` | DSDT |
| 0xd0-0xd9 | 0x7e (126) x10, probably thermal limits | guess - do not write |
| 0xf0-0xfe | EC firmware version string | ASCII |

Not applicable (tested, no effect): T14s LED reg 0x0c (`0x80|id` on,
`0xc0|id` blink; lid id 10, power id 0) and T14s modern-standby reg 0xe0
(`0x02` entry / `0x01` exit; doesn't even read back).

## Standby notification (found)
Windows: PEP0 `_DSM` UUID `11e00d56-ce64-47ce-837b-1f898f9aa461` (Modern
Standby firmware notifications) -> `\_SB.I2C9.ECNT(n)` -> `ECWS(0x80, val, 3)`
(= ECWR 0x80 with retry):

| _DSM fn | ECNT | action |
|---|---|---|
| 3 display off | 1 | EC 0x80 = 0x66 |
| 4 display on | 0 | EC 0x80 = 0xbb (+ `SCMS(0x21)`) |
| 5 sleep entry | 3 | EC 0x80 = 0x55, then GPIO 176 low (`SGOV(0xB0,0)`) |
| 6 sleep exit | 2 | GPIO 176 high, 10 ms, EC 0x80 = 0xaa |
| 7 / 8 MS entry / exit | 5 / 4 | 0x66 / 0xbb (+ DYTC if MSCB) |

Linux (DT boot) never calls this `_DSM`, so the EC never learns the system
sleeps. Test 2026-11-10 at EL2 (0x66, 0x55, 12 s, 0xaa, 0xbb): power-button LED breathed, lid dot
went off (Windows: lid dot breathes). Second test with the full Windows
sequence: **power-button LED and lid dot both breathe.** GPIO 176 (TLMM, func0,
firmware leaves it `out high`, unclaimed in Linux, not in the X13s DT, not
reserved) is the SoC->EC sleep line.

Working recipe (verified 2026-11-10, EL2, by hand):
- suspend: EC 0x80 = 0x66; EC 0x80 = 0x55; GPIO 176 low
- resume:  GPIO 176 high; 10 ms; EC 0x80 = 0xaa; EC 0x80 = 0xbb

Implemented in `patches/linux/0013` (`drivers/platform/arm64/lenovo-thinkpad-x13s.c`,
`CONFIG_EC_LENOVO_THINKPAD_X13S=m`) from system suspend/resume, plus restoring
the keyboard backlight level on resume (0x15[2:1] -> 0xc0[5:4], DSDT
`SCMS(0x21)`) and `platform::micmute`. DT: `embedded-controller@28` on i2c8 in
`dts/x13s-el2-dsp.dtso`, `sleep-gpios = <&tlmm 176 GPIO_ACTIVE_LOW>`.
The 0xe0/0x0c T14s registers and the WMI/`SMI` mailboxes are unrelated to this.

## Hotkey events (found 2026-11-10)
- Interrupt: **TLMM GPIO 103**, falling edge (ACPI `GIO0` `_AEI` pin 0x300 ->
  `\_SB.I2C9.QEXC`). Found with `gpiomon` while pressing F4: the EC pulses the
  line low (~1 ms) about every 100 ms while its queue is non-empty, nothing
  when empty (measured: 0 edges idle, 54 in 6 s with one unread event, 0 after
  reading it). GPIO 132 is noise.
- Read one event: write `f0 00 00 01`, STOP, read 1 byte (DSDT `QEVT`); 0x00 =
  queue empty. Nothing drains it without the driver, so it fills with lid
  (0x52/0x53), thermal (0x50/0x51) and 0x3c events.
- Codes (DSDT `_Qxx` -> `HKEY.MHKQ` -> thinkpad_acpi Lenovo keymap):

| EC | hkey | Linux | key |
|---|---|---|---|
| 0x13 | 0x1004 | KEY_SLEEP | Fn+4 (also `Notify(SLPB)`) |
| 0x19 | 0x1007 | KEY_SWITCHVIDEOMODE | F7 |
| 0x1f | 0x1012 | KEY_KBDILLUMTOGGLE | Fn+Space (EC changes the level itself) |
| 0x28 | 0x101b | KEY_MICMUTE | **F4, verified** |
| 0x2a | 0x1005 | KEY_WLAN | F8? |
| 0x62 | 0x1312 | KEY_SELECTIVE_SCREENSHOT | |
| 0x6c / 0x6d | 0x1318 / 0x1319 | KEY_PICKUP_PHONE / KEY_HANGUP_PHONE | F10/F11? |
| 0x6e | 0x1311 | KEY_BOOKMARKS | F12 (star)? |
| 0x88 | 0x131b | camera shutter toggle | not mapped |
| 0x50/0x51, 0x70/0x72/0x73, 0x75, 0x77 | 0x6040, 0x6005, 0x6060, 0x60c0 | thermal / power events | not mapped |
| 0x52 / 0x53 | 0x5002 / 0x5001 | lid open / close | not mapped (gpio-keys has the lid) |
| 0x3c, 0x36, 0x81 | - / TZ notify / 0x1014 | | not mapped |

Mic-mute LED: `platform::micmute` works when written directly, but the
`audio-micmute` trigger has nothing to follow: UCM's internal `Mic` device has
no hardware capture switch, so PipeWire mutes in software. Needs a userspace
sync (watch the default source mute, write the LED).

## Dumps (charger unplugged, then plugged; 7.3.1-el2, EL2)
```
# unplugged
00: 00 00 02 00 00 00 00 00 b3 00 00 10 00 00 00 30
10: a0 00 07 00 00 04 00 00 00 00 00 00 00 00 00 00
20: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
30: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
40: 00 00 00 00 00 00 00 05 00 00 00 00 00 00 00 00
50: 24 00 84 0c 00 00 01 40 00 00 00 18 00 0a 0b 1a
60: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
70: 02 00 04 01 08 65 00 20 00 01 10 00 51 60 00 00
80: 00 00 3b 00 03 07 00 00 00 00 01 00 00 00 00 00
90: 00 00 00 04 ff 00 00 00 00 b1 00 00 00 00 03 0b
a0: 80 80 80 80 80 80 80 80 22 24 20 22 22 23 00 00
b0: 80 80 80 00 00 00 00 00 00 00 00 00 00 00 11 0b
c0: 60 80 00 00 00 00 00 00 00 04 62 00 40 00 00 00
d0: 7e 7e 7e 7e 7e 7e 7e 7e 7e 7e 00 00 00 00 00 00
e0: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
f0: 4e 33 48 48 54 34 39 57 28 31 2e 32 33 29 20 00
# plugged
00: 00 00 02 00 00 00 00 00 b3 00 00 50 00 00 00 30
10: a0 00 07 00 00 04 00 00 00 00 00 00 00 00 00 00
20: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
30: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
40: 00 00 00 00 00 00 00 05 00 00 00 00 00 00 00 00
50: 24 00 84 0c 00 00 01 40 00 00 00 18 00 0a 0b 1a
60: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
70: 22 00 04 01 08 65 00 30 00 01 10 00 50 60 00 40
80: 00 00 3b 00 03 07 00 00 00 00 00 01 00 00 00 00
90: 00 00 00 04 ff 00 00 00 00 b1 00 00 00 00 03 0b
a0: 80 80 80 80 80 80 80 80 23 37 21 26 23 28 00 00
b0: 80 80 80 00 00 00 00 00 00 00 00 00 00 00 11 0b
c0: 60 80 00 00 00 00 00 00 00 04 62 00 40 00 00 00
d0: 7e 7e 7e 7e 7e 7e 7e 7e 7e 7e 00 00 00 00 00 00
e0: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
f0: 4e 33 48 48 54 34 39 57 28 31 2e 32 33 29 20 00
```
