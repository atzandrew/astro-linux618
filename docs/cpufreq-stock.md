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

## C2 pre-flash check (boot-c2.img, DTB only on kernel #24)

- Image: `out/boot-c2.img` `cb497ad7…6df4`, DTB `0d8a02c5…9b98`, Image.gz
  unchanged (`6138a975…`, kernel #24, modules as installed).
- Change, DTS only:
  - MT6315@6 vbuck1/vbuck3: 0.600-0.800 V (was pinned), software ramp
    5 mV/us, always on.
  - MT6359P ldo_vsram_proc1/2: new nodes, 0.750-0.900 V, ramp 5 mV/us,
    always on; `sram-supply` on CPU0-3 (vsram_proc2) and CPU4-7
    (vsram_proc1). mediatek-cpufreq tracks Vsram = Vproc + 100 mV (floor
    0.75 V, at most 250 mV apart) = the stock rule.
  - OPPs: every FY point up to 0.800 V. A55 500-1541 MHz (adds 1358 /
    1500 / 1541), A76 774-1548 MHz (adds 841-1548).
- Risk flags: **first CPU-rail voltage changes** (up to 0.800 V on Vproc,
  0.900 V on Vsram), new MT6359P regulator constraints (two LDOs). No PMIC
  keys, watchdog, reset path, display or config change.
- PMIC writes at boot: none (LK's 0.600 / 0.71875 / 0.750 / 0.81875 V are
  inside every range, both SRAM LDOs already on). Writes start only after
  `modprobe mediatek-cpufreq`, through the regulator API: Vproc via SPMI
  (MT6315@6 vbuck1/3), Vsram via pwrap at VOSEL 0x1b44 / 0x1b46 (MT6359P,
  far from STRUP_CON12 0xa12).
- Highest new pairs: A76 1548 MHz at 0.800 V / Vsram 0.900 V, A55 1541 MHz
  at 0.800 V / 0.900 V (stock values, unadjusted by EEM). The A55/CCI rail
  never drops below LK's 0.71875 V (no CCI driver yet), which also covers
  the CCI at 730 MHz (0.650 V).
- Guard: `build-boot-img.sh` accepts exactly these constraints on pmic@6
  and the two vsram nodes; checked with a 0.825 V variant (refused).
- Escapes: power-key reset and watchdog observed, paths unchanged; a CPU
  fault at a too-low voltage ends in the watchdog reset. After the flash:
  0xa12 (single-register read).
- Test (`c-test.sh`, C2 version): boot → rails at LK's values, no
  regulator errors; `modprobe` → policy0 10 OPPs, policy4 9 OPPs; `steps`
  (other cluster at its minimum): PLL readback, Vproc = max(table, boot),
  Vsram = Vproc + 100 mV at every OPP; `stress 120` at max with
  temperatures; `stress 60 min`. Fail: any hang/reset, any FAIL line.
- Rollback: `mtk w boot_a boot-c1.img` (same kernel and modules).

### C2 result: PASS (2026-11-26, boot-c2.img `cb497ad7…`, kernel #24)

- Boot: 0xa12 0x21e0 (single-register read: `dd bs=11 skip=1289 count=1`
  on the pwrap regmap debugfs; no pwrap interrupt message this time), rails
  at LK's 0.600 / 0.71875 / 0.750 / 0.81875 V, no regulator errors.
- `modprobe`: policy0 10 OPPs (500-1541 MHz), policy4 9 OPPs (774-1548).
- steps: 19/19 PASS. Vproc = max(stock table, boot value) and Vsram =
  Vproc + 100 mV at every OPP (e.g. A76 1548 MHz: 0.800 / 0.900 V; A55
  1541 MHz: 0.800 / 0.900 V; A55 below 1181 MHz stays at the 0.71875 V
  boot floor).
- Shell sampling right after switching back to schedutil showed A76 PLL
  1008 MHz next to 0.600 V: the sampler's own process spawning loaded the
  A76 cores (reads milliseconds apart). Checked with `vfcheck` (static C
  sampler, /dev/mem + sysfs, Vproc / PLL / Vproc within microseconds),
  pinned to the other cluster, schedutil with bursty load (`vfrun.sh`):
  40000 samples per cluster, **0 samples under the stock voltage**, every
  OPP visited (A76 774-1548, A55 500-1541 MHz), mux always ARMPLL /1.
- stress 120 at max (1541 / 1548 MHz, 0.800 V, Vsram 0.900 V): 0 md5
  mismatches, runs 914-928 (A55) / 1638-1674 (A76) vs C1's 726-732 /
  859-867; peak 50.7 °C. stress 60 at min: 0 mismatches.
- No kernel ftrace in #24 (CONFIG_FTRACE off); worth enabling at the next
  kernel build for the CCI stage.

## C3 pre-flash check (boot-c3.img, kernel #25)

- Image: `out/boot-c3.img` `59831c2e…7cf550`, Image.gz `afcb9b45…`, DTB
  `fe7e18ab…`. Kernel #25 = #24 + `CONFIG_ARM_MEDIATEK_CCI_DEVFREQ=m`
  (module; selects the passive governor, already a module).
- Delta: `drivers/devfreq/mtk-cci-devfreq.c`: `mediatek,mt6873-cci` with
  the same Vproc/Vsram rule as mediatek-cpufreq's mt6873 data.
- DTS: cci node gets proc-supply vbuck3 (shared with the A55 cluster),
  sram-supply vsram_proc2, and the stock CCI OPPs the normal map can
  select: 500-1017 MHz at 0.600-0.7125 V. Every CPU OPP gets
  `required-opps` from the stock `CCI_6873Tbl` normal map. That map is
  exactly `min(a[A55 index], b[A76 index])` for all 256 entries, with
  a = 6 7 8 9 10 10 11 11 12 13 14 15 15 15 15 15 and
  b = 6 7 7 8 8 9 10 10 12 13 13 14 15 15 15 15, so the passive governor's
  maximum reproduces the map. Rows are read as A55 (the vendor code does
  not name them); a swap would only pick a neighbouring CCI point, never a
  lower voltage than the chosen CCI point needs. C3 pairings: A55 1541/1500
  → 730, 1358 → 672, 1181 → 615, 1075 → 557, below → 500; A76 1548 → 816,
  1383 → 672, 1258/1175 → 615, 1091 → 557, below → 500 MHz.
- Rail and range constraints unchanged from C2 (guard unchanged).
- Risk flags: **new kernel config** (one module) and **new kernel**. First
  CCI rate changes (stock range; highest 816 MHz at 0.66875 V). The A55/CCI
  rail may now go down to 0.600 V (the stock floor; C2 held it at
  0.71875 V); each consumer keeps its own vote, the core runs the higher.
  CCIPLL post dividers per stock (/2 at 816 and above, /4 at 730 and below).
  The CCI parks on 26 MHz while CCIPLL relocks (as the Cosmo's C2).
- Boot: no change (both modules blacklisted, loaded by hand). At
  `modprobe mtk-cci-devfreq` the driver first raises the shared rail to the
  CCI's top OPP voltage (0.7125 V, inside the constraint).
- Escapes: power-key reset and watchdog observed, paths unchanged. After
  the flash: 0xa12 (single-register read).
- Test: `modprobe mediatek-cpufreq mtk-cci-devfreq`; devfreq `cci` on the
  passive governor; `steps` (other cluster at its minimum): PLL readback,
  CCI hw = devfreq = paired OPP, Vproc_little = max(A55, CCI) table value,
  Vproc_big = table, Vsram = Vproc + 100 mV; `vfrun.sh big|little`
  (vfcheck now also checks CCIPLL against the A55 rail): 0 LOW; stress max
  and min: 0 md5 mismatches. Fail: any hang/reset, any FAIL/LOW line.
- Rollback: `mtk w boot_a boot-c2.img` plus the #24 module tree (kept as
  `/lib/modules/6.18.58-astro.k24`; swap back before rebooting into C2).

### C3 result: PASS (2026-11-26, boot-c3.img `59831c2e…`, kernel #25)

- Boot: #25, 0xa12 0x21e0, rails at LK's values. `modprobe
  mediatek-cpufreq mtk-cci-devfreq`: devfreq `cci` on passive, 500-1017
  MHz listed; CCI left LK's 730 MHz at once (557 MHz at idle).
- steps: 19/19 PASS: CCI hw = devfreq = stock-map OPP at every step
  (A55 sweep 500 → 730 MHz, A76 sweep 500 → 816 MHz); Vproc_little = max(A55,
  CCI) table value, now down to 0.600 V; during the A76 sweep the A55 rail
  follows the CCI's own vote (0.66875 V at CCI 816 MHz).
- vfcheck (CCIPLL against the A55 rail added), schedutil + bursty load:
  2 x 40000 samples, 0 under the stock voltage; CCI 500-816 MHz visited.
- stress 120 max: 0 md5 mismatches, runs 948-951 (A55, C2 914-928: CCI
  816 vs 730 MHz) / 1676-1700 (A76); peak 50.4 °C. stress 60 min (both
  rails 0.600 V, CCI 500 MHz, Vsram 0.750 V): 0 mismatches.

## C4 pre-flash check (boot-c4.img, DTB only on kernel #25)

- Image: `out/boot-c4.img` `98ad67eb…0751`, Image.gz `afcb9b45…`
  (kernel #25, modules as installed for C3).
- Change, DTS only: the full FY tables, A55 500-2000 MHz and A76
  774-2000 MHz (16 OPPs each, each with its stock-map CCI requirement; CCI
  can now reach 1017 MHz). Constraints: Vproc_big/Vproc_little 0.600-0.925
  V (stock FY floor/top), vsram_proc1/2 0.750-1.000 V (stock
  MIN/MAX_VSRAM_VOLT). Guard narrowed to exactly these.
- Risk flags: **first CPU-rail voltages above 0.800 V** (Vproc up to
  0.925 V, Vsram up to 1.000 V; at the top Vsram - Vproc = 75 mV, as stock,
  which clamps at 1.0 V too). Stock unadjusted FY values (EEM only lowers).
  No PMIC keys, watchdog, reset path, display or config change.
- PMIC writes at boot: none (LK's values inside every range); writes only
  after `modprobe`, as in C2/C3.
- Thermal: mt8192.dtsi cpu zones, passive 85 °C on both clusters (step-wise,
  250 ms), critical 100 °C (orderly power-off). Expected: throttling under
  a sustained all-core load at 2.0 GHz; a critical trip is a fail.
- Escapes: power-key reset and watchdog observed, paths unchanged. After
  the flash: 0xa12 (single-register read).
- Test: `steps` (32 OPPs: PLL readback, CCI pairing, Vproc/Vsram per
  table), `vfrun.sh big|little` (0 LOW), `stress 300` at max with
  temperatures (throttling expected; md5 mismatches fail), `stress 60 min`.
  Then the user-visible check: Plasma/KWin smoothness with schedutil.

### C4 result: PASS (2026-11-26, boot-c4.img `98ad67eb…`, kernel #25, flashed from livingwall)

- Boot: 0xa12 0x21e0, rails at LK's values inside the C4 ranges, no
  regulator errors. policy0 500-2000 MHz and policy4 774-2000 MHz (16
  OPPs each), CCI 500-1017 MHz.
- steps: 32/32 PASS. Tops: A55 2000 MHz at 0.925 V / Vsram 1.000 V with
  CCI 1017 MHz; A76 2000 MHz at 0.925 / 1.000 V with CCI 1017 MHz (A55 rail
  0.7125 V = the CCI's vote). Post dividers switch where stock's do: A55
  1541 /2 -> 1625 /1, A76 1548 /2 -> 1633 /1, CCIPLL /2 at 1017 MHz.
- vfcheck under schedutil: 2 x 40000 samples, 0 under the stock voltage;
  every A55/A76 OPP up to 2000 MHz and every CCI OPP visited.
- stress 300 at max (all 8 cores, 2000/2000 MHz, CCI 1017 MHz): 0 md5
  mismatches; runs 3026-3061 (A55) / 5414-5432 (A76), per second +29 % on
  both over C3 (= 2000/1541, 2000/1548); temperature 62 -> 78.9 °C, rising
  ~0.4 °C per 10 s at the end, below the 85 °C passive trip (no throttling
  within 300 s). stress 60 at min: 0 mismatches.
- Against LK's clocks (C1 stress, same md5 workload per second): A55 x2.6
  (1075 -> ~2000 MHz effective), A76 x2.6 (774 -> 2000 MHz).
