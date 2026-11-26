# CPU DVFS on the Astro: stock reference and plan

Started 2026-11-26. Why: the CPUs run at LK's clocks (A76 774 MHz, A55
1075 MHz), the main cause of KWin/Qt frame drops (desktop.md).

## What stock Android does

- `CONFIG_MTK_CPU_FREQ` + `CONFIG_MTK_TINYSYS_MCUPM_SUPPORT` →
  `CONFIG_HYBRID_CPU_DVFS` (vendor `base/power/cpufreq_v1`, mach mt6873).
  The kernel only writes the OPP table into CSRAM 0x0011bc10
  (`cpuhvfs_pvt_tbl_create`) and sends IPI `IPI_DVFS_INIT_PTBL` to the
  MCUPM over its tinysys mailbox (mcupm@0c540000, channel 1); after that the
  MCUPM firmware does PLL, divider and Vproc/Vsram changes, the kernel only
  posts OPP indexes into CSRAM. The MCUPM firmware is loaded by the
  bootloader (no reset/load path in the vendor kernel).
- The MCUPM CSRAM layout is MTK's Android one (16 rows of `Vproc<<16 |
  MHz`, then `clkdiv<<16 | postdiv`, clusters at word 0/36/72), not the
  Chromebook MCUPM interface that mainline `mediatek-cpufreq-hw` reads, so
  cpufreq-hw cannot drive it.
- The non-hybrid code in the same files (`mtk_cpufreq_platform.c`) shows the
  hardware steps, which are what mainline `mediatek-cpufreq` does:
  - ARMPLL_LL apmixed+0x208..0x214 (A55 cluster), ARMPLL_BL0 +0x218..0x224
    (A76 cluster; BL1-3 are off, 0x3F0), CCIPLL +0x258..0x264. CON1: pcw
    bits 21:0 (`MHz << 14 / 26`), post divider bits 26:24, CHG bit 31.
  - MCUSYS 0x0c53a2a0 / 2a4 / 2e0 (MP0/MP1/BUS_PLL_DIVIDER): mux bits 10:9
    (0 = 26 MHz, 1 = ARMPLL, 2 = MAINPLL, 3 = UNIVPLL), CKDIV1 bits 21:17
    (8 = /1). Same layout as mainline `clk-mt8186-mcu.c`.
  - Rails: `6_vbuck1` (MT6315@6 vbuck1) = proc1 = A76; `6_vbuck3` = proc2 =
    A55 + CCI; VSRAM_PROC1/2 (MT6359P) the SRAM rails. Vsram = Vproc +
    100 mV within 0.75-1.0 V, at most 250 mV apart; Vproc 0.6-1.0 V
    (`NORMAL_DIFF_VRSAM_VPROC`, `MAX_DIFF_VRSAM_VPROC`, `MIN/MAX_VSRAM_VOLT`).
  - Up 12.5 mV/us, down 5 mV/us (`UP_SRATE`/`DOWN_SRATE`).
- Chip level: `_mt_cpufreq_get_cpu_level` from devinfo 7 and 141. This
  unit (`/proc/device-tree/chosen/atag,devinfo`, 2026-11-26): devinfo[7]
  = 0x00060801 (low byte 0x01), devinfo[141] = 0x07000105 (ver 5, env bit
  0) → **CPU_LEVEL_0 = FY table**. DT DOE override off (`change_flag = 0`).
- Shipped kernel binary (backup/boot_a.kernel, gunzipped) contains the FY,
  TB and 6873T tables at 0x1a267a0.. byte for byte as the source.
- EEM (`CONFIG_MTK_PTPOD`, eem_v2 via MCUPM EEMSN) lowers voltages per chip
  at runtime; not reproduced. The FY table values are the unadjusted ones
  (EEM only lowers), so using them is on the safe side.

### FY table (MHz / Vproc V / post divider; clkdiv always /1)

| A55 (ARMPLL_LL) | A76 (ARMPLL_BL0) | CCI (CCIPLL) |
|---|---|---|
| 2000 0.925 /1 | 2000 0.925 /1 | 1340 0.925 /2 |
| 1875 0.8875 /1 | 1950 0.90625 /1 | 1308 0.8875 /2 |
| 1812 0.86875 /1 | 1900 0.8875 /1 | 1265 0.8375 /2 |
| 1750 0.85625 /1 | 1850 0.86875 /1 | 1258 0.800 /2 |
| 1687 0.8375 /1 | 1800 0.850 /1 | 1190 0.750 /2 |
| 1625 0.81875 /1 | 1716 0.83125 /1 | 1103 0.73125 /2 |
| 1541 0.800 /2 | 1633 0.80625 /1 | 1017 0.7125 /2 |
| 1500 0.78125 /2 | 1548 0.800 /2 | 960 0.700 /2 |
| 1358 0.750 /2 | 1383 0.750 /2 | 902 0.6875 /2 |
| 1181 0.7125 /2 | 1258 0.71875 /2 | 873 0.68125 /2 |
| 1075 0.69375 /2 | 1175 0.700 /2 | 816 0.66875 /2 |
| 968 0.66875 /2 | 1091 0.675 /2 | 730 0.650 /4 |
| 862 0.64375 /2 | 1008 0.65625 /2 | 672 0.6375 /4 |
| 756 0.625 /2 | 925 0.6375 /2 | 615 0.625 /4 |
| 650 0.600 /4 | 841 0.61875 /2 | 557 0.6125 /4 |
| 500 0.600 /4 | 774 0.600 /2 | 500 0.600 /4 |

Vproc = table step x 6.25 mV. CCI pairing: stock `CCI_6873Tbl` (16 x 16
map from the two cluster indexes), for C2.

## Live state under our kernel #23 (read only, 2026-11-26)

- ARMPLL_LL CON1 0x8114AC4E = 2150 MHz /2 = **1075 MHz**; ARMPLL_BL0
  0x010EE276 = 1548 /2 = **774 MHz**; CCIPLL 0x821C13B1 = 2920 /4 = **730
  MHz**. CON0 0x3F1 (on), CON3 0x80000001 (power on, iso off) for all three.
- MCUSYS 0x0c53a2a0/2a4 = 0x00110AFF, 2e0 = 0x80100AFF: mux 1 (ARMPLL),
  CKDIV1 8 (/1).
- FHCTL (0x1000ce00..) all 0: no hopping on any PLL, direct pcw writes work.
- MAINPLL 0x80150000 = 2184 MHz: too fast as a parking parent; 26 MHz is
  used instead (as the Cosmo's CCI in C2).
- Rails: MT6315@6 vbuck1 (A76) 0.600 V, vbuck3 (A55/CCI) 0.71875 V,
  VSRAM_PROC1 0.750 V, VSRAM_PROC2 0.81875 V (= Vproc + 100 mV): LK's state
  matches the stock rule. CSRAM holds random data (MCUPM never initialised).

## Route: kernel-side DVFS, as the Cosmo

Mainline `mediatek-cpufreq` with the stock table, like the Cosmo (whose
stock also ran DVFS in a co-processor). Deltas (all upstreamable):
- `include/dt-bindings/clock/mt8192-clk.h`: CLK_APMIXED_ARMPLL_LL/BL/CCIPLL
  and MCUSYS mux IDs.
- `clk-mt8192-apmixedsys.c`: `mediatek,mt6873-apmixedsys` = MT8192 PLLs +
  the three CPU PLLs (PLL_AO; post dividers per the stock tables through a
  div_table). Registration writes nothing new: the critical-clock prepare
  rewrites CON3/CON0 with the bits already set.
- `clk-mt8186-mcu.c`: `mediatek,mt6873-mcusys` (same mux registers).
- `mediatek-cpufreq.c`: `mediatek,mt6873` platform data (stock Vsram rule,
  CCI supported); `cpufreq-dt-platdev.c`: blocklist `mediatek,mt6873`.
- Config: `ARM_MEDIATEK_CPUFREQ=m`.

Stages (as the Cosmo C1-C4):
- **C1** frequency only, rails pinned at LK's voltages. A55 500-1181 MHz,
  A76 774 MHz only (0.600 V allows nothing else), no sram supply, CCI node
  without a driver (mediatek-cpufreq keeps Vproc >= boot value).
- **C2** sram supplies (VSRAM_PROC1/2, MT6359P) + Vproc constraints opened
  upward in steps; A76 range opened. First CPU-rail voltage changes.
- **C3** CCI devfreq (mtk-cci-devfreq + stock CCI table/pairing).
- **C4** full tables to 2.0 GHz, thermal throttling checked (mt8192.dtsi
  cpu zones already map both clusters).

## C1 pre-flash check (boot-c1.img, kernel #24)

- Image: `out/boot-c1.img` `a66d505e98fa…c1d`, Image.gz `6138a975…`, DTB
  `4e53320e…`. Same cmdline as boot-tp2.
- Risk flags: **new kernel config** (ARM_MEDIATEK_CPUFREQ=m) and **first
  regulator constraints on the CPU rails** (MT6315@6 vbuck1/vbuck3). No
  PMIC keys, watchdog, reset path or display change.
- PMIC write: at registration the regulator core applies each pin once,
  same value as LK's (0.600 V, 0.71875 V). If LK ever left another value,
  the pin would move the rail to it (both are valid stock voltages for the
  LK clocks: 774 MHz needs 0.600 V, 1075 MHz 0.69375 V).
  `build-boot-img.sh` accepts exactly these constraints on pmic@6 and
  nothing on pmic@3.
- Clock writes: none at boot (mediatek-cpufreq is a module, blacklisted,
  loaded by hand). After `modprobe`: ARMPLL_LL pcw/postdiv and the MP0 mux
  only. New frequency/voltage pair: A55 1181 MHz at 0.71875 V (stock
  0.7125 V). A76 and CCI unchanged (774 / 730 MHz).
- Escapes: power-key reset and watchdog observed, unchanged paths. A CPU
  fault ends in the watchdog reset. After the flash: read 0xa12 (expect
  0x21e0).
- Test (`tools/cpufreq-tests/c-test.sh`, register readback): boot → 0xa12,
  rails 600000/718750, clk tree has armpll_ll/bl/ccipll at 1075/774/730
  MHz; `modprobe mediatek-cpufreq` → policy0 (7 OPPs) and policy4 (774);
  `steps` PASS each OPP (cpuinfo = OPP, PLL readback within 0.1 %, rails
  unchanged, CCI stays 730 MHz); `stress 120` at max and `stress 60 min`:
  no md5 mismatch, no hang. Fail: any hang/reset, any FAIL line.
- Rollback: `mtk w boot_a boot-tp2.img` (kernel #23; the #23 module tree is
  kept as `/lib/modules/6.18.58-astro.k23`).

### C1 result: PASS (2026-11-26, boot-c1.img `a66d505e…`, kernel #24)

- Boot: #24, 0xa12 0x21e0, Vproc_big 600000 / Vproc_little 718750 (pins),
  VSRAM 750000 / 818750 unchanged. Clock tree: armpll_ll 1074999390,
  armpll_bl 773999878, ccipll 729999909 Hz = register decode.
- `modprobe mediatek-cpufreq`: policy0 (CPU0-3, 500-1181 MHz) and policy4
  (CPU4-7, 774 MHz) on schedutil; "unlisted initial frequency" 1074999 /
  773999 -> 1075000 / 774000 kHz. No errors.
- steps: 8/8 PASS (cpuinfo = OPP, PLL readback within 1 kHz, rails
  pinned, CCI 730 MHz unchanged). ARMPLL_LL CON1: 500/650 MHz post divider
  /4 (0x82…), 756/1181 MHz /2 (0x81…) = the stock FY dividers.
- stress 120 at max (A55 1181 MHz): 0 md5 mismatches, runs 726-732 (A55)
  / 859-867 (A76), 33.2 -> 35.4 °C. stress 60 at min (A55 500 MHz): 0
  mismatches, runs 158-160 / 428-431. Rails unchanged throughout.
- Side note: one `mt-pmic-pwrap: unexpected interrupt int=0x20` at 82 s,
  before cpufreq loaded; it coincided with reading 0xa12 through the
  whole-map regmap debugfs dump. Read single registers next time.
