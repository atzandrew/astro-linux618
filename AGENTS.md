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
- **pwrap + MT6359P + Esc key** (pmicB): see next candidates 0.
- **Driver policy (user, 2026-11-25):** mainline drivers and bindings,
  small upstreamable deltas; vendor BSP is a reference for values only;
  shell register pokes are for learning, never the fix.

Next session plan (written 2026-11-25, end of the Wi-Fi/BT session):
- **Cheap, DT-mostly, mainline drivers or Cosmo code**: RTC (rtc-mt6397
  MT6359 cell), power off (Cosmo mt6358-poweroff pattern on MT6359P),
  slide hall sensor (gpio-keys SW_LID, as the Cosmo lid), volume keys
  (mt6779-keypad), keyboard backlight (gpio-leds GPIO28), microSD (mtk-sd,
  CD GPIO23), joydev; userspace: PipeWire (BT audio), polkit rule for
  nmcli/bluetoothctl, ping_group_range.
- **Not like the Cosmo — CPU DVFS**: Cosmo = mediatek-cpufreq on MT6358
  Vproc. Astro = MT8192 layout: Vproc1/2 and Vgpu on two MT6315 over SPMI
  (stock mt6315@6/@7), and mainline mt8192 uses cpufreq-hw, but the CSRAM
  LUT at 0x11bc10 is not initialised on this LK (read 2026-11-25: random
  values; stock kernel fills it and starts MCUPM). Needs SPMI + MT6315
  first, then a decision (port the stock CSRAM/MCUPM init, or kernel-side
  DVFS).
- **GPU**: Mali-G57 MC5 (Valhall) = MT8192 Chromebook GPU, mainline panfrost
  `mediatek,mt8192-mali` (Cosmo had G72/Bifrost, also panfrost). Needs
  SPMI + MT6315 (vgpu), MT6359 vsram_others, the MFG0-6 power domains
  (removed from the spm node for W2) and the stock gpufreq OPPs. Useful
  once display (DSI panel) is done.
- Shared prerequisite for CPU DVFS and GPU: SPMI (spmi-mtk-pmif) + MT6315
  regulators, a rule-5-style pre-flash check (CPU rails).
- **Decided (user, 2026-11-25): next session = real display first (route C),
  then GPU (route B), towards an accelerated DE.** Why: the panel is
  command mode (frames only on trigger), so simpledrm writes never reach
  it, and Mesa pairs panfrost with a KMS driver (mediatek-drm), not with
  simpledrm. First look (not started): mainline mtk_dsi has CMD_MODE and
  TE flag definitions but its enable path is video-mode shaped (vm_cmd,
  vdo timing, start once); mt8192 main path OVL0 → OVL_2L0 → RDMA0 →
  COLOR0 → CCORR → AAL0 → GAMMA → POSTMASK0 → DITHER0 → DSI0 (LK uses
  OVL0_2L → OVL0 → RDMA0 → DSI0). Start with a D0 research doc like
  wifi-stock.md: vendor panel-sh8802b-vdo.c (init, off, DCS 0x51),
  LK's registers (backup/disp-regs-lk.txt), mainline command-mode DSI
  gaps, the DISP power domain (removed from spm in W2), burn-in plan.
  **Display Stages 0–4 done (2026-11-25, `docs/display-stock.md`)**:
  mainline mediatek-drm drives the SH8802B in command mode (kernel #19 +
  modules, blacklisted at boot): takeover without init, console, DCS
  brightness, stock off, and a full stock screen-on (54-write table) with
  power mode 0x9C. Reference = stock Android behaviour (user decision).
  Next: Stage 5 (mediatek-drm by default, idle blanking/DPMS, hang-proof
  off path, CMA or IOMMU), then GPU (panfrost).

Next candidates:
00. ~~Burn-in bug~~ fixed in chg1 (astro-console ignores init's alive
   lines; user saw the 60 s blank, 2026-11-25).
0. ~~Step 2~~ **done** (pmicB, 2026-11-25): pwrap + MT6359P MFD core +
   `mtk-pmic-keys` (KEY_ESC) on mainline, two upstreamable deltas (pwrap
   mt6873 INT_FLG/INT_CLR + no WDT_SRC write; keys MT6359P reset layout in
   STRUP_CON12). 0xa12 stays 0x21e0; both escapes observed on A and B.
   Plan/audit: `docs/pmic-plan.md`. Next PMIC users: mt6359-auxadc +
   battery gauge (step 3), each through the narrowed rule-5 guard.
0b. **Step 3A + 3B done** (bat3a/bat3b, 2026-11-25; both escapes
   observed on each): battery percentage from mt6359-auxadc VBAT/IBAT +
   generic-adc-battery/adc-battery-helper + stock OCV tables, temperature
   from the stock NCP15XH103 NTC via ntc_thermistor (`docs/pmic-plan.md`
   "Step 3", "Step 3B"). Later: a coulomb-counter FG driver.
0a. **Debian 13 CLI on userdata: running** (root3 + gemini-debian
   `DEVICE=astro`, 2026-11-25): only sdc + sdc56 writable, systemd owns
   the watchdog, tripwire, console on the panel, SSH via Monolith
   (`ssh -J atzero@192.168.0.235 atzero@10.15.21.1`), NAT through
   Monolith's `astro-usb` profile. **Wi-Fi: working** (kernel #13,
   boot-w2.img, 2026-11-25): vendor WMT/BTIF/gen4m stack as modules, CONN
   genpd, five MT6359P rails; gemini-debian astro-wifi.service brings it up
   at boot (`docs/wifi-stock.md`). **Bluetooth: working** (hci_stp +
   astro-bt.service, unit BD address; session log 2026-11-25). Next: pairing/A2DP test, GPS. Rootfs to-dos: ping
   (ping_group_range), smaller image.
0c. **To-do: charge voltage 4.40 V** (user, 2026-11-25: queued, not
   urgent). LK sets CV 4.35 V every boot (`mt6360_set_cv: cv = 4350`);
   stock Android raises it to `battery_cv` 4.40 V in 10–45 °C. Mainline
   `mt6360_charger` never writes VOREG. Plan: upstreamable delta so it
   reads `monitored-battery` (constant-charge-voltage-max) → battery
   node 4400000 (also the helper's Full threshold). Charger write: needs
   a pre-flash check; verify rest voltage after a full charge. Session
   log "Why the charger stops at 4.35 V".
0d. **Deferred: battery temperature protection while charging** (user,
   2026-11-25: battery only gets slightly warm where it sits; circle back
   later). Stock JEITA: 4.24 V above 45 °C and 0–10 °C, 4.04 V below 0 °C.
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
5. **Never flash an image that can strand the device.** The reset escapes
   (power-key reset, watchdog reset) are established, below; they exist so
   a hung board can always be rebooted. **No escape re-tests per image**
   (user, 2026-11-25): their mechanisms are PMIC hardware (STRUP_CON12
   0xa12) and the TOPRGU watchdog, so a change is checked by reading 0xa12
   and by keeping the watchdog path unchanged, not by holding the key.
   Status (2026-11-25, `docs/session-log.md`):
   - **Watchdog: observed** with our kernel (try1c `astro.wdtest=1`, init
     never feeds it: board resets, next boot `lk boot reason = 4`).
   - **Power key ~10 s: observed** with our kernel running (normal image,
     init feeding the watchdog) and before the kernel (mtk DA mode).
   - **LK panic → watchdog reset: observed** (try1, try1b).
   - **Debian root (root3, 2026-11-25): observed** power-key reset with
     Debian running, watchdog reset after the handoff (systemd frozen by
     SIGSEGV → reset in 31 s), tripwire (TRY → rescue → Debian).
     `docs/rootfs-plan.md`.
   These hold only while nothing in Linux reaches the MT6359P: its
   power-key reset lives in `STRUP_CON12` (0xa12) and mainline
   `mtk-pmic-keys` writes 0x14c, a different register on this PMIC.
   `bin/build-boot-img.sh` refuses a DTB with pwrap/mt6359/keys enabled
   and a kernel with the pwrap or PMIC keys driver. Changes touching PMIC
   keys, watchdog, reset path, display/panel or a new kernel config need
   an explicit yes to a written pre-flash check. After such a flash: read
   0xa12 (expect 0x21e0).
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
