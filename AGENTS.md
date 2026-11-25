# AGENTS.md — astro-linux618: mainline Linux 6.18 LTS on the Astro Slide 5G

Read this first, then `docs/bringup-checklist.md`, `docs/hardware-map.md`
and `docs/session-log.md`.

Sister projects (same owner, same methods — reuse their code and lessons):
- `atzandrew/cosmo-linux618` — Cosmo Communicator (MT6771 on MT8183) on
  6.18. **The template for this repo**: build scripts, boot-image checks,
  escape rules, AW9523 keyboard, CONSYS Wi-Fi/BT, simpledrm-first display.
- `atzandrew/gemini-nixos` — Gemini PDA (MT6797) on 6.6. LK behaviour docs.
- `atzandrew/gemini-debian` — Debian 13 + Plasma 6 rootfs builder
  (`DEVICE=cosmo` today; an Astro target will be added).

## Status (2026-11-25, day 1, late)

Mainline 6.18.58-astro boots to our initramfs on the Astro from `boot_a`
(bootloader unlocked, orange). Working: LK handover (AVB footer, LK vendor
nodes, `dtbo_a` = `dtbo/astro-lk.dts`), both reset escapes **observed**,
USB device network + shell (`bin/astro-sh`), RAM log after a watchdog
reset, visible framebuffer console (our buffer at 0x70000000 pushed
through LK's command-mode DSI path by `initramfs/astro-disp` /
`astro-console`, idle blank after 60 s, `fbcon=rotate:1`).
- **UFS** (ufskbd1/2): mainline `ufs-mediatek` on the legacy MT6873 host
  (delta: legacy-IP guards), no VCC regulator (rule 5). SK hynix
  H9HQ15AFAMADAR: sda/sdb boot LUs, sdc 57 stock GPT partitions
  (boot_a sdc30, super sdc55, userdata sdc56). Partition reads verified
  against P0 backups. **Init sets every /dev/sd* read-only** unless
  `astro.ufsrw=1`; no write path decided yet.
- **Keyboard**: AW9523 at i2c8 0x5b, Cosmo driver and keymap, repeat
  delay 500 ms. i2c8 is a multi-channel I2C: the AP channel is at
  base+0x100 (`reg` in the DTS); mainline at base+0 times out.
  Fn = KEY_LEFTMETA; the Fn layer is userspace (gemini-debian, Cosmo).
- Power-key escape re-observed on this kernel (2026-11-25, reboot_longkey).
History and receipts: `docs/session-log.md`.

- **Console Fn layer** (kernel default keymap, Planet US layout =
  gemini-debian `cosmo(us)`).
- **MT6360 charger/ADC/regulators** (chg2, mainline drivers, DTS only):
  i2c5 `pmic@34`, IRQB GPIO24; power_supply `mt6360-chg.1.auto` (SDP,
  charging at LK's 500 mA / 500 mA), iio VBAT/IBAT/IBUS/VBUS. DRAM rails
  (BUCK2, LDO6, LDO7) and BUCK1 are MT6360 rails: always-on in the DTS,
  ranges audited against LK's voltages (session log "chg2").
- **Driver policy (user, 2026-11-25):** mainline drivers and bindings,
  small upstreamable deltas; vendor BSP is a reference for values only;
  shell register pokes are for learning, never the fix.

Next candidates:
00. ~~Burn-in bug~~ fixed in chg1 (astro-console ignores init's alive
   lines; user saw the 60 s blank, 2026-11-25).
0. **Esc/power key = step 2: pwrap + MT6359P core + keys.** Full plan,
   register audit and test order in `docs/pmic-plan.md` (for review,
   2026-11-25). Two upstreamable deltas: pwrap mt6873 INT_FLG/INT_CLR
   (0x450/0x454), mtk-pmic-keys MT6359P reset layout (STRUP_CON12 0xa12).
   Esc/power split in userspace as on the Cosmo (kernel reports KEY_ESC).
   Image A (pwrap + core) before image B (+ keys).
1. Root filesystem on UFS (userdata or super) → Debian via gemini-debian
   (Astro target; check the Astro's key legends for the Fn layer). Needs
   a decided write path and lifting the init read-only guard for that LU.
2. Display: mainline mediatek DRM with command-mode DSI + SH8802B panel
   driver (vendor `panel-sh8802b-vdo.c`: mode flags LPM|EOT, timings,
   DCS 0x51 backlight, 0x28/0x10 off). Must keep the burn-in rules below.
3. PMIC (MT6359P via pwrap): only after the power-key reset question in
   rule 5 is settled (STRUP_CON12 vs mainline's 0x14c).
4. Other i2c buses (i2c2/4/9 are multi-channel too: vendor
   ch_offset_default 0x100) — touch, charger.

Display / burn-in rule (AMOLED): never leave a static frame lit for long.
Default boot sends a black frame and the console blanks after 60 s idle;
display experiments must include their own blank-again path.

- `kernel/BASE` pins v6.18.58 (`2926d88bb7fc`), same as the Cosmo.
- Vendor source: Planet's 4.14.186 MTK BSP (`astro-kernel`, one commit
  `a79860700`), board = `k6873v1_64_defconfig` + `mt6873.dts` +
  `aeon_gpio.dtsi`. Vendor drivers worth reading: `drivers/phy/mediatek/
  phy-mtk-mt6873.c`, `drivers/gpu/drm/panel/panel-sh8802b-vdo.c`,
  `drivers/misc/mediatek/aw9523/`, `drivers/input/aeonusb/` (USB mux:
  right port = GPIO13 and GPIO127 low).

## Why this should work: MT6873 ≈ MT8192

The Astro's MT6873 (Dimensity 800) is the phone sibling of the Chromebook
MT8192, as the Cosmo's MT6771 was of MT8183. Mainline has no `mt6873`
anything; the board will ride on `mt8192.dtsi` and MT8192 drivers.
Receipts (2026-11-25, `docs/hardware-map.md`): 97 of mainline
`mt8192.dtsi`'s 102 addressed nodes are at identical addresses in the
vendor `mt6873.dts`; pin tables are 228 pins in both, function lists equal
except mainline's 8 extra GPIO-only entries (GPIO220–227).

## Talking to the running Astro (2026-11-25)

- **USB network + shell** (right-hand port, g_ether): the Astro is
  10.15.21.1, Monolith gets 10.15.21.2 by DHCP. `bin/astro-sh '<cmd>'`
  runs a command through Monolith (socat to the init's `nc` shell on port
  2323); `telnet 10.15.21.1` on Monolith is interactive.
- **RAM log after a reset**: ramoops/pmsg at 0x4d010000 survive a
  **watchdog** reset. Stop feeding the watchdog (or use an image with
  `astro.logreset=1`), then `mtk da peek 0x4d000000 0x100000 --filename
  f.bin` in the preloader window and unpack the zones (console at
  0x4d09f000, pmsg at 0x4d0df000).
- **LK log**: `mtk r expdb` (ring buffer; find a boot by its dtbo_size or
  zimage size).
- **Keyboard light**: heartbeat = kernel, fast blink = init feeding the
  watchdog, solid = wdtest, N blinks = USB diagnosis code (initramfs/init).

## Flashing host

The Astro is plugged into **Monolith** (192.168.0.235) by its **right-hand**
USB-C port (the only port that does ADB/MTP/download mode). All device
access (adb, mtkclient) runs on Monolith. This build machine (aarch64)
builds images and copies them over.

## Rules (inherited from cosmo-linux618 — read its AGENTS.md for history)

1. **Base + file-tree delta, no patch files.** Upstream pinned in
   `kernel/BASE`; changed/added kernel files live whole under
   `kernel/delta/` at their kernel-relative path; config fragment in
   `kernel/config/astro.config`.
2. **Record before you forget.** Every fact with a date and a receipt;
   every session in `docs/session-log.md`; every flash logs kernel release
   and image sha256.
3. **Panel rule.** LK initialises the panel. No mediatek DSI/display
   pipeline or panel init until the panel ID and init path are confirmed;
   first boots use LK's framebuffer via simpledrm.
4. **Never flash something you cannot identify or undo.** P0 backups first
   (`backup/` is gitignored: IMEI/NVRAM/seccfg are device-unique and this
   repo is public).
5. **Never flash an image that can strand the device.** Every experimental
   image needs a power-key reset and a watchdog reset that have been
   **seen to fire**. Status (2026-11-25, `docs/session-log.md`):
   - **Watchdog: observed** with our kernel (try1c `astro.wdtest=1`, init
     never feeds it: board resets, next boot `lk boot reason = 4`).
   - **Power key ~10 s: observed** with our kernel running (normal image,
     init feeding the watchdog) and before the kernel (mtk DA mode).
   - **LK panic → watchdog reset: observed** (try1, try1b).
   These hold only while nothing in Linux reaches the MT6359P: its
   power-key reset lives in `STRUP_CON12` (0xa12) and mainline
   `mtk-pmic-keys` writes 0x14c, a different register on this PMIC.
   `bin/build-boot-img.sh` refuses a DTB with pwrap/mt6359/keys enabled
   and a kernel with the pwrap or PMIC keys driver. Changes touching PMIC
   keys, watchdog, reset path, display/panel or a new kernel config need
   an explicit yes to a written pre-flash check; a change touching any of
   these re-opens the matching escape test.
6. After an mtk write the board stays in download mode until reset by hand;
   `mtk reset` may power the board off (it did on the Cosmo).

## Open questions blocking first boot (P0 — answer from the device)

1. Bootloader **locked** (green), **A/B** slot a, boot + vendor_boot + dtbo (answered 2026-11-25). Still open: boot header version,
   and what LK does with `dtbo` overlays on
   our DTB.
2. ~~LK framebuffer / panel~~ answered 2026-11-25: 0x7dd80000, pitch 4352, eBGRA8888; panel **SH8802B, DSI command mode** (see p0-findings). Was: (the
   defconfig's `td4330_fhdp_dsi_cmd_auo_rt5081` is the MTK reference).
3. LK-injected `/reserved-memory` and `/chosen` (dump `/proc/device-tree`).
4. ~~Storage~~ **UFS** (answered 2026-11-25, `docs/p0-findings.md`).
5. Power-key reset on MT6359P: control is STRUP_CON12 0xa12 bit 13 (mainline keys driver writes a different reg, 0x14c — keep disabled); preloader value,
   mainline behaviour. Watchdog left running by LK?
6. Console: any UART pad? Otherwise framebuffer + ramoops/expdb.

## Where things live

| Path | What |
|---|---|
| `kernel/BASE` | upstream pin |
| `kernel/delta/` | changed/added kernel files, kernel-relative |
| `kernel/config/astro.config` | config fragment over arm64 defconfig |
| `bin/build-kernel.sh` | build (`dtbs` arg = DTB only) → `out/` |
| `bin/build-dtbo.sh` | `out/dtbo.img` from `dtbo/astro-lk.dts` (NOOP=1: no-op) + both LK overlay passes checked offline |
| `bin/build-boot-img.sh` | `out/boot.img`: boot v2 + DT table + AVB footer; refuses PMIC/display/overlay hazards |
| `bin/astro-sh` | run a shell command on the Astro over USB via Monolith |
| `dtbo/` | LK board-config overlay (`astro-lk.dts`) and the no-op overlay |
| `initramfs/init` | bring-up init: watchdog owner, LED codes, USB network/shell, diagnostics |
| `docs/flashing.md` | mtk procedure and stock restore |
| `docs/bringup-checklist.md` | every hardware block, status and the order to do the rest |
| `docs/hardware-map.md` | SoC/board map and mainline status |
| `docs/session-log.md` | dated log of every session |
| `backup/` | P0 partition backups (gitignored, never pushed) |
