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

## 2026-11-25 — display: LK's board config comes from `dtbo` on LK's own DTB

- Diff of LK-only display messages, stock vs our boots (try1c expdb):
  stock finds `gpio_init_default` ("Found perperty … len 6020"), the
  `/odm/led@0-6` nodes ("backlight hw mode is LCM", `SH8802B backlight:
  level = 255`), the LCM pinctrl ("gpio set lcm rst pin"),
  `/dsi/panel2/port/endpoint`, and reads panel status 0x0A = 156;
  ours: "Fail to found property gpio_init_default", "Cannot find LED node",
  "get idx fail. pinctrl_name:", "get panel node failed", 0x0A = 0.
- All of these are in the **stock dtbo** (gpio_init_default, odm LEDs,
  mtkfb/dispsys_config pinctrl, dsi0 panels), not in the stock base DTB.
- LK applies `dtbo` once per boot at ~350 ms, right after
  `load_lk_dtb(): load lk_main_dtb dtb_img_size=171401` (= the size of
  stock's kernel DTB: LK carries its own copy in `lk`) and seconds before
  the boot image is loaded; stock logs no second overlay pass. Our boots
  log `Found /gpio@10005000 at offset 14984` although our kernel DTB has
  no such node → these lookups run on LK's own DTB + dtbo. Our kernel
  still receives our DTB (its gpio-leds node drives the keyboard light).
- Hypothesis: the no-op dtbo removed LK's own board config. Test: stock
  `dtbo_a` back, our boot.img unchanged.

### display test 1 — PRE-FLASH CHECK

- Change: `dtbo_a` = stock (`p0/dtbo_a.bin`, sha256 in p0/SHA256SUMS).
  `boot_a` stays try1c `boot.img` (`a1dc4f5c…`).
- Panel: LK runs its stock init with stock GPIO/LED config — the same
  sequence every stock Android boot runs. Our kernel sends nothing to the
  panel. Brightness: LK's stock 255 → keep the session short (burn-in).
- Risk: if LK also overlays dtbo onto our kernel DTB, the stock overlay
  cannot resolve its labels → "dconfig DT overlay failed, system not
  bootable" / assert → LK panic → watchdog loop (observed escape).
  Undo: `mtk w dtbo_a dtbo.img` (no-op).
- Escapes: both observed with our kernel (unchanged kernel and config).
- Expected: logo/orange screen visible as on stock; then our kernel; the
  keyboard light blinks fast; the screen most likely freezes on LK's last
  frame (SH8802B command mode, nothing triggers new frames yet).

## 2026-11-25 — display test 1 result: LK applies dtbo twice

- Flashed by the user: `dtbo_a` = stock (`p0/dtbo_a.bin`), `boot_a` =
  try1c boot.img. User: **orange-state screen visible** (first time on
  our boot chain). Then a reset loop (~26-32 s, Monolith USB log).
- `mtk r expdb` (agent): LK's own pass works with the stock dtbo
  (`read from lcm 0x0A: 156`, `SH8802B backlight: level = 255`), then
  `ERROR: ufdt_overlay_do_fixups():Couldn't find 'reserved_memory' symbol
  in main dtb`, `boot image dtb_overlay fail`, … `ASSERT at
  (platform/common/boot/boot_info.c:61): g_boot_info.img_loaded`. So LK
  applies `dtbo` to its own DTB (~350 ms) **and** to the kernel DTB
  (~3 s); the second failure is fatal. Watchdog loop as expected.
- Fix: `dtbo/astro-lk.dts`, the six stock fragments LK's display path
  needs (odm LEDs, pio LCM states, mtkfb, dispsys_config, dsi0 panels,
  gpio_init_default), on labels present in both DTBs. Our DTB gets an
  inert `/lk-sink` (no compatible, disabled) with those labels;
  `bin/build-boot-img.sh` points `__symbols__` pio/dsi0 there, so the
  overlay never lands on the real mainline pinctrl/DSI nodes.
- Offline: astro-lk applies to the stock base DTB (= LK's lk_main_dtb,
  171401 bytes); result equals the stock overlay for led@6,
  lcm_rst_out0_gpio, lcm_dsi_te, panel2@0 (phandles aside);
  gpio_init_default identical (1505 cells). Applies to our boot DTB and
  lands only in /lk-sink; real dsi@14010000 stays disabled, no panels.

### display test 2 — PRE-FLASH CHECK

- Images: `dtbo.img` = astro-lk `a86abc6d…a499`; `boot.img`
  `7c8912d8…a58d` (kernel unchanged `5da8edab…`; DTB + /lk-sink, boot DTB
  with redirected symbols); `boot-wdtest.img` `5cc815f6…0528` (spare).
- Writes: `dtbo_a`, `boot_a`.
- Panel: LK's stock panel/backlight/GPIO config (identical to stock's
  fragments) → stock init sequence. No Linux display driver. Brightness
  255, static frame after handoff → short session, burn-in.
- gpio_init_default: LK now sets every pin to the vendor DWS defaults,
  as on every stock boot (it did not with the no-op dtbo).
- Escapes: kernel and config unchanged → both still observed. A failed
  LK pass ends in LK panic → watchdog loop (observed). Undo:
  `mtk w dtbo_a <no-op dtbo>` (`NOOP=1 bin/build-dtbo.sh`) or stock.
- Expected: LK logo/orange screen, `lk finished --> jump`, keyboard light
  fast blink, no reset loop; the screen most likely stays frozen on LK's
  last frame (command-mode panel).

## 2026-11-25 — display test 2 result; burn-in guard

- Flashed by the user: `dtbo_a` = astro-lk (`a86abc6d…`), `boot_a` =
  `7c8912d8…`. User: **keyboard light blinking fast, screen on the orange
  warning**: LK's own overlay pass and the pass on our DTB both succeed,
  LK runs its stock panel init and hands over; our init runs. The
  command-mode panel keeps LK's last frame (orange warning, brightness
  255) indefinitely.
- Burn-in guard (user request): `gpio-hog` GPIO42 (panel reset) output
  low at pinctrl probe. Vendor lcm_unprepare = DCS 0x28, 0x10, reset low,
  bias low; we do only the reset step (no DSI path yet for DCS); reset
  low is also the state LK's init starts from each boot. GPIO87/88 not
  touched.

### display test 3 (reset hold) — PRE-FLASH CHECK

- `boot.img` / `boot-wdtest.img` with the hog (DTB only changed); dtbo
  unchanged (astro-lk). Writes `boot_a`.
- Panel: one GPIO (reset) driven low by Linux after LK's normal init; no
  DSI, no DCS, no rail. Expected: orange screen during LK, then black
  within ~1 s of the kernel starting. Next boot's LK reset+init restores.
- Escapes: kernel/config unchanged → both still observed.
- Result (user ran `mtk w boot_a boot.img`, `c3486e4c…`): **orange
  warning during LK, then blanked**, no garbage or flicker; keyboard
  light blinking fast (init feeding the watchdog). Burn-in guard works.

## 2026-11-25 — usb1: USB gadget network — PRE-FLASH CHECK

- DTS: `ssusb: usb@11201000` (`mediatek,mt8192-mtu3`, mac 0x11201000,
  ippc 0x11203e00, SPI 96, u2port0 only), OTG + role switch defaulting to
  peripheral, high-speed, `u3p-dis-msk = <1>` (Cosmo recipe); T-PHY
  `u3phy0` re-enabled. No vbus/vusb33 supply (PMIC stays out of reach).
- Config: `USB_MTU3=y` (dual role), `USB_LIBCOMPOSITE=y`, `USB_ETH=y`
  (g_ether CDC ECM), RNDIS off. Kernel `92ff386d…`, DTB `fc86347a…`.
- Cmdline: `g_ether.dev_addr=42:00:15:21:01:01
  g_ether.host_addr=42:00:15:21:01:00`. Init: usb0 = 10.15.21.1, udhcpd →
  host 10.15.21.2, `telnetd`, `nc -lk -p 2323 -e /bin/sh`
  (`bin/astro-sh` drives it via Monolith + socat).
- Images: `boot.img` `5bb2631a…48fb`, `boot-wdtest.img` `eb016b91…c41d`;
  dtbo unchanged (astro-lk `a86abc6d…`). Writes `boot_a`.
- Risk flags: **new kernel config** (USB only). New hardware access: SSUSB
  IP (infracfg SSUSB gate, apmixed USBPLL, T-PHY u2 port init). No PMIC,
  watchdog, reset-path or display change (GPIO42 hold kept).
- Escapes: watchdog and power key observed with the previous kernel;
  nothing here touches PMIC keys, watchdog or keyboard input, so they
  stand. Worst case for USB: no usb0 (init logs it and keeps feeding the
  watchdog) or a hang in USB probe (kernel worker keeps the watchdog fed
  only while the kernel lives: a hard hang → watchdog; a soft hang → power
  key).
- Expected: keyboard light fast blink as before; on Monolith a new
  `42:00:15:21:01:00` cdc_ether interface, DHCP 10.15.21.2,
  `telnet 10.15.21.1` works.

## 2026-11-25 — usb1 result: gadget up, link never seen; RAM log channel works

- Flashed by the user: `boot_a` = usb1 boot.img (`5bb2631a…`). Keyboard
  light fast blink (init alive); nothing new on Monolith's USB.
- Blink-code image (`boot-logreset.img`, `6449863e…`, `astro.logreset=1`):
  user saw **3 blinks** = UDC present, usb0 present, state "not attached".
- **Log channel**: after the image's deliberate watchdog reset, `mtk da
  peek 0x4d000000 0x100000` (agent, quick read) → ramoops `DBGC` at
  0x4d010000, console zone 0x4d09f000 (27 KiB of our kernel's log) and
  pmsg zone 0x4d0df000 (init's ASTRO-DIAG). **RAM survives a watchdog
  reset** (power-key reset untested here; it did not on the Cosmo).
- Kernel log: `mtu3 11201000.usb: … IP version 0x1003(U3 IP)`, `dr_mode:
  3`, `u3p_dis_msk: 1`, `max_speed: high-speed`, `g_ether ready`,
  `gadget (high-speed) pullup D+` → controller and gadget fine; the host
  never sees the pull-up. Also `simple-framebuffer … probe … failed with
  error -12` (to look at later).
- Candidates: (1) USB mux — right port = GPIO13 `usb_sw` low and GPIO127
  `hdmi_usb_sw` low (vendor aeonusb.c / uswitch.c usb_gpio_init); the
  stock gpio_init_default LK applies sets both output low; (2) PHY setup
  mainline tphy skips: vendor phy-mtk-mt6873.c phy_init_soc sets
  U2PHYDTM1 FORCE_VBUSVALID/FORCE_AVALID/FORCE_SESSEND and
  RG_SSUSB_VUSB10_ON (U3 PHYA bank, 0x11e40b04 bit 29), mainline only the
  RG values (u2_phy_instance_power_on) and never the u3 bank.

### usb2 — test image (init only)

- `boot-usb2.img` (`7424d09e…`): cmdline `astro.logreset=1
  astro.usbforce=1`. Init dumps PHY/IPPC/MAC/GPIO registers (read only),
  then writes the vendor values (DTM1 forces, then VUSB10_ON if still not
  attached), re-reads the UDC state after each step, blink code from the
  final state, record to pmsg, watchdog reset ~30 s later for the RAM log.
  USB PHY register writes only; the vendor writes them every stock boot.
- `boot.img` (`e7f4e743…`): same init without the flags (to end the loop).

## 2026-11-25 — usb2 result: USB network and shell work

- Flashed by the user: `boot_a` = `boot-usb2.img` (`7424d09e…`). User:
  **5 blinks** (configured), and a new device on Monolith.
- Monolith: `0525:a4a1 Netchip … Linux-USB Ethernet Gadget`,
  `enp0s20f0u6 10.15.21.2/24` (NetworkManager DHCP from the Astro's
  udhcpd). `bin/astro-sh 'uname -a'` → `Linux (none) 6.18.58-astro #2 …
  aarch64`. Full dmesg fetched over the shell (`backup/usb2-dmesg.txt`).
- `/tmp/usbregs.txt`: "udc state: not attached" → **"after
  vbus/avalid/sessend force: configured"**. VUSB10_ON not needed.
- Fix moved into the kernel: delta `drivers/phy/mediatek/phy-mtk-tphy.c`
  adds the u2 port property `mediatek,force-vbus-valid` (sets
  U2PHYDTM1 FORCE_VBUSVALID bit 13, FORCE_SESSEND bit 12, FORCE_AVALID
  bit 10 at power-on, next to mainline's RG values); `&u2port0` sets it.
  Kernel `2ad23ce5…`, DTB `32c2938e…`. Init still dumps the registers
  (read only); `astro.usbforce` stays as a test path.
- Also seen in dmesg: `WARNING … arch/arm64/mm/ioremap.c:27` then
  `simple-framebuffer 7dd80000.framebuffer: probe … failed with error
  -12`: LK reserves the framebuffer mapped (mblock map:1), so ioremap of
  RAM is refused. To fix with the display work.

## 2026-11-25 — usb3: USB fix in the kernel

- Flashed by the user: `boot_a` = `81f18d5d…` (kernel `2ad23ce5…` with
  the tphy delta, no test flags). User: 3 blinks, device on Monolith.
- Shell: UDC `configured` at 67 s; `U2PHYDTM1=0x00003426` →
  FORCE_VBUSVALID=1 FORCE_SESSEND=1 FORCE_AVALID=1 RG_VBUSVALID=1
  RG_SESSEND=0 RG_AVALID=1, set by the kernel. **USB device network works
  from the kernel alone.**
- The blink code (3) was a race: init read the state at 0.67 s, before
  the host enumerated. Init now waits up to 10 s for "configured".

## 2026-11-25 — display: LK's path read back; frame-kick test — PRE-FLASH CHECK

- Read-only over the USB shell (`backup/disp-regs-lk.txt`), after checking
  the mmsys clock gates first (CG0 0xF7FC40E0: mutex0/ovl0/rdma0/ovl0_2l
  and dsi0 ungated; CG2 bit0 ungated):
  - DSI0: START 1, MODE_CTRL 0 (command mode), INTSTA 0x4 (TE_RDY),
    PSCTRL 0x2C030CA8, MEM_CONTI 0x3C, CMDQ_SIZE 1, **CMDQ0 0x002C3909**
    (DCS long write 0x2C write_memory_start).
  - MUTEX0: EN 0, SOF 0, MOD0 0x93F7.
  - OVL0_2L (0x14006000) layer 0 addr **0x7DD80000** (console fb);
    OVL0 (0x14005000) layer 1 addr **0x7E754000** (LK logo/warning,
    pitch 4320) on top; OVL0 DATAPATH_CON BGCLR_SEL_IN (background from
    OVL0_2L). RDMA0 1080x2340.
- simpledrm -12: LK's framebuffer mblock is map:1 (in the linear map);
  arm64 refuses ioremap/WC of mapped RAM, so neither `reg` nor
  `memory-region` works as is; a second reservation over LK's mblock is
  what made the Cosmo's LK refuse to boot. Console fb deferred to a real
  driver (mediatek DRM, command-mode DSI).
- Tooling: `bin/astro-sh` waits for the command's own timeout (socat -t);
  init's regdump loop compared against hex (busybox `[` takes decimal
  only) and printed nothing — fixed.

### dispkick1 — PRE-FLASH CHECK

- DTS: GPIO42 gpio-hog removed; `initramfs/init` blanks first thing via
  `/bin/astro-disp reset-hold` (read-modify-write of GPIO DO1 0x10005110
  bit 10; no SET/CLR alias assumed). Kernel unchanged (`2ad23ce5…`).
- `boot-dispkick.img` (`4b2bb7ac…`, `astro.dispkick=1`): init instead runs
  `astro-disp black`: both OVLs SRC_CON=0, ROI_BGCLR=0xff000000, then one
  frame (DSI INTSTA cleared, MUTEX0_EN=1, DSI_START 0→1, wait CMD_DONE,
  MUTEX0_EN=0). No frame → reset hold. Live panel: blank after 600 s.
  `boot.img` (`79cc1fde…`): default reset hold.
- Panel: register writes to LK's already-running path only; the one DCS
  sent is the write_memory_start LK queued itself; black pixels = OLED
  off. No panel init, no rail.
- Escapes: kernel/config unchanged → both stand. A bus stall from a
  register access → kernel hang → watchdog (kernel worker stops feeding).
- Expected: orange (LK) → **black** within ~1 s of the kernel; then colour
  tests over the shell, each ending in `astro-disp black`.
- Result (user flashed `boot-dispkick.img`): screen orange → black as
  before, but now from **our black frame** (`/tmp/dispkick.txt`: "frame
  done (5 ms, INTSTA 0x00000016)"; GPIO42 still high, `0x10005110 =
  0x400`: panel live, not in reset).
- `astro-disp color 0xff000060` (11:23:08) → user: **"blue!"**; 20 s
  later `astro-disp black` → frame done. **Linux drives the SH8802B
  through LK's command-mode path**: OVL background + MUTEX0_EN +
  DSI_START, CMD_DONE in 5 ms.

### dispfb1 — PRE-FLASH CHECK

- DTS: `/reserved-memory/astro-fb@70000000` (10 MiB, no-map) and
  `chosen/framebuffer@70000000` (simple-framebuffer 1080x2340, stride
  4352, a8r8g8b8) replacing the node on LK's framebuffer. Range checked
  free on the running kernel: `/proc/iomem` 4d100000-77feffff System RAM,
  only 5feff000 reserved inside; LK's mblocks (DT) none near it.
- `astro-disp fb`: OVL0 SRC_CON 0 (LK logo layer off), both BGCLR black,
  OVL0_2L L0 address = 0x70000000 (LK's layer setup otherwise kept: pitch
  0x1100, L0_CON 0x21FF), OVL0_2L SRC_CON 1, one frame. `kick`: frame only.
- Images: `boot-dispkick.img` `a9765ff1…` (dispkick: black frame at
  init), `boot.img` `562f3bb2…` (reset hold). Kernel unchanged.
- Risk: a reservation LK does not know about (non-overlapping; the Cosmo's
  no-map scp_fw_mem at 0x50000000 was accepted). If LK refused it: LK
  panic → watchdog loop (observed escape) → reflash.
- Test plan (shell): write bands with alpha 0xff into /dev/fb0, `astro-disp
  fb`, ~10 s, `astro-disp black`.
- Result (user flashed `boot-dispkick.img` `a9765ff1…`): boots black as
  before; LK accepted the new no-map reservation; `[drm] Initialized
  simpledrm 1.0.0 for 70000000.framebuffer`, `fb0: simpledrmdrmfb` (fbdev
  shadow stride 4320; simpledrm blits to the 4352-stride buffer).
- `astro-disp fb` after writing test bands to /dev/fb0 → user: **the
  kernel boot console with accurately coloured penguins** (fbcon had been
  drawing into our buffer all along; command mode shows it only on a
  frame). First attempt's bands were broken (shell variables drop NUL
  bytes: rows of 2160 bytes); fixed with printf-to-file rows (4320 bytes,
  verified with od).
- With fbcon unbound (`vtcon1/bind = 0`): user sees **white, red, green
  stripes** (bytes ff ff ff ff / 00 00 ff ff / 00 ff 00 ff) with leftover
  console text: **format a8r8g8b8 (BGRA in memory) and stride 4352
  confirmed on glass.** Each exposure ~10 s, then `astro-disp black`.

## 2026-11-25 — console1: visible console with idle blanking — PRE-FLASH CHECK

- LK's `zone-movable-cma-memory` node: empty (only `name`), reserves
  nothing; MemTotal 7386408 kB.
- `initramfs/astro-console`: while active (new kernel message, or
  `astro-disp wake`), ~5 frames/s via `astro-disp kick`; after 60 s idle a
  black frame and no more frames until the next activity. Init's main
  loop blanks the panel (black + reset hold) if the helper dies.
- Default boot now: black frame (not reset hold) + astro-console;
  `astro.noconsole=1` or a failed black frame → reset hold. Init only;
  kernel/DTB unchanged. `boot.img` hash below.
- Burn-in bound: a static console stays lit at most ~60 s after the last
  activity (plus LK's own orange frame during boot, as always).
- Image: `boot.img` `0df962b1…9c39` (writes `boot_a`).
- Result (user flashed `0df962b1…`): **console visible** on a normal boot.
- Orientation: `rotate_all = 1` → user: **upright with the slider open**.
  "Only ~2/5 of the screen": the console is 146x33 (TER16x32, landscape;
  67x73 portrait at boot); full-width ruler rows 1/16/32 → user: fills
  the screen ("fixed!") — the 2/5 was just short kernel lines.
- `fbcon=rotate:1` now on the cmdline (build-boot-img.sh). Image includes
  the blink-code wait (configured) fix.

## 2026-11-25 — ufskbd1: UFS and keyboard — PRE-FLASH CHECK

Read only over the USB shell first (kernel `2ad23ce5…` running):
- infracfg CG2_STA (0x100010ac) = 0x00000100, CG3_STA = 0x0800C800: UFS
  gates (CG2 bits 11/12/13/28/29/30, CG3 bit 5) all ungated (LK uses UFS).
- UFSHCI 0x11270000: CAP 0x3587071F (no MCQ), VER 0x200, HCE 1, HCS
  0x10F, REG_UFS_MTK_IP_VER 0x20160706 = mainline `IP_LEGACY_VER_MT6893`.
  0x144 (XOUFS/REFCLK_CTRL) = 3 (request+ack).
- GPIO: MODE15 0x00111111 (GPIO122/123 = SCL8/SDA8 already), GPIO5 output
  **low** (AW9523 HWEN: chip in shutdown), GPIO2 input high (INT idle).

Vendor vs mainline:
- UFS SiP: vendor `MTK_SIP_KERNEL_UFS_CTL` 0x82000276 with cmd 2 (device
  reset, 0 then 1) and 8 (ref clk) = mainline `MTK_SIP_UFS_CONTROL`
  BIT(1)/BIT(3). Mainline also sends BIT(2) crypto enable (failure only
  clears the crypto cap). Vendor `ufs_mtk_init_mphy` is empty → no phys.
- Mainline bug for legacy IPs: `ip_ver >= IP_VER_MT6989/MT6899` checks
  match 0x20160706 (MMIO_OPT_CTRL_0 DDR_EN write, VS_DEBUGOMC 0x100).
  Delta `drivers/ufs/host/ufs-mediatek.c` adds `!host->legacy_ip_ver`.
- Keyboard: vendor `aw9523_key.c` key_map[] = the Cosmo's matrix exactly
  (8 rows P0, 7 cols P1); Fn → KEY_LEFTMETA as on the Cosmo. Cosmo driver
  `aw9523-keypad.c` + Kconfig/Makefile copied (they differ from base only
  by the AW9523 entry). Stock: i2c8 400 kHz open-drain, EINT2 level-low
  (GPIO2 pull-up), HWEN GPIO5 (driver: reset-gpios active low, same
  5 ms low / 5 ms high pulse as vendor).

Image `boot-ufskbd1.img` = `boot.img` `8d6ec3a0…0d90` (kernel Image.gz
`05085538…`, DTB `c27311f1…`):
- Config: +SCSI_UFS_MEDIATEK (selects PHY_MTK_UFS, RESET_TI_SYSCON; no
  nodes for either), EFI_PARTITION, I2C_MT65XX, KEYBOARD_AW9523.
  pwrap / PMIC keys / DRM_MEDIATEK still off (build-boot-img checks pass).
- DTS: `ufshci@11270000` (4 vendor clocks, 2 lanes, no vcc-supply, no
  phys, no resets), `&i2c8` okay with only keyboard@5b, GPIO2 pull-up.
- Init: every /dev/sd* set read-only (blockdev --setro) in the main loop
  unless `astro.ufsrw=1`; diag record gets ufs/i2c lines.

Rule 5:
- PMIC: unreachable as before (no pwrap). VEMC (UFS VCC) not described,
  so Linux can never turn it off. i2c8 carries only AW9523 + a camera
  EEPROM; the PMIC/charger are on pwrap / other buses.
- Watchdog / power key: kernel config changed → re-observe. Expected
  failure modes: UFS host/UIC hang or an ATF SMC that never returns →
  watchdog (kernel stops feeding / init never starts) → reset; i2c hang →
  only the keyboard. Power key ~10 s is PMIC hardware, unaffected.
- UFS writes: Linux UFS init writes host registers, a device reset, and
  volatile flags (WriteBooster enable); no `ref_clk` clock so bRefClkFreq
  is never written. Nothing mounts or writes any LU; init marks them ro.
- Worst case: board in a reset loop → `mtk w boot_a boot-dispkick.img`
  (`a9765ff1…`, booted 2026-11-25) from download mode. Note: the board
  runs `0df962b1…` (console1; cmdline has no `fbcon=rotate:1`), which is
  not on Monolith; Monolith `boot.img` `836308e4…` (11:38, +rotate) was
  never flashed.

Test plan: shell: dmesg ufs/scsi, `/proc/partitions`, `blkid`-free GPT
names via `/sys/block/sd*/sd*/uevent` (PARTNAME), read 4 KiB from a few
partitions and compare with backup/ hashes; then evdev keypresses
(`hexdump /dev/input/eventN`) while the user types. Then power-key 10 s
escape with this image.
- Result (user flashed `boot-ufskbd1.img` `8d6ec3a0…`): boots.
  - **UFS works**: `ufshcd-mtk … legacy IP version - 0x20160706, is
    legacy : 1`, device reset done, SK hynix H9HQ15AFAMADAR (A102); LU0
    sda 4 MiB, LU1 sdb 4 MiB (preloader boot LUs), LU2 sdc 119 GiB with
    57 GPT partitions, names = stock (boot_a sdc30, super sdc55, userdata
    sdc56, …). One `dme-set: attr-id 0x15d4 val 0x3 failed 0 retries`
    (harmless so far). All /dev/sd* read-only (init).
  - Read check: full-partition sha256 of lk_a, lk_b, vbmeta_a, logo,
    tee_a = the P0 backups (Monolith p0/); dtbo_a = out/dtbo.img
    (`a86abc6d…`, our overlay).
  - **Keyboard failed**: `aw9523-keypad 0-005b: chip id -110`; every
    i2c8 transfer timed out, 0 interrupts. GPIO5 high after probe (HWEN
    released).

## 2026-11-25 — i2c8 is multi-channel: the AP channel is at +0x100

- Hand-ungating i2c8 (topck CLK_CFG_10 bit 15 = i2c_sel gate, infra CG0
  bit 11, imp_iic_wrap_s 0xe00 bit 1) before reading: with any of the
  three gated the block reads 0. Note: mainline gates i2c_sel; the vendor
  clock driver never does (INV_MUX_GATE).
- With clocks on: at base+0 only SLAVE_ADDR/INTR_MASK keep writes;
  CONTROL/TIMING/START read 0 mid-transfer while AP-DMA sits enabled.
  At base+0x100 registers read back what is written; ch1 START = 0x2
  (RESUME_ARBIT). Vendor (i2c-mtk.c, mt6873.dts i2c8 `ch_offset_default
  = <0x100>`) inits on ch0 ("shadow") and programs every transfer on ch1;
  it also asks ATF (SiP 0x820002A0) for MULTI_DMA shadow mode.
- Test module (copy of mainline i2c-mt65xx with knobs, bound by
  driver_override after unbinding the built-in): base+0x100 →
  `input: Integrated keyboard`, IRQs. Knob sweep (chip ID read 0x23):
  ch1 alone works; shadow init and MCH FIFO clear not needed; ch0 times
  out even with them. No SMC needed.
- User typed: **keymap correct, Shift works**, some letters doubled, Fn
  does nothing. Capture (88 events): no phantom press/release; the
  doubles are autorepeat (repeat events 250 ms after press: input-core
  default delay; keystrokes here are held 200-250 ms). Fn = KEY_LEFTMETA
  as on the Cosmo, whose Fn layer is userspace (gemini-debian xkb
  `cosmo`, console remap.inc), so nothing in this initramfs.

### ufskbd2 — PRE-FLASH CHECK

- DTS: `&i2c8` reg = <0x11d01100 0xf00> (+ DMA window unchanged). No
  driver change for I2C.
- Keyboard driver (Astro delta copy): `input_enable_softrepeat(500, 33)`.
- Image `boot-ufskbd2.img` = boot.img `da6b9665…d0da` (Image.gz
  `8e983863…`, DTB `f5397256…`). Config unchanged from ufskbd1; rule 5
  checks pass. Escapes: power key still to be re-observed on this
  kernel family.
- Result (user flashed `boot-ufskbd2.img` `da6b9665…`, kernel #5): boots;
  `input: Integrated keyboard as …/11d01100.i2c/i2c-0/0-005b` at 0.64 s
  with the built-in mainline I2C driver; UFS probes at 0.87 s (10.9 s on
  ufskbd1, after the I2C timeouts). User typed: **no doubles**. Capture:
  96 presses, 26 repeats (keys held > 500 ms only), one re-press 60 ms
  after release (possible bounce, watch).
- **Power key ~10 s: observed** on kernel #5 (ufskbd2): user held power
  with the Astro booted normally, also with USB/power disconnected →
  reset by itself, booted back; LK cmdline `androidboot.bootreason=
  reboot_longkey`. (Watchdog escape not re-run on this kernel; the
  watchdog path is unchanged.)

## 2026-11-25 — ufskbd3: UFS adapt-type fix, blink code once — PRE-FLASH CHECK

- UFS on kernel #5: link HS_GEAR3 / HS_RATE_B / 2 lanes / FAST_MODE,
  idle HIBERN8 (`power_info`). The one error, `dme-set: attr-id 0x15d4
  val 0x3 failed`, is PA_TXHSADAPTTYPE (UniPro 1.8, HS-G4 only) written
  unconditionally by mainline `ufs_mtk_pre_pwr_change`; the vendor
  writes it only on G4 hosts. The failure made the hook return an error
  and ufshcd fell back to the desired mode (same result). Delta: skip it
  on legacy IPs.
- Init: the USB code blinks once, then the keyboard light stays off; a
  USB failure (code 1-4) keeps repeating.
- Image `boot-ufskbd3.img` = boot.img `8c078f41…225f` (Image.gz
  `ccdb8689…`, DTB `f5397256…` unchanged). Config unchanged; rule 5 checks
  pass. UFS power-mode change only; escapes as on ufskbd2.
- Result (user flashed `boot-ufskbd3.img` `8c078f41…`, kernel #6): no
  0x15d4 error; link still HS_GEAR3 / RATE_B / 2 lanes / FAST_MODE. LED:
  user saw ~2 s of rapid blinking (init's fast-feed timer while waiting
  for USB, then the code), then off (brightness 0, diag code 5).
  "Acceptable for now."

## 2026-11-25 — fn1: Fn layer on the console — PRE-FLASH CHECK

- Stock layout source: Android has no device kcm (system/vendor/product
  keylayout + keychars are Generic/qwerty/Virtual only). Planet's layouts
  ship in `system/app/Planet_Keyboard` (IME): res/raw/
  keyboard_layout_*_gemini.kcm, the same set as Gemini/Cosmo. Extracted on
  Monolith (~/Build/astro-extract, lpunpack of p0/super.bin; not in repo).
- `english_us_intl_gemini.kcm` fn: 1-0 = ~ ` £ € < > [ ] { }, I/O/P =
  + - =, J/K/L = _ ; ", APOSTROPHE = :, M = ', arrows = PgUp/Home/PgDn/
  End. Base layer: APOSTROPHE key = \ |, Shift+, = /, Shift+. = ?,
  Shift+Backspace = forward delete. **Identical to gemini-debian's xkb
  `cosmo(us)`** (level 3 = Fn), so the rootfs can reuse the Cosmo layout.
  UK kcm differs (1-3 = | # \, K = @, L = ;, M = `).
- Console: `bin/make-defkeymap.py` writes delta
  `drivers/tty/vt/defkeymap.c_shipped` = base table with only these
  entries changed (Fn = KEY_LEFTMETA = AltGr in all 7 maps; altgr map =
  kcm fn; base/shift differences above). No userspace keymap tools.
- astro-console: a keypress (i2c8 interrupt count) now counts as
  activity, so typing wakes the panel like a kernel message.
- Image `boot-fn1.img` = boot.img `5f3808ef…7d35` (Image.gz `4ebf0215…`).
  Console keymap + init helper only; config/DTB unchanged; escapes as on
  ufskbd2/3.
- Result (user flashed `boot-fn1.img` `5f3808ef…`): **Fn keys working.**
  User: Esc shares the power key; wants Esc for presses up to 1.5 s and
  power beyond, as on the Cosmo.

## 2026-11-25 — Esc/power key: read-only look at the MT6359P

- The key is the PMIC PWRKEY (no Esc in the AW9523 matrix). Read-only
  PMIC reads by hand through pwrap WACS2 (`/tmp/pmicrd`, mainline
  pwrap_read16 ARB protocol: idle → CMD=addr → WFVLDCLR → SWINF_2_RDATA
  → VLDCLR; no PMIC writes). pwrap INIT_DONE2 = 1 (LK/ATF set it up).
  - HWCID 0x8 = 0x5930 (MT6359P).
  - TOPSTATUS 0x2a = 0x000e; bit 1 = PWRKEY debounce, 0 = pressed.
    User pressed 3 taps + a "2 s" hold: 0.26 / 0.22 / 0.26 s and
    **1.59 s** (a deliberate 2 s hold measured 1.6 s).
  - STRUP_CON12 0xa12 = 0x21e0 (bit 13 PWRKEY_RST_EN set: the 10 s escape).
  - TOP_RST_MISC 0x14a = 0x0225; 0x14c reads 0x0000. **Vendor map:
    0x14a = TOP_RST_MISC, 0x14c = its SET alias, 0x14e = CLR.** Mainline
    `MT6359_TOP_RST_MISC 0x14c` is the SET alias; mtk-pmic-keys does a
    read-modify-write there at every probe (lp_reset_setup).
  - PSC_TOP_INT_CON0 0x910 = 0x0025.
- Vendor PMIC interrupt: pio EINT 214 level-high (stock DTB), pwrkey /
  pwrkey_r hwirqs 0x30 / 0x32.
- Mainline pwrap probe on mt6873 (mt6873_regs defines 8 registers):
  skips init when INIT_DONE2 is set, but writes WDT_SRC_EN (undefined
  index → offset 0), TIMER_EN = 3, INT_EN = BIT4|BIT5 and its IRQ handler
  uses undefined INT_FLG/INT_CLR (offset 0). Same as on MT8192
  Chromebooks; unverified against this ATF/SSPM.

## 2026-11-25 — end of session: burn-in bug found

- init's 30 s "alive" kmsg line counts as console activity in
  astro-console, so the idle blank (60 s) never fires and the console has
  been lit all along on every image since console1. To fix first next
  session (AGENTS.md next candidates 00). Blanking the panel from here
  was refused by the session's permission check; handed to the user.

## 2026-11-25 — chg1: i2c5 bus for the MT6360 charger; burn-in fix — PRE-FLASH CHECK

- Goal: stop the battery draining under our kernel. First find out
  whether the MT6360 charges at all with no Linux driver.
- What we know without new writes: MT6359P `CHR_CON0` 0xa88 = 0x0001
  (RGS_CHRDET: VBUS seen, Monolith port). Gauge `FGADC_CUR_CON0` 0xd8a =
  0xfe50 and CAR 0xd16/0xd18 did not move in 5 s: latched values that
  need a PMIC write (FG_SW_READ_PRE) to refresh, so not read further.
- Vendor MT6360 charger DT (mt6360.dtsi): ichg 2.0 A, aicr 3.2 A, mivr
  4.4 V, cv 4.4 V, ieoc 150 mA, safety timer 12 h, **en_wdt = 1** (the
  vendor kernel kicks a charger watchdog; what the charger does when
  nobody kicks it is what to read first).
- DTS: `&i2c5` okay, 400 kHz, no children (single-channel controller,
  vendor reg size 0x1000, no ch_offset). SCL5/SDA5 GPIO202/203 already
  mode 1 (MODE25 0x11111111 read on the running board).
- astro-console ignores init's "astro-init: alive" kmsg lines
  (AGENTS.md item 00): the 60 s idle blank fires again.
- Image `boot-chg1.img` = boot.img `d9df3c73…b06e`. Image.gz `4ebf0215…`
  unchanged from fn1, DTB `ad6a9cfe…`, initramfs `7e27bde1…`.
- Pre-flash check: no PMIC/pwrap/keys/watchdog/reset/display change
  (rule-5 checks in build-boot-img.sh pass). i2c5 probe only resets the
  AP I2C controller; nothing on the bus is written by the kernel.
  Escapes as on fn1 (kernel identical). Plan after boot: read-only
  `i2cget`/`i2cdump` of MT6360 PMU 0x34 (charger status, HZ/CHG_EN,
  AICR/ICHG, watchdog) — no i2cset without a written check.
- Result (user flashed `boot-chg1.img` `d9df3c73…`, kernel #7 as fn1):
  booted; i2c5 = /dev/i2c-1, `i2cdetect -r` finds 0x1a, 0x34, 0x4e,
  0x64. Read-only `i2cdump -f 1 0x34` (no writes), decoded against
  mainline mt6360_charger.c and the vendor mt6360_pmu_chg.h:
  - CHG_CTRL1 0x11 = 0x00: no HZ, no force sleep, no OTG.
  - CHG_CTRL2 0x12 = 0x1b: **CHG_EN = 1**, CFO_EN, TE_EN, IINLMTSEL = AICR.
  - CHG_CTRL3 0x13 = 0x22: **AICR 500 mA** (sel 8), ILIM_EN 0.
  - CHG_CTRL7 0x17 = 0x10: **ICHG 500 mA** (sel 4). CV 0x14 = 0x5a: 4.35 V.
    MIVR 0x16 = 0x0d: 4.5 V. IEOC 0x19 = 0x3c: 250 mA.
  - CHG_CTRL12 0x1c = 0x02: safety timer enabled; timer field 0 (by
    the vendor table {4,6,…} h that is 4 h; field position not checked).
  - CHG_CTRL13 0x1d = 0x52: **charger watchdog off** (bit 7 = 0); nothing
    needs kicking.
  - DEVICE_TYPE 0x22 = 0x50: BC1.2 off (USBCHGEN 0); USB_STATUS1 0x27 =
    0x60 → type 6 = "BC1.2 disabled".
  - **CHG_STAT 0x4a = 0x62: charge in progress, VBAT_LVL = 1 (fast charge).**
  So the MT6360 charges with no Linux driver, at LK's safe defaults
  (500 mA in, 500 mA to the battery). Whether the battery gains net
  charge under our load is not measured (gauge needs a PMIC write;
  MT6360 ADC needs a conversion start = a write).

## 2026-11-25 — chg2: MT6360 on mainline drivers — PRE-FLASH CHECK

- Direction (user): drivers as mainline-ready as possible; shell pokes are
  for learning only. Vendor BSP = reference for values, not code.
- Read-only audit on chg1 (i2ctransfer to 0x1a/0x64, 1-byte CRC reads;
  enable = bit 6 of the CTRL register, vsel via mainline tables):
  | rail | vendor name | en | vsel | V |
  |---|---|---|---|---|
  | BUCK1 | VMDLA | on (0xc4) | 0xa5 | 1.125 V |
  | BUCK2 | VDRAM1 | on (0xc4) | 0x5a | 0.75 V |
  | LDO6 | VMDDR | on (0xc4) | 0x25 | 0.75 V |
  | LDO7 | VDRAM2 | on (0xc4) | 0x10 | 0.60 V |
  | LDO1 | VFP | off (0x80) | 0x40 | 1.8 V |
  | LDO2 | VTP | off (0x80) | 0x40 | 1.8 V |
  | LDO3 | VMC | off (0x80) | 0xb0 | 3.0 V |
  | LDO5 | VMCH | off (0x80) | 0x25 | 2.95 V |
  DRAM rails live on the MT6360: they must stay always-on and in range.
- GPIO24 (IRQB): mode 0, input, SMT, pull-up, **reads 0** (MT6360 holds
  an unserviced interrupt). FOD_STAT 0xe7 = 0x94: CHRDET_EXT = VBUS on
  the right port (vendor aeonusb.c: both ports charge).
- DTS: `pmic@34` "mediatek,mt6360" (IRQB GPIO24 edge-falling as vendor
  and mainline boards; pinctrl = the state LK leaves), `charger`
  (vinovp 6.5 V = LK's CTRL19 value = driver default; OTG boost regulator
  described, not enabled), `regulator` (vendor names/ranges, every range
  contains LK's voltage; BUCK1/BUCK2/LDO6/LDO7 always-on). No adc node
  (bound by MFD cell name; the MFD binding has no adc child). No TCPC,
  no LEDs. Binding nit for upstream: mfd yaml says `regulators`, driver
  and in-tree DTs use `regulator`.
- Config: CHARGER_MT6360=y, MEDIATEK_MT6360_ADC=y (MFD/REGULATOR already
  =y from defconfig), TYPEC_MT6360=n.
- Image `boot-chg2.img` = `85613d6b…5542`; Image.gz `639597f3…`, DTB
  `aebbc537…`; initramfs contents unchanged from chg1 (hash differs by
  cpio mtimes only; init/astro-console/astro-disp compared).
- Pre-flash check — what this kernel writes, all on the MT6360 (i2c5),
  nothing on the MT6359P (pwrap still off, rule-5 checks pass):
  - core: masks and acks all MT6360 interrupts (regmap-irq init).
  - charger probe: CHG_CTRL19 VINOVP (same value), DEVICE_TYPE USBCHGEN
    0 then 1 (BC1.2 detection runs on D+/D- once, VBUS present),
    CHG_CTRL2 IINLMTSEL = AICR (same), CHG_CTRL3 ILIM_EN = 0 (same),
    CHG_CTRL10 OTG OC = 3 A (OTG off). Charging stays enabled; AICR/ICHG
    untouched (500 mA / 500 mA).
  - regulators: no write (in range, always-on ones already on).
  - MT6360 reset functions (QONB/MRSTB/AP-watchdog reset) not touched.
  Risks: BC1.2 may drop the USB shell for a moment (host re-enumerates);
  a regulator surprise could hang the board → watchdog/power-key escape,
  then reflash chg1. New kernel → re-observe the power-key escape.
- After boot: dmesg mt6360; /sys/class/power_supply/mt6360-chg*;
  /sys/bus/iio (VBAT, IBAT); /sys/kernel/debug/regulator/summary; GPIO24
  high again; IRQ count changes on unplug/replug.
- Result (user flashed `boot-chg2.img` `85613d6b…`, kernel #8): boots,
  USB shell up (BC1.2 did not drop it). dmesg: no mt6360 errors (adc/
  led/tcpc "Failed to locate of_node" = MFD cells without a DT node, as
  intended; tcpc/led have no driver).
  - power_supply `mt6360-chg.1.auto`: online 1, **status Charging,
    charge_type Fast**, usb_type **SDP** (BC1.2 ran: attach_i fired once),
    ICHG 500 mA, AICR 500 mA, CV 4.35 V, MIVR 4.5 V, IEOC 250 mA.
  - ADC (iio:device0, raw × scale): **VBAT 4.340 V**, VSYS 4.348 V,
    **IBAT 265 mA** (charge current into the battery), IBUS 398 mA,
    VBUS 4.97 V, junction 25 °C. The battery was not drained: near CV.
  - GPIO24 now reads **1** (IRQB released: interrupts serviced).
  - regulator_summary: vmdla 1125, vdram1 750, vmddr 750, vdram2 600 mV
    on; vfp 1800, vtp 1800, vmc 3000, vmch 2950 mV off; otg 5050 mV off.
    Identical to the pre-flash audit.
- chg1 burn-in fix **confirmed** by the user: the panel blanked after
  about 1 min idle (AGENTS.md item 00 closed).
- Replug test (user unplugged/replugged the right port twice, uptime
  ~238 s): mt-eint 24 = 7, chrdet_ext_evt = 4 (2 × out + in), attach_i
  = 3 (boot + 2), usb_type SDP again, USB shell back by itself. Then
  **status Full** (termination), VBAT 4.277 V, IBAT 0, IBUS 162 mA (the
  board on USB power, battery idle).
- User: the **red charging light** comes on at every boot and on each
  replug. That is the MT6360 LED1 in hardware charge-indicator mode
  (vendor DT rgbled trigger "cc_mode"), no driver involved. When
  leds-mt6360 is enabled, LED1 must stay in hardware/CC mode or the
  charge light is lost.
- Power-key escape **re-observed on chg2** (kernel #8): user held power
  ~10 s, board reset, next boot `androidboot.bootreason=reboot_longkey`,
  charger back to Charging. (Watchdog path unchanged; not re-run.)

## 2026-11-25 — pmicA: pwrap + MT6359P core (step 2, image A) — PRE-FLASH CHECK

- Plan and register audit: `docs/pmic-plan.md` (user approved: Esc/power
  split in userspace as on the Cosmo; clean the WDT_SRC write; image A
  before image B).
- Delta `drivers/soc/mediatek/mtk-pmic-wrap.c` (upstreamable):
  `mt6873_regs` gains `PWRAP_INT_FLG` 0x450 / `PWRAP_INT_CLR` 0x454
  (vendor PMIF IRQ_FLAG_3/IRQ_CLR_3); `pwrap_mt6873.wdt_src = 0` and the
  probe skips the WDT_SRC_EN write when `wdt_src` is 0 (mt6873 has no
  such register; mainline and stock both wrote 0xffffffff to offset 0).
  mt8195_regs has the same gap (not changed, can't test).
- DTS: `&pwrap` okay with one child `pmic` "mediatek,mt6359" (EINT 214
  level high, interrupt-controller), no function nodes.
- Config: MTK_PMIC_WRAP=y, MFD_MT6397=y; off: KEYBOARD_MTK_PMIC,
  REGULATOR_MT6359 (was y from defconfig), RTC_DRV_MT6397,
  MEDIATEK_MT6359_AUXADC, SND_SOC_MT6359 (+ the three Chromebook machine
  drivers that select it), SND_SOC_MT6359_ACCDET, SPMI_MTK_PMIF,
  REGULATOR_MT6315.
- Rule-5 guard narrowed (bin/build-boot-img.sh): pwrap allowed only with
  the delta in the built source, exactly one child `pmic` =
  "mediatek,mt6359" with no children, keys/long-press refused, none of
  the MT6359 function drivers in the config. Negative test: a
  `regulators { };` child under pmic → "REFUSING (mt6359 node has
  children)". Found and fixed on the way: `grep -E` has no `\t`.
- Images: `boot-pmicA.img` `afdbac95…8948`, `boot-pmicA-wdtest.img`
  (`astro.wdtest=1`) `44c35a35…905d`; Image.gz `38591225…`, DTB
  `0eccd504…`.
- Pre-flash check — writes this kernel makes:
  - pwrap MMIO: TIMER_EN 0x3E0 = 3 (is 3), INT_EN 0x448 = 0x30 (is 0),
    clock parent osc_d10 (is osc_d10); handler clears 0x454 only if a
    pwrap interrupt fires. No WDT_SRC write, no pwrap init (INIT_DONE 1).
  - MT6359P: **0 to the 10 interrupt-enable registers** (pmic-plan
    table: LDO_TOP_INT_CON0/1 0xffff/0x3fff and PSC_TOP_INT_CON0 0x25 are
    the only nonzero ones); status W1C only if a PMIC interrupt fires.
    Reads: SWCID. **Nothing touches 0xa12 (STRUP_CON12) or 0x14a/0x14c.**
  - MT6360, USB, UFS, keyboard, display: as chg2.
  Escapes to re-observe: power-key hold (normal image), watchdog
  (`boot-pmicA-wdtest.img`). Rollback: `boot-chg2.img`.
- After boot, first: `/tmp/pmicrd 0xa12 0x14a` (expect 0x21e0, 0x0225)
  before any reset; then the IRQ-enable table, pwrap/PMIC IRQ counts (no
  storm), probe log.
- Result (user flashed `boot-pmicA.img` `afdbac95…`, kernel #9): boots,
  shell up. Probe: mt-pmic-pwrap and mt6397 bound; mt6359 cells without
  DT nodes log "Failed to locate of_node" (intended). Read-only, at 22 s:
  **0xa12 = 0x21e0, 0x14a = 0x0225, 0x14c = 0** (unchanged); HWCID
  0x5930; all 10 IRQ-enable registers 0; TOP_INT_STATUS0 0; PMIF
  INIT_DONE 0x1 (no WDT_SRC write), TIMER_EN 3, INT_EN 0x30, IRQ_FLAG_3
  0. IRQ counts: pwrap (GIC 252) 0, mt6358-irq (EINT 214) 0.
- Power-key escape **observed on pmicA** (kernel #9, pwrap + MT6359P core
  running): user held the power/Esc key, board reset, next boot
  `androidboot.bootreason=reboot_longkey`.
- Watchdog escape **observed on pmicA** (user flashed
  `boot-pmicA-wdtest.img` `44c35a35…`, init never feeds the watchdog):
  the board resets by itself and cycles. Monolith kernel log, Astro
  USB: gadget up 13:37:07 → disconnect 13:37:56 → preloader 13:37:59;
  gadget up 13:38:21 → disconnect 13:39:10 → preloader 13:39:13 (~49 s
  from gadget to reset each time). Shell not reached (reset comes before
  DHCP). Both escapes now observed with pwrap + MT6359P core running.
- Back on `boot-pmicA.img` after the wdtest (user), bootreason PowerKey.

## 2026-11-25 — pmicB: power key on mtk-pmic-keys (step 2, image B) — PRE-FLASH CHECK

- Delta `drivers/input/keyboard/mtk-pmic-keys.c` (upstreamable):
  `mt6359p_regs` with the long-press reset in STRUP_CON12 0xa12
  (RST_EN bit 13, KEY_MODE bit 12 = two-key, TD bits 15:14), chosen when
  `MT6359P_HWCID` ≥ `MT6359P_CHIP_VER` (the check mt6359-regulator.c
  already makes); for it `power-off-time-sec` is real seconds through
  the BSP table {8, 11, 14, 5} (absent/unknown = timeout untouched).
  Plain-MT6359 table unchanged (also wrong, untestable here).
- DTS: `pmic/keys` "mediatek,mt6359-keys", long-press-mode 1,
  power-off-time-sec 8, `power` = KEY_ESC + wakeup-source.
- Config: KEYBOARD_MTK_PMIC=y. Guard: keys allowed only as exactly
  `keys { power { } }` with mode 1 / 8 s and the delta in the built
  source. Negative tests: mode 0 → refused; 5 s → refused.
- Images: `boot-pmicB.img` `e5e1299e…1a44`, `boot-pmicB-wdtest.img`
  `d44e9304…9e75`; Image.gz `167fc6a7…`, DTB `b405c43d…`.
- Pre-flash check — new writes vs pmicA (all MT6359P):
  - HWCID 0x8 read (0x5930 → MT6359P table).
  - PSC_TOP_INT_CON0 0x910: PWRKEY + PWRKEY_R enables (bits 0, 2) set
    (intsel update + IRQ enable); was 0x25 under LK, 0 on pmicA.
  - STRUP_CON12 0xa12: read-modify-write, mask 0xf000, value 0x2000.
    0xa12 = 0x21e0 → bits 15:12 already 0x2 → **no write**
    (regmap_update_bits skips unchanged values).
  - On key events: TOPSTATUS 0x2a read, PSC status W1C (MFD handler).
  Nothing else changes. Esc reaches the console; holding still resets
  the board at ~8–10 s (PMIC hardware). After boot, first: 0xa12 again.
  Escapes: power-key hold, watchdog (wdtest image). Rollback: pmicA.
- Result (user flashed `boot-pmicB.img` `e5e1299e…`, kernel #10): boots;
  `mtk-pmic-keys` = input0/event0 under 10026000.pwrap:pmic/mt6359-keys.
  Read-only at 19 s: **0xa12 = 0x21e0** (driver wrote nothing), 0x14a
  0x0225, 0x14c 0, PSC_TOP_INT_CON0 0x910 = 0x0005, TOPSTATUS 0x000e.
- Key test (user: 3 taps + ~2 s hold, twice). Round 1: keys IRQ 48/50 =
  4/4, EINT 214 = 24, pwrap IRQ 0 (busybox hexdump can't read evdev:
  EINVAL on short reads). Round 2 (dd bs=24): EV_KEY **KEY_ESC** press/
  release ×4, held 0.39 / 0.26 / 0.27 / **1.74 s**; IRQs 8/8; 0xa12 still
  0x21e0.
- Power-key escape **observed on pmicB** (kernel #10, keys driver bound):
  user held the key, board reset, next boot `bootreason=reboot_longkey`.
- Watchdog escape **observed on pmicB** (user flashed
  `boot-pmicB-wdtest.img` `d44e9304…`): Monolith USB log, gadget up
  13:55:23 → reset 13:56:11; gadget up 13:56:36 → reset 13:57:25 (48–49 s,
  as on pmicA; each reset re-enumerates the preloader twice). **Step 2
  done: pwrap + MT6359P core + power key on mainline drivers (two
  upstreamable deltas), both escapes observed on A and B.**
- Back on `boot-pmicB.img` (user), kernel #10, no wdtest, bootreason PowerKey, charger Full.

## 2026-11-25 — Step 3A: battery percentage (AUXADC + adc-battery) — PRE-FLASH CHECK

- Read-only look (kernel #10): MT6360 VBAT 4.27 V, IBAT 0 at Full
  (charge-only). MT6359P FG on (0xd08 = 0x2359, FG_ON); FG_CURRENT_OUT
  0xd8a = 0xfe4c (−266 mA) and CAR 0x0113776f frozen over 20 s: LK's last
  latch, not a live drain. LK /chosen: boot_voltage 4230, fg_swocv_v
  42089 (4.2089 V), fg_swocv_i −2630 (−263 mA), imix_r 214.
- Stock DTB battery profiles = vendor source tables (all five equal).
- Plan, deltas, register audit, guard and images: `docs/pmic-plan.md`
  "Step 3". Guard negative tests: 5/5 refused, control passes.
- Images: `boot-bat3a.img` `b812f105…0b97`, `boot-bat3a-wdtest.img`
  `7d04e984…b4fe`. Pre-flash register snapshot
  `backup/pre-bat3a-auxadc-regs.txt` (0xa12 = 0x21e0). Not flashed yet.
- Result (user flashed `boot-bat3a.img` `b812f105…`, kernel #11): boots,
  bootreason PowerKey. **0xa12 = 0x21e0.** Register diff vs the pre-flash
  snapshot (`backup/post-bat3a-auxadc-regs.txt`): only result registers
  (AUXADC_ADC0/3/19/22 cleared by the reset, ADC30 and IMP3 new
  samples); every config register (AUXADC_CON0–20, DIG_3_ELR trims,
  LBAT, NAG, HK_TOP) unchanged.
- Readings on USB, charger Full: MT6359 VBAT raw 22242 × 0.19226 =
  **4276 mV** vs MT6360 VBAT 4272.5 mV (4 mV apart; mainline scale fix
  confirmed). IBAT −2…+1 mA (charger terminated, system on VBUS).
  adc-battery: **capacity 92 %**, voltage_ocv 4.275 V, status
  "Not charging" (helper's Full needs OCV > CV − 38 mV = 4.312 V).
- Note: rest voltage 4.276 V = 92 % of the stock profile because the
  charger terminates at CV 4.35 V (LK's setting); stock battery_cv is
  4.40 V. Not changed.
- BAT_TEMP raw 826 × 1.0986 = 907 mV → 24 kΩ·V/(2.8 V − V) = 11.5 kΩ ≈
  21–22 °C for a 10 kΩ B≈3435 NTC (plausible room temperature; 3B input).
- LK cmdline `has_battery_removed=1` this boot; also seen on earlier
  boots before any PMIC driver (usb1 logs), so not new.
- Unplug test (user, 90 s off USB, typing; logger every 2 s in /tmp):
  current_now **−187…−253 mA** (mean ≈ −200 mA) with status
  Discharging; replug → **+273…+292 mA**, status Charging, charger
  Charging (recharge after the dip). IBAT sign and scale confirmed.
  Terminal V fell 4.273 → 4.194–4.216 V under load while voltage_ocv
  moved only 4.2551 → 4.2523 V; capacity 91 → 90 → 91 %, no jumps.
  Board stayed up through both unplugs (uptime vs Monolith USB log).
  Idle draw on battery ≈ 200 mA (panel blanked, cpuidle.off=1).
- Earlier "previous boot" ramoops was stale (kernel #10 pmicB wdtest).
- To fix in the next image: stock IR compensation uses profile R +
  R_FG 5 mΩ + FG_METER_RESISTANCE 10 mΩ (0.1 mΩ units, stock DTB 0x64);
  factory-internal-resistance should be ~105 mΩ, not 90 mΩ.
- Power-key escape **observed on bat3a** (kernel #11, AUXADC +
  adc-battery running): user held the key, board reset, next boot
  `bootreason=reboot_longkey`; 0xa12 = 0x21e0; capacity 92 % at boot.
- Watchdog escape **observed on bat3a** (user flashed
  `boot-bat3a-wdtest.img` `7d04e984…`): Monolith USB log, gadget up
  14:43:45 → reset 14:44:33; up 14:44:58 → reset 14:45:47; up 14:46:12
  (48–49 s each, preloader enumerates twice per reset, as on pmicA/B).
  **Step 3A done: battery percentage on mainline drivers (three
  upstreamable deltas), both escapes observed.**

## 2026-11-25 — Step 3B: battery temperature — PRE-FLASH CHECK

- Stock NTC = mainline NCP15XH103 table; formula = ntc_thermistor
  connected-ground. Deltas, audit and images: `docs/pmic-plan.md`
  "Step 3B". Images `boot-bat3b.img` `9328ef42…2e27`,
  `boot-bat3b-wdtest.img` `dbca9572…a62e` (on Monolith). Guard re-pinned
  and re-tested (changed source refused). Not flashed yet.
- Result (user flashed `boot-bat3b.img` `9328ef42…`, kernel #12): boots,
  bootreason PowerKey, **0xa12 = 0x21e0**. `ntc-thermistor` probed
  (iio:device2 ncp15xh103, hwmon1). batt_temp raw 814 × 1.0986 =
  894.3 mV → 11262 Ω → 21.97 °C by hand; driver 21968 m°C (IIO), 21920
  (hwmon), `adc-battery` TEMP **220** (22.0 °C, unit fix confirmed).
  Capacity 92 %, OCV 4.274 V, I −2 mA, Not charging (charger Full).
- Power-key escape **observed on bat3b** (kernel #12): user held the key,
  board reset, next boot `bootreason=reboot_longkey`; 0xa12 = 0x21e0.
- Watchdog escape **observed on bat3b** (user flashed
  `boot-bat3b-wdtest.img` `dbca9572…`): Monolith USB log, gadget up
  14:56:47 → reset 14:57:35; up 14:58:01 → reset 14:58:49; up 14:59:14
  (48 s each). **Step 3B done: battery temperature on mainline drivers,
  both escapes observed.**

## 2026-11-25 — Why the charger stops at 4.35 V

- LK sets it: every saved LK log has `mt6360_chg_init_setting: starts` →
  `mt6360_set_cv: cv = 4350` (expdb/try1*, backup/). LK's built-in
  value: its own embedded DTB (= stock DTB) says `cv = <4400000>` on
  `mediatek,mt6360_pmu_chg` and `battery_cv = <4400000>`.
- Stock Android raises it: `mtk_charger` SW JEITA, normal band 10–45 °C
  → `sw_jeita.cv = 0` → `battery_cv` 4.40 V (`jeita_temp_t2_to_t3_cv`
  4.34 V is never used in that band; 4.24 V above 45 °C and 0–10 °C,
  4.04 V below 0 °C).
- Mainline `mt6360_charger` never writes VOREG (no init, no
  monitored-battery), so LK's 4.35 V stays.

## 2026-11-25 — root1: Debian on userdata — first boot

- User flashed `userdata` (`astro-debian-rootfs.img` `1d745041…`,
  gemini-debian `7785797`) + `boot_a` (`boot-root1.img` `0f0fda93…`).
  Booted to Debian 13 trixie, logged in on the panel; SSH from Hydra via
  `-J` Monolith. Handoff `last state: none` → tripwire **OK** after
  multi-user; `is-system-running` = running, no failed units; root
  /dev/sdc56 grown to 111 GiB (growfs); RuntimeWatchdogUSec 30 s;
  panic_on_oops 1; usb0 10.15.21.1 default via Monolith (NAT profile
  `astro-usb` there, tested from rescue: ping + DNS ok). Battery 92 %.
- **Bug: every sdc partition was writable** under Debian (sysfs `ro` = 0;
  sda/sdb ro = 1). Cause: UFS came up late this boot (4.48 s); the handoff
  found userdata in sysfs and ran 2 ms later, but `ufs_ro` walked /dev/sd*,
  where devtmpfs had not made most sdc nodes yet. Nothing wrote them (no
  tool in the image targets them). Fix (boot-root2): ufs_ro walks
  /sys/class/block (mknod if a node lags), and a gate refuses the handoff
  unless every sd device but sdc + sdc56 reads back ro. Gate dry-run on
  the live system: "REFUSE (sdc1 not read-only)".
- Image `boot-root2.img` `2739e141…153c` (kernel/DTB = bat3b).
- root2 result (user flashed `boot-root2.img`): the gate **refused** the
  handoff ("sdc1 is not read-only: staying in the rescue initramfs") —
  the safe outcome. Real cause (also likely behind root1): a partition's
  sysfs `ro` reads 1 while its disk is read-only, and `ufs_ro` skipped
  devices that already read ro; sdc is visited before sdc1…, so no sdc
  partition got its own flag, and all came back writable with
  `--setrw sdc`. Fix (root3): `blockdev --setro` every sd device
  unconditionally. Tested in rescue (no mount): ufs_ro → setrw sdc, sdc56
  → gate PASS, writable exactly "sdc sdc56"; relock → none writable.
- User reported a power-key hold rebooting the board, but bootreason on the
  current boot was PowerKey (fresh power-on) and root2 never ran Debian:
  the power-key escape under Debian is still to be observed.
- Image `boot-root3.img` `abe341b1…29aa`.
- root3 result (user flashed `boot-root3.img` `abe341b1…`): handoff
  "UFS: only sdc + sdc56 writable (60 sd devices checked)", "booting
  Debian … (last state: OK)"; under Debian exactly sdc + sdc56 have
  sysfs ro = 0, the other 58 sd devices ro = 1. Tripwire OK, running,
  astro-console active.
