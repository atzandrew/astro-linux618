# GPU (Mali-G57, panfrost) on the Astro: stock reference (G0) and plan, 2026-11-25

Research only, no image, no register write. Sources: stock DTB
(`backup/boot_a.dtb.0.dts`), vendor 4.14 tree (`astro-kernel`:
`drivers/misc/mediatek/base/power/gpufreq_v1/mt6873/`,
`include/gpufreq_v1/mt6873/mtk_gpufreq_internal_plat.h`), the stock kernel
log (`backup/expdb.txt`), mainline v6.18.58 (`build/src`). Same method and
rules as the display (`docs/display-stock.md`): reference = stock Android,
no rail outside stock values, every write stage behind a written check.
User decision (2026-11-25): GPU before a desktop (panfrost needs the KMS
driver we now have; software rendering would be throw-away work).

## Hardware

| Item | Stock | Receipt |
|---|---|---|
| GPU | Mali-G57 (Valhall), `mali@13000000`, IRQs GPU/MMU/JOB/EVENT/PWR = SPI 363–367 | stock DTB `mali@13000000` |
| Segment | **MT6873 (5G-A)**: efuse spare[7:0] = `0x1` → `segment_id 1` | expdb 15407 `efuse_id: 0x1, segment_id: 1` |
| Shader cores | **4** (`shader_present 0x50005` = cores 0, 2, 16, 18; MT6875 variants get 5) | expdb 15416; vendor `mt_gpufreq_get_shader_present` |
| Segment table | efuse(69)[5:4] = `0x0`; source says table 1, the shipped kernel logs `segment_table: 14` (binary differs from source; open) | expdb 15406 |
| vgpu | **MT6315 @ SPMI slave 7, vbuck1** (`7_vbuck1`), range 0.3–1.19375 V | stock DTB `gpufreq _vgpu-supply = 7_vbuck1`; `VGPU_MAX/MIN_VOLT` |
| vsram_gpu | **MT6359P `vsram_others`** LDO, range 0.5–1.29375 V | `_vsram_gpu-supply = ldo_vsram_others` |
| vsram rule | vgpu ≤ 0.75 V → vsram 0.75 V, else vsram = vgpu; −100 ≤ vsram − vgpu ≤ +300 mV | header :43-69 |
| Clocks | mfg mux, main/sub parents, `subsys_bg3d`, MTCMOS MFG0–6 | stock DTB `gpufreq` clocks |
| Other MT6315 | **slave 6: vbuck1, vbuck3 = CPU rails** (proc1/proc2); slave 3: vbuck1/3/4 (to identify) | stock DTB `mt6315@6`, `@3`, `@7` |

## Stock OPP table (segment 1, table 1; `g_opp_table_segment_1`)

39 points, 950 MHz / 0.8 V (`0` sign-off) down to 358 MHz / 0.5625 V
(`38` sign-off), post-divider /4 (/8 at 358 MHz), aging margin 18.75 /
12.5 / 6.25 mV. vsram = 0.8 V at the top points, 0.75 V from 855 MHz down.
Table 2 (`_segment_2`) has the same frequencies with higher voltages below
688 MHz. The vendor also applies per-chip PTPOD/SVS lowering and the aging
margin at runtime; using the table voltages without them is at or above
stock, never above the table.

Mainline `mt8192.dtsi` `gpu_opp_table` is a different (Chromebook) bin:
358 MHz at 606.25 mV … 800 MHz top. Not used as is.

## Mainline status

| Block | Mainline | Note |
|---|---|---|
| SPMI | `spmi-mtk-pmif`, compatible **`mediatek,mt6873-spmi`** (mt8192 uses it) | node exists in mt8192.dtsi (disabled in our DTS) |
| MT6315 | `mt6315-regulator` (vbuck1–4, modes) | binds **all** MT6315s incl. the CPU rails: needs a "no write at probe" audit (constraints, modes) like pmic-plan |
| vgpu/vsram coupling | `mtk-regulator-coupler` (vsram = vgpu + spread, within vsram's range) | Asurada: vsram_others 750–800 mV, spread 10 mV → vgpu + 10 mV (stock: max(0.75, vgpu)) |
| Power domains | MFG0 (+MFG1–6) in mt8192 tables; MFG0 domain-supply vgpu, MFG1 vsram | deleted from our spm node in W2; KEEP_DEFAULT_OFF status per domain to check |
| GPU | panfrost `mediatek,mt8192-mali` (5 PM domains, 1 supply, Valhall) | core count from the GPU's SHADER_PRESENT; the MC4 mask must be checked against the hardware |
| devfreq | panfrost devfreq + OPP table | stock table and vsram rule instead of Asurada's |

## Open questions (to settle in G-S0 reads, not guesses)

1. Live rail values left by LK/preloader: vgpu (MT6315@7 vbuck1), CPU
   rails (MT6315@6), vsram_others (MT6359P; readable now via pwrap
   regmap).
2. The GPU's own SHADER_PRESENT with the stock MFG power-up: 0x50005 (fused)
   or more (then panfrost needs a core mask, as the vendor forces 4).
3. Which segment table the shipped kernel really uses ("14").
4. MT6315@3's bucks (consumers) and whether any MT6315 is touched by the
   mainline driver at probe.
5. MFG power-domain state at handover (on/off) and their KEEP_DEFAULT_OFF.

## G-S0 reads (2026-11-25, kernel #19, read-only)

- MT6359P (pwrap regmap): `vsram_others` VOSEL `0x1b48 = 0x28` → **0.750 V**,
  enabled (`0x1f08 = 1`, MON `0x1f0c = 3`). Also vsram_proc1 `0x1b44 =
  0x28` (0.750 V), vsram_proc2 `0x1b46 = 0x33` (0.81875 V), vsram_md
  `0x1b4a = 0x38` (0.850 V).
- SPM MFG0–6 control `0x308`–`0x320` = `0x1112` each (ISO, CLK_DIS,
  SRAM_PDN, SRAM ack; no PWR_ON), status `0x16c`/`0x170` bits 2–8 clear:
  **all GPU domains off at handover.** A G-S2 power-up is a first power-on
  (no takeover), so its sequence (vgpu/vsram on and at a stock point before
  MFG0, then MFG1–6) needs the full check.
- vgpu (MT6315@7) and the CPU rails (MT6315@6) cannot be read without an
  SPMI transaction: first read in G-S1.

## G-S1 pre-flash check (2026-11-25) — approved ("yes, go ahead")

1. **Image**: `boot-g1.img` sha256
   `c53b50c7fc5e5acba6ffecbda5dab41b4ecc5be6ae1880d248ceb4d21bf67a79`
   (Monolith), kernel **#20** (`Image.gz` `af4f6507…`, DTB `df449428…`).
   Writes `boot_a`. Module tree staged in `~/mod-k20` (installed as
   `/lib/modules/6.18.58-astro` before the flash, #19's kept as `.k19`,
   synced). Changes vs #19: `CONFIG_SPMI=y`, `SPMI_MTK_PMIF=y`,
   `REGULATOR_MT6315=y` (unmodified mainline, sha256 pinned); DT `&spmi`
   okay with bare `pmic@6/@7/@3` (`mediatek,mt6315-regulator`, reg only).
   Guard: sources pinned, children exactly pmic@3/6/7, no child nodes, no
   `regulator-*`/always-on/boot-on (negative test refused).
2. **What runs at boot** (audit of the sources):
   - `spmi-mtk-pmif` probe: maps registers, `clk_bulk_prepare_enable` of
     `infra_pmic_ap`, `infra_pmic_tmr` (ungated already, also held by
     pwrap) and `spmi_mst_sel`; assigned parent of `pwrap_ulposc_sel` =
     `osc_d10`, already live (`CLK_CFG_8 0x03010001`, and pwrap sets the
     same). **No PMIF register write at probe.** Transactions use software
     channel 2 (`0xC80`–`0xCA8`) = the stock AP channel (`ap_swinf_no 2`);
     channel idle (`0x8441`).
   - `mt6315-regulator` probe (×3): SPMI regmap init, registers vbuck1–4
     with **no init data** → the regulator core applies no voltage, no
     mode, no enable; reads only. `regulator_ignore_unused` (cmdline) →
     nothing is switched off later. No consumer exists (GPU, cpufreq off).
   - `.shutdown` on a clean reboot/power-off: TMA key 0x9C/0xEA, set
     `TOP2_ELR7` bit 0 ("power off sequence"), keys 0 — **the same writes
     as the stock driver** (`CONFIG_REGULATOR_MT6315=y` in the stock
     defconfig). Watchdog and power-key resets do not run it.
3. **Rails**: none changed; CPU rails (MT6315@6) and vgpu (MT6315@7) only
   read. MT6359P untouched (pwrap path unchanged) → 0xa12 stays.
4. **After boot (read-only)**: `uname -v` #20; dmesg for pmif/mt6315;
   `/sys/class/regulator/*/{name,microvolts,state}` for all MT6315 bucks
   (SPMI reads); 0xa12; console, Wi-Fi.

**G-S1 result (2026-11-25): passed.** User flashed `boot-g1.img`, kernel
#20; no pmif/mt6315 error, "Not disabling unused regulators", 0xa12
`0x21e0`, console on mediatek-drm, Wi-Fi up. Live rails (SPMI reads via
sysfs, nothing written):

| PMIC | buck | stock use | µV | state |
|---|---|---|---|---|
| MT6315@6 | vbuck1 | CPU big (proc1) | 600000 | on |
| MT6315@6 | vbuck3 | CPU little (proc2) | 718750 | on |
| MT6315@7 | vbuck1 | **vgpu** | **750000** | **on** |
| MT6315@7 | vbuck3, vbuck4 | ? | 750000 | off |
| MT6315@3 | vbuck1, vbuck3, vbuck4 | ? (to identify) | 825000 | on |
| all | vbuck2 | phase of vbuck1 | — | off |

vgpu is on at 0.75 V with every MFG domain off; vsram_others 0.75 V. 0.75 V
is a stock point (855 MHz / 0.75 V / vsram 0.75 V).

## Staged plan

Each stage with a write has its own pre-flash check and waits for a yes.

- **G-S0 — read-only.** vsram_others via the pwrap regmap; SPM MFG domain
  status; GPU/mfg clock registers; PMIF/SPMI registers (without driving the
  bus). No SPMI transaction.
- **G-S1 — SPMI + MT6315 regulators, no consumer (flash).** DT for the
  three MT6315s with constraints that include the live voltages (so the
  core never adjusts), no always-on changes, `regulator_ignore_unused`
  kept; audit `mt6315-regulator` and `spmi-mtk-pmif` probe writes. Check:
  live voltages unchanged after probe, 0xa12.
- **G-S2 — MFG domains + panfrost at one fixed stock OPP (flash).**
  Lowest stock point (358 MHz, vgpu 0.5625 V, vsram 0.75 V) or LK's live
  point; panfrost loaded by hand; read SHADER_PRESENT; kmscube / glmark2
  on the KMS console.
- **G-S3 — devfreq with the stock table** (vsram per the stock rule), then
  a desktop (Plasma) on panfrost.
