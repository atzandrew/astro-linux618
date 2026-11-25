# AGENTS.md — astro-linux618: mainline Linux 6.18 LTS on the Astro Slide 5G

Read this first, then `docs/hardware-map.md` and `docs/session-log.md`.

Sister projects (same owner, same methods — reuse their code and lessons):
- `atzandrew/cosmo-linux618` — Cosmo Communicator (MT6771 on MT8183) on
  6.18. **The template for this repo**: build scripts, boot-image checks,
  escape rules, AW9523 keyboard, CONSYS Wi-Fi/BT, simpledrm-first display.
- `atzandrew/gemini-nixos` — Gemini PDA (MT6797) on 6.6. LK behaviour docs.
- `atzandrew/gemini-debian` — Debian 13 + Plasma 6 rootfs builder
  (`DEVICE=cosmo` today; an Astro target will be added).

## Status (2026-11-25)

Bootloader **unlocked** 2026-11-25 (orange). Our 6.18 kernel boots to init from `boot_a` (both escapes observed). `dtbo_a` = `dtbo/astro-lk.dts` (LK applies dtbo to its own DTB and to ours; this overlay carries the stock display config and lands in `/lk-sink` on ours): LK brings the panel up as stock, and Linux then holds it in reset (GPIO42 hog) as a burn-in guard. No Linux display output yet (SH8802B command mode).
- `kernel/BASE` pins v6.18.58 (`2926d88bb7fc`), same as the Cosmo.
- Vendor source: Planet's 4.14.186 MTK BSP (`astro-kernel`, one commit
  `a79860700`), board = `k6873v1_64_defconfig` + `mt6873.dts` +
  `aeon_gpio.dtsi`.

## Why this should work: MT6873 ≈ MT8192

The Astro's MT6873 (Dimensity 800) is the phone sibling of the Chromebook
MT8192, as the Cosmo's MT6771 was of MT8183. Mainline has no `mt6873`
anything; the board will ride on `mt8192.dtsi` and MT8192 drivers.
Receipts (2026-11-25, `docs/hardware-map.md`): 97 of mainline
`mt8192.dtsi`'s 102 addressed nodes are at identical addresses in the
vendor `mt6873.dts`; pin tables are 228 pins in both, function lists equal
except mainline's 8 extra GPIO-only entries (GPIO220–227).

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
| `bin/` | build and device scripts (to port from cosmo-linux618) |
| `docs/hardware-map.md` | SoC/board map and mainline status |
| `docs/session-log.md` | dated log of every session |
| `backup/` | P0 partition backups (gitignored, never pushed) |
