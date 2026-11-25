# Session log

## 2026-11-25 — day 0: survey

- Vendor source at `~/Build/astro-kernel`: 4.14.186 MTK BSP, single commit
  `a79860700`. Astro board identified as `k6873v1_64_defconfig` +
  `mt6873.dts` + Aeon `aeon_gpio.dtsi` (grep for `aeon` across the tree).
- MT6873 vs mainline MT8192: 97/102 node addresses equal, pin tables equal
  bar GPIO220–227 (receipts in `docs/hardware-map.md`).
- Repo scaffolded from cosmo-linux618 layout; base pinned to v6.18.58.
- Flashing host Monolith (192.168.0.235): answers ping, but no SSH (port 22
  refused). Device not yet reached; nothing read or written on it.

## 2026-11-25 — Monolith reached; read-only adb survey

- SSH `atzero@192.168.0.235` (EndeavourOS x86_64) works; adb, fastboot,
  mtkclient-git 2.1.4.1.r72 installed. Astro on USB `0e8d:201c`, adb
  authorised (`Astro_Slide_5G_Transformer`).
- Non-root getprop/by-name survey → `docs/p0-findings.md`. Headline: locked
  + green, A/B on slot a, boot + vendor_boot + dtbo, UFS, Android 11.
- Nothing written to the device.

## 2026-11-25 — P0 backup (read-only)

- `mtk printgpt` after `adb reboot`: preloader caught, device unprotected
  (SBC/SLA/DAA off) — `docs/p0-findings.md`.
- `mtk rl p0 --skip userdata` → `~/Build/astro-backup/p0` on Monolith
  (backup stays off git). Needed a hand power-key reset to leave DA mode
  first.
- Backup done (user ran it): 58 partitions, 7.2 GiB, SHA256SUMS written —
  `docs/p0-backup.md`. Preloader LUs still to read.
- Research: no official Planet Linux/Debian release for the Astro found
  (promised Debian/KDE, Kali, Sailfish; Planet's wiki covers Gemini and
  Cosmo only). No reference Linux kernel to borrow from.
- Boot chain decoded from dumps → `docs/p0-findings.md`: boot v2 +
  DTB section, `bootopt=` cmdline, vendor_boot empty, dtbo panel list.
  Panel SH8802B **command mode**; LK FB 0x7dd80000 pitch 4352 BGRA8888.
  First-boot display plan needs a decision (cmd mode ≠ Cosmo).

## 2026-11-25 — bootloader unlocked (stage A)

- User ran `mtk da seccfg unlock` on Monolith: "Detected V4 Lockstate",
  "SecCfgV4 - hwtype found: V4", "Successfully wrote seccfg."
  (`~/Build/astro-backup/unlock.log`). Pre-unlock seccfg: `p0/seccfg.bin`.
- After a power-key reset: LK orange-state warning, then stock Android
  booted. **No userdata wipe** (the wipe belongs to `fastboot flashing
  unlock`; mtkclient rewrites seccfg directly — same as the Cosmo).
- adb: `ro.boot.verifiedbootstate=orange`, `ro.boot.flash.locked=0`,
  `ro.boot.vbmeta.device_state=unlocked`.
- A/B: misc+0x800 bootloader_control decoded (slot a active, successful)
  — `docs/p0-findings.md`.

## 2026-11-25 — try1 built: watchdog escape test — PRE-FLASH CHECK

Images (kernel `6.18.58-astro`, source commit 0511f65 + the build-dtbo
check fix):
- `Image.gz` `5da8edab…6aad`, DTB `76eeca6b…d3a3` (50 KiB, `-@`)
- `dtbo.img` (no-op overlay, 1-entry DT table) `40bdc376…f1d7`
- `boot-wdtest.img` (cmdline + `astro.wdtest=1`) `7e84fff4…7271`
- `boot.img` (same, without wdtest) `4fae0363…c9b5`
Offline checks: packer reproduces stock boot_a/boot_b byte for byte;
our image's header fields equal stock's (addresses, os_version, DT
table); DTB in the image = built DTB; no-op overlay applies (`fdtoverlay`);
kernel image_size 0x28b0000 → ends 0x42930000 < ramdisk 0x47c80000;
ramdisk 0xd61f9 < 64 MiB; `bootopt=` kept; init `sh -n` OK.

**Change:** first image of ours. Flash `dtbo_a` = no-op overlay,
`boot_a` = `boot-wdtest.img`. Nothing else is written.

**Risk flags:**
- New kernel config: yes (first kernel).
- PMIC / power-key reset: **not touchable** — pwrap node disabled,
  `MTK_PMIC_WRAP`/`KEYBOARD_MTK_PMIC` not built, SPMI disabled; the boot
  image build refuses otherwise.
- Display/panel: no DSI, OVL, mmsys, M4U or panel command; simpledrm only
  writes LK's framebuffer memory. No register reads either
  (`astro.dispdump` off). Static image at LK's brightness 255 while the
  test runs: keep the session short (burn-in).
- Watchdog: mtk_wdt (Cosmo delta). This test arms it and never feeds it.
- Reset path: restart handler priority 130 (not exercised by this test).

**Escapes:**
- Power-key ~10 s reset: **observed** today, but only pre-kernel (three
  resets out of mtk DA mode). Linux cannot reach the PMIC in this image.
  Not yet observed with our kernel running.
- Watchdog: LK enables it (mode 0x7d). **Not observed** — this test is
  the observation.

**Expected:** LK orange warning → (keyboard light, slider open)
heartbeat → solid on (init reached, watchdog not fed) → board resets by
itself in ~31-62 s → repeats every boot (`0e8d:2000` re-appears on
Monolith each cycle).

**Failure modes:** LK refuses our image (assert) → LK hang or reset loop
(LK's WDT) → power key, then restore. Kernel hangs early → LK-armed WDT
resets (no "solid on"); if it does not, power key. Keyboard light may
stay dark if it needs a rail we do not turn on: then only the reset
timing tells.

**Restore:** `mtk w boot_a,dtbo_a p0/boot_a.bin,p0/dtbo_a.bin`.

## 2026-11-25 — try1 result: LK asserts before the kernel (AVB footer)

- Flashed by the user: `dtbo_a` = no-op (`40bdc376…`), `boot_a` =
  `boot-wdtest.img` (`7e84fff4…`). Reset loop: on Monolith the preloader
  re-appeared alternately 7 s and 24 s after each LK handoff (09:59:19 →
  10:01:04, six cycles). Too short for the watchdog test.
- `mtk r expdb` (user) → LK log, our boots identified by `dtbo_size : 179`:
  - the no-op overlay applies (`dtb_overlay takes 15 ms`);
  - LK reads its own driver data from **our** DTB: no LED nodes, no
    `i2c_lcd_bias`, no LCM pinctrl ("get idx fail. pinctrl_name:"), so
    it cannot reset/power the panel; both panel ID reads return 0
    (`DSI Read Fail: Polling DSI read ready timeout`), LK falls back to
    `sh8802b_fhdp_dsi_vdo_x900` and sends its init blind
    (`DSI_WaitForNotBusy: 1000`); `fb dump: 0xff000000` (black);
  - `[avb] … boot_a: Error verifying vbmeta image: invalid vbmeta header`,
    `boot state: orange`, 5 s orange wait, then
    **`panic … ASSERT at (platform/common/boot/boot_info.c:554): g_boot_info.hdr_loaded`**
    → WDT reset (`[RGU] rst from: lk`). The kernel never ran.
- Cause: stock `vbmeta_a` chains `boot` (rollback location 3) to
  Planet's key, and AVB is what loads `boot_a`. Unlocked, libavb
  tolerates a rejected key / wrong digest but not missing metadata, so
  with no footer the image is never loaded.
- Fix: `bin/build-boot-img.sh` adds an AVB hash footer as stock
  (`avbtool add_hash_footer`, partition `boot`, SHA256_RSA2048, rollback
  0, 0x2800000), signed with a local dev key (`build/avb/`, not in git).
- Escape observations from try1: **LK's own watchdog reset works** after
  an LK panic (`rst from: lk`, MODE 0x25 → re-armed 0x7d by preloader);
  no power-key or kernel watchdog observation yet.
- Open (display): give LK the vendor panel nodes it looks up in our DTB
  (LCM pinctrl states, `/dsi/panelN`, `i2c_lcd_bias`, LEDs) so it can
  reset and power the panel as stock does — next step after the escapes.

## 2026-11-25 — try1b: AVB passes, LK asserts in its DTB fixups

- Flashed by the user: `boot_a` = `boot-wdtest.img` with AVB footer
  (`eee8a221…f0`). Boots every ~9-27 s (Monolith USB log, 10:11-10:12).
- `mtk r expdb` (agent, quick read; first attempt cut by a reset) →
  `[avb] avb_ret = 0`, `boot state: orange`, `load boot image takes
  5394 ms`, `decompress_kernel takes 797 ms` — **the AVB footer fix
  works**. Then LK's fixups on our DTB: `EMI info incorrect`,
  `[set_fdt_dramc] get_path_offset fail`, `DRAMC info incorrect`,
  `can't find reserved-memory node`, `DRAM dummy read address incorrect`,
  `[SCP] platform_fdt_scp: getting node from dtb fails`,
  `SSPM: no reserved mem found, skip`, `/sleep not found. LINE: 101`,
  `[atf] ATF does not support ram dump`, then
  **`ASSERT at (app/mt_boot/mt_boot.c:991): 0`**. None of these lines
  appears in a stock boot (which logs `[SCP] set core status=okay`,
  `SSPM: set reserved mem status=okay`, `spmfw version: …` there). The
  assert sits before the ssmr step (no "can't find memory-ssmr-features").
- Fix (try1c): carry the vendor nodes from the stock base DTB —
  `/reserved-memory` container + `reserve-memory-sspm_share`,
  `sleep@10006000`, `emicen@10219000`, `dramc@10230000`, `scp-lk`
  (`mediatek,scp`, no reg), `memory-ssmr-features`. No mainline driver
  matches them (grep of drivers/ and sound/).

### try1c PRE-FLASH CHECK

- Images: DTB `9cf8c904…2b8a`, `boot-wdtest.img` `c3b3da0c…e6`,
  `boot.img` `a1dc4f5c…b39` (same kernel `5da8edab…`, same init;
  AVB footer; no-op overlay still applies offline).
- Change vs try1b: DTB only (vendor data nodes above). Writes `boot_a`.
- Risk flags: no new driver, config, PMIC, display, watchdog or reset
  change. New: 5 MiB dynamic `sspm_share` no-map pool in low RAM.
- Escapes: LK panic → WDT reset observed (try1, try1b). Power key observed
  pre-kernel only. Kernel watchdog: not yet observed (this test).
- Expected: as try1 (heartbeat → solid → self-reset 31-62 s after init).

## 2026-11-25 — try1c: LK jumps to our kernel; watchdog reset observed

- Flashed by the user: `boot_a` = try1c `boot-wdtest.img` (`c3b3da0c…`).
  Monolith USB log: boots at 10:18:28 (power key), 10:18:38, 10:19:45
  (+67 s).
- `mtk r expdb` (agent, quick read). Blocks changed since try1b show,
  for our boots: `[SCP] set core status=disabled`, `SSPM: set reserved
  mem status=okay`, `spmfw version: pcm_suspend_v1.43_20200622`, the ssmr
  scenarios + `get ssmr-reserved-cma_memory failed` (as stock),
  `Storage type :2`, our cmdline, **`lk finished --> jump to linux kernel
  64Bit`**, **`[LK]jump to K64 0x40080000`**. Remaining non-fatal:
  `EMI info incorrect`, `/mddriver not found`, `vpu_core0/1 was not
  found, try to create`, `'mediatek,dfd_cache' not found`.
- Two jumps logged: the first with `lk boot reason = 0` (power key), the
  next boot with **`lk boot reason = 4`** (`BR_WDT_BY_PASS_PWK`: watchdog
  reset). **Watchdog escape OBSERVED with our kernel running.** The
  ~67 s cycle fits LK ~12 s + kernel/init + 31-62 s unfed watchdog.
- Not yet known: whether init was reached (keyboard light "solid on"),
  i.e. whether the reset came from init's unfed /dev/watchdog or from an
  earlier kernel hang with LK's watchdog still armed.

## 2026-11-25 — normal image: init reached, feeding the watchdog

- Flashed by the user: `boot_a` = try1c `boot.img` (`a1dc4f5c…b39`).
  Boot 10:23:53 (preloader), LK running from 10:23:55.
- User: **keyboard light blinking fast** = init's `timer 100 100` LED
  pattern, set only after init opened /dev/watchdog and started feeding
  it. First user-visible proof that our 6.18 kernel runs to userspace on
  the Astro: GPIO (pinctrl-mt8192 on MT6873), gpio-leds, initramfs, init.
- Implies the try1c wdtest resets (boot reason 4) were most likely init's
  unfed watchdog, as designed.
- No self-reset for 100 s (10:23:53 → hold; the wdtest image reset every
  ~67 s), with the keyboard light blinking fast throughout.
- **Power-key escape OBSERVED with our kernel running**: user held power
  ~10 s at ~10:25:2x; preloader re-appeared 10:25:33 (Monolith USB log),
  LK 10:25:36, same image booted again. User confirmed the reset came
  with the hold.
- **Rule 5 status: both escapes observed under our kernel** — watchdog
  (try1c wdtest, boot reason 4) and power key (this boot). Screen: black
  throughout ("nothing on the screen"), as expected from LK's blind panel
  init.
