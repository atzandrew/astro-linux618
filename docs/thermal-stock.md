# SoC thermal (LVTS) on the Astro: stock reference and plan, 2026-11-25

Why: G-S3 (GPU DVFS up to the stock 748 MHz) needs GPU throttling, and
our kernel had no SoC temperature at all (only the battery ADC zone).
User decision (2026-11-25): thermal stage first, then G-S3.

Sources: vendor 4.14 tree (`astro-kernel`:
`drivers/misc/mediatek/thermal/mt6873/src/mtk_lvts_tc.c`,
`.../common/thermal_zones/mtk_ts_cpu_noBank.c`, `.../mt6873/inc/`), the
stock DT (`backup/boot_a.dtb.0.dts`), the stock log (`backup/expdb.txt`),
mainline v6.18.58 (`drivers/thermal/mediatek/lvts_thermal.c`,
`mt8192.dtsi`). Same rules as the display and GPU work: stock sequences,
every write stage behind a written check.

## Hardware (stock = mainline MT8192 layout)

| Item | Stock MT6873 | Mainline MT8192 |
|---|---|---|
| Block | `therm_ctrl@1100b000` (one node, size 0x26e200) | `lvts_ap@1100b000`, `lvts_mcu@11278000` (= stock base + 0x26d000) |
| Controllers | MCU: +0x26d000/+0x100/+0x200 with 2/2/4 sensors; AP: +0/+0x100/+0x200/+0x300 with 2/2/2/3 | same |
| Sensors | 17; CPU big = TC0/TC1, little = TC2, GPU = TC4 (AP +0x100) | same (`MT8192_*` ids) |
| Calibration | efuse 0x11C101C0…0x214 (devinfo 116–119, 190–207): golden = word0[31:24], count_r[i] = word(i+1)[23:0] | nvmem cell `lvts_e_data1` = efuse 0x1c0, 0x58 bytes; golden = word0 >> 24; sensor i = bytes 0x04+4i…+2 |
| Formula | T = −250.46 × MSR/16384 + golden/2 + 250.46 (`lvts_raw_to_temp`) | same (`LVTS_COEFF_A/B_MT8195`) |
| RC mode | `LVTS_DEVICE_AUTO_RCK 1`: EDATA = count_r | EDATA = calibration (same) |
| Clock / reset | infra_therm (CG0 bit 10); INFRA RST0 bit 0 (AP), RST4 bit 12 (MCU) | same |

## Reads (2026-11-25, kernel #21, read-only)

- infra CG0 status `0x10001090 = 0x83AF9A00`: bit 10 clear, clock on.
- All seven controllers at reset defaults (MONCTL0/1/2 0, TSSEL
  `0x03020100`, ID `0x98`, EDATA 0, MSR 0, PROTCTL/PROTTA–C 0, CLKEN 0):
  **LK does not start LVTS**; T-S1 is a first init, not a takeover.
- efuse 0x1c0…: `0x3C000000 0x00008A60 0x0B008A8D 0x2D008995 …
  0x5D000B2A`, the same words the stock kernel logged (expdb 13445–13451:
  golden 60, counts 35424, 35469, …). The chip is calibrated
  (golden 60 < mainline's 62 limit, so mainline uses it).

## Stock init sequence (`tscpu_thermal_initial` → LVTS part)

Per controller:
1. infra reset pulse (AP RST0 bit 0, MCU RST4 bit 12) — `lvts_tscpu_reset_thermal`.
2. `CLKEN = 1`; device commands via `LVTS_CONFIG` (3 µs apart):
   `8103FFFF` (reset devices), `8502FC55` (read ID; expect `0x81 + tc`).
3. Device init: `81030300 810307A6 81030500 81030420 81030A84 81030C7C
   8103098D 810308F4 810308FC 810308F4`, then auto-RCK `81030E01`.
4. `EDATA0x = count_r` per sensor.
5. `MONCTL0 = 0` (sensing off), then `TSSEL = 0x13121110`,
   `CALSCALE = 0x300`, device `810306B8` (single mode),
   `MONCTL1 = 0x00C00001`, `MONCTL2 = 0x00010001`, `MSRCTL0 = 0x492`
   (4 samples, drop min/max).
6. `MONCTL0 = 0x200 | sensor bits` (periodic, all sensors).
7. HW protection (`lvts_config_all_tc_hw_protect`): stage-3 threshold
   117 °C → TOPRGU thermal reset (`wd_thermal_direct_mode_config`).
   Throttle trips (`tzcpu_initcfg.h`): 95 / 85 / 65 °C; plus SSPM throttling
   (efuse sent by IPI).

## Mainline vs stock

Same: blocks, controllers, sensor map, efuse parsing, formula, reset
bits, clock, order (reset → CLKEN → connect → init → EDATA → configure →
start), ID check (bit 7), `TSSEL`, MONCTL0 layout in filtered mode.

Different (mainline mt8192 data):
- device commands use mask `0xC1…`/`0xC5…` and other analog values
  (`0C=FC 0A=8C 08=F1`, plus `0E`, `06`, and a reg-0 sequence);
- `CALSCALE` computed but never written; `MSRCTL0 = 0` (1 sample),
  `MONCTL1 = 0`, `MONCTL2 = 0`;
- AP controllers in immediate mode (MSRCTL1) instead of periodic;
- no HW protection (PROTTx stay 0, no RGU): the critical trip does an
  orderly software shutdown.

## The delta (`kernel/delta/drivers/thermal/mediatek/lvts_thermal.c`)

New `mediatek,mt6873-lvts-ap` / `-mcu` data: the MT8192 controller tables
with every controller in filtered (periodic) mode, the stock commands
(conn `8103FFFF 8502FC55`; init the ten stock writes + `81030E01`; cfg
`810306B8`), and an optional `cfg_cmd` branch in `lvts_ctrl_configure`
that writes TSSEL, CALSCALE 0x300, the cfg commands, MONCTL1 0x00C00001,
MONCTL2 0x00010001, MSRCTL0 0x492 in the stock order. Command spacing
stays mainline's 2–4 µs (hardware needs 1 µs, stock waits 3).

Not taken from stock (deliberately):
- **HW thermal reset (117 °C via TOPRGU)**: needs a TOPRGU write mainline
  `mtk_wdt` has no API for. Later stage if wanted; until then the
  critical trips shut down in software.
- Stock interrupts/thresholds for SSPM: mainline programs its own trip
  thresholds and interrupts (to the CPU only).

## Trips

mt8192.dtsi zones, one per sensor (17): passive 85 °C (stock's 85 °C
trip), critical 100 °C (below stock's 117 °C HW reset). CPU cooling-maps
bind once cpufreq exists; `gpu-thermal` binds the GPU devfreq in G-S3.

## T-S1 pre-flash check (2026-11-25) — approved ("go")

1. **Image**: `boot-t1.img` sha256
   `fac89f85531ba3f7a52261aa241d06e22651456fc882eae363f2943e23d5793f`
   (Monolith `~/Build/astro-backup/`), kernel **#22** (`Image.gz`
   `b053088b…`, DTB `31d5c4d4…`). Writes `boot_a`. Module tree staged at
   `~/mod-k22` on the Astro (not installed; installed with #21's kept as
   `.k21` and synced right before the flash). `lvts_thermal.ko`
   `31ff4b29…`, blacklisted (`/etc/modprobe.d/astro-thermal.conf`,
   synced); `mediatek-drm.ko` `66274443…` (the version running now).
2. **Changes vs #21**:
   - DT: `efuse@11c10000` okay (read-only driver; no write op exists);
     `lvts_ap`/`lvts_mcu` okay with `mediatek,mt6873-lvts-*`; SVS stays
     disabled. 17 mt8192.dtsi zones (passive 85 °C, critical 100 °C).
   - `lvts_thermal.c` delta (`daaba4d1…`, pinned): the MT6873 stock
     sequence (section above).
   - Config: `NVMEM_MTK_EFUSE=y`, `MTK_THERMAL=y`, `MTK_LVTS_THERMAL=m`
     (+ debugfs), `MTK_SOC_THERMAL=n`, `MTK_SVS=n`. Guard: LVTS module
     only, pinned sha, mt6873 compatibles, SVS node/config off (three
     negative tests refused).
   - Committed display fixes (vblank source, OVL FME_CPL), same as the
     module running now.
3. **At boot**: efuse probes and only reads. LVTS is blacklisted: **no
   thermal write at boot.** Everything else as #21.
4. **The test** (agent):
   1. read 0xa12; compare the efuse cell (`/sys/bus/nvmem`) with the
      words read by devmem;
   2. `modprobe lvts_thermal` — writes, per controller: infra reset pulse
      (AP RST0 bit 0, MCU RST4 bit 12), `CLKEN=1`, stock device commands,
      EDATA (efuse counts), TSSEL, CALSCALE 0x300, `810306B8`, MONCTL1/2,
      MSRCTL0 0x492, MONINT 0, MONCTL0 (start); then the thermal core
      programs mainline's trip thresholds/interrupts (CPU interrupts only);
   3. reads: probe log (golden 60, not "fake"), 17 zones, temperatures at
      idle (sane = close together, a little above the battery's ~23 °C),
      controller registers vs the stock values (debugfs);
   4. kmscube 30 s with panfrost: GPU sensors should rise a few degrees
      and fall back.
5. **R-rules**: no PMIC, rail, clock-rate or display change; efuse read
   only; no TOPRGU write (no HW thermal reset). Failure modes: bogus
   readings ≥ 100 °C → orderly power-off (harmless, then
   `rmmod`/blacklist stays); bogus low readings → no worse than today.
6. **Escapes**: 0xa12 unaffected (no MT6359P write); a bus hang from an
   LVTS access → watchdog reset in ~31 s.

## T-S1 result (2026-11-25) — passed

- `boot-t1.img` `fac89f85…` flashed (kernel #22); 0xa12 = 0x21e0; the
  efuse nvmem cell equals the devmem words (and the stock log).
- `modprobe lvts_thermal`: golden temp 60 on both domains (not fake), 17
  LVTS zones. Registers after start, all seven controllers: MONCTL0
  `0x203`/`0x207`/`0x20F` (2/3/4 sensors), MONCTL1 `0x00C00001`, MONCTL2
  `0x00010001`, MSRCTL0 `0x492`, TSSEL `0x13121110`, CALSCALE `0x300`,
  EDATA = efuse counts, CLKEN 1, ID `0x81`–`0x87` = the vendor's expected
  `0x81 + tc`. Stock values throughout.
- **Read fix**: mainline polls the MSR valid bit for 400 µs; in this
  (stock, periodic) mode the bit is set only part of each round, so 12–55 %
  of reads failed (md0/md2 showed "No data"). The MT6873 data now reads as
  the vendor `lvts_read_tc_raw_and_temp`: last filtered value, raw 0 =
  not ready (`msr_holds_last`). Read path only, no register write changed;
  module swapped by hand (`lvts_thermal.c` `de9e97ac…`, `.ko`
  `c5cafd04…`): 0 failures in 320 reads.
- Idle: all 17 sensors 28.6–30.6 °C (battery 22.1 °C). 30 s all-core
  `yes` (LK clocks): CPU sensors +3.5 °C in 5 s (33.5 °C peak), GPU/MD
  +1 °C, back within ~10 s. kmscube at 358 MHz: no measurable change
  (light load).

## Staged plan

- **T-S1 — LVTS + efuse (flash). Done 2026-11-25.** efuse driver (read-only) built in;
  LVTS as a module, blacklisted, loaded by hand. Check: probe log (golden
  60, no "fake"), 17 zones registered, plausible temperatures (all
  sensors close together, above the battery's, rising under load),
  registers match the stock values. Pre-flash check below.
- Then G-S3 (`docs/gpu-stock.md`), with `gpu-thermal` throttling.
- Optional later: HW thermal reset via TOPRGU (stock 117 °C).
