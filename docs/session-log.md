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
