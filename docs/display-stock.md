# Display (SH8802B AMOLED, command-mode DSI) on the Astro: stock reference (D0) and plan, 2026-11-25

Research only. No image was built or flashed, and no display, DSI or panel
register was written. Sources: the vendor 4.14 tree (`astro-kernel`, panel
driver `drivers/gpu/drm/panel/panel-sh8802b-vdo.c`, vendor DRM
`drivers/gpu/drm/mediatek/`, legacy `drivers/misc/mediatek/video/*/ddp_dsi.c`),
LK's own LCM table decoded from the P0 `lk_a.bin`, the LK log in
`backup/expdb.txt` (8 stock/our boots), LK's live registers
(`backup/disp-regs-lk.txt`), the stock DTB/dtbo (`backup/*.dts`), mainline
v6.18.58 (`build/src`), and the Shenghe SH8601A/SH8601Z datasheets (sister
controller; no SH8802B datasheet found).

Goal of the series: mainline mediatek-drm on the MT8192 path driving the
SH8802B through a proper panel driver, so that panfrost can drive a desktop.
The user's seven safety rules (session D0 brief) apply to every stage.
Shorthand below: **R1** = no NVM/OTP, **R2** = stock bytes only, **R3** =
power, **R4** = brightness, **R5** = burn-in, **R6** = link, **R7** = way back.

**Reference = stock Android** (user decision, 2026-11-25): where LK and the
stock Android kernel differ, we copy what the stock Android kernel does in
steady state. LK's values are recorded because LK still runs before us on
every boot and its state is what our driver takes over.

## Summary

- **Who drives the panel when.** LK (the bootloader) resets the panel and
  sends its own table on every boot. The stock Android kernel takes over
  without re-initialising: panel probe sets `prepared = enabled = true`
  (:719-720), and the DRM first enable only powers the DSI on
  (`mtk_drm_crtc_first_enable` → `mtk_dsi_poweron`: data rate, PHY on,
  clocks; no PHY timing, no TXRX, no panel command). The first DSI idle exit
  (`mtk_dsi_leave_idle`) or screen-on (`mtk_output_dsi_enable`) reprograms
  the PHY timings and DSI_TXRX_CTRL; every screen-on also runs the kernel's
  full init (`lcm_prepare`, seen in the stock log, expdb line 3784). So in
  day-to-day Android use the panel runs on the **kernel's** sequence and
  link settings.
- The two init tables **differ**: the kernel's has 12 extra gamma-table
  writes (C3–CE); LK's has `51 05 00` mid-table and `51 FF 03` at the end.
  We use the kernel's.
- Mainline has **no driver for this controller** or a relative, and nothing
  Shenghe at all (no SH8xxx, no vendor prefix, no `F0 3C 3C` unlock; no
  dri-devel patch found). No other device using the SH8802B was found; the
  Astro (Planet project x900) is the only source.
- Mainline `mtk_dsi` is **video-mode shaped**: it has no command-mode frame
  path (no type-1 "write memory" CMDQ packet, no external TE, no per-frame
  trigger, mutex SOF = DSI0 instead of single). That is the main new work.
- The PLL matches at 1050 Mbps (PCW `0x50C4EC4E`), but mainline's D-PHY
  timings are shorter than the stock kernel's: needs a delta.
- **0xD0 is a hazard byte**: on the sister SH8601A, 0xD0 is the OTP control
  register (MCS_PROG_EN). Both stock tables send `D0 80`. See "Non-volatile
  memory".
- All questions answered (Decisions, end of this doc).

## Hardware

| Item | Value | Receipt |
|---|---|---|
| Controller | SH8802B (Shenghe), AMOLED, own GRAM | LK `we will use lcm: sh8802b_fhdp_dsi_vdo_x900` |
| ID | DA = 0x5C, DB = 0x00, DC = 0x00 (LK reads these; the vt_dr6110 probe reads the same 0x5C, yet LK picks sh8802b — selection logic not decoded) | expdb.txt `lcm_compare_id,sh8802b_id=0x5c,0x0,0x0` (first boot near line 7877) |
| Status | DCS 0x0A = 0x9C after init (booster, sleep-out, display on, normal) | expdb `read from lcm 0x0A: 156`; vendor `lcm_esd_check_table` expects 0x9c |
| Mode | 1080×2340, RGB888, 4 lanes, **command mode**, 64×129 mm | vendor :447-463, :615, :677-680; LK `DSI Mode: CMD_MODE` |
| Link | PLL 525 MHz = 1050 Mbps/lane, SSC off | vendor `ext_params.pll_clk = 525` → `mtk_dsi_default_rate` = pll_clk × 2; LK `PLL_CLOCK: 525 … ssc_disable: 1` |
| Reset | GPIO42 (stock dtbo `reset-gpios = <&pio 0x2a 0>`), DWS default mode 1 LCM_RST; LK pinctrl and the kernel's gpiod switch it to GPIO mode | dtbo frag 3/11, gpio_init_default |
| TE | GPIO41 mode 1 = **DSI_TE** (dtbo `lcm_dsi_te` pinmux 0x2901; gpio_init_default mode 1); `EXT_TE_EN` set in DSI_TXRX_CTRL by LK and by the stock kernel | disp-regs-lk `dsi0+018 0x27C`; vendor `writel(0x0001023c, …TXRX_CTRL)` |
| "pm-enable" | GPIO41 in the dtbo panel node: same pin as TE; the SH8802B driver never uses it | dtbo panel2@0 |
| "bias" GPIOs | GPIO87 (`bias` index 0, "pos") and GPIO88 (index 1, "neg"). The stock kernel drives them around panel power (below). Their DWS default is mode 1 = `MIPI0_D_SCLK/SDATA` (modem RFFE, mainline pinctrl-mtk-mt8192.h :922-932); taking them as GPIOs switches them to mode 0. LK never drives them (its `lcd_bias_en*` pinctrl states are empty: `get pins_cmd_dat node fail` ×2 per init). Not panel supplies as far as any source shows | dtbo frag 3/11, vendor :343-401, expdb |
| Bias chip | LK tries I2C6 0x3e (LCD AVDD/AVEE bias, SM5109-style) twice per init and gets NACK: not fitted (AMOLED). The stock kernel has no I2C bias code (`CONFIG_RT5081/MT6370_PMU_DSV` unset) | expdb `id=6,addr: 3e … I2C_ACKERR`, defconfig |
| Supplies | **None declared anywhere in the stock sources.** No regulator in the panel driver, no `*-supply` on dsi/mipi_tx/panel nodes, LK touches no PMIC rail for the LCM. VDDI/VCI/ELVDD/ELVSS must be board-always-on or enabled by the panel module itself (Q7) | stock DTB, defconfig, vendor driver |
| Backlight | none: brightness is DCS 0x51 (`led@6 led_mode = 4` = "LCM"); `lcm_setbacklight_cmdq` | vendor :510-529, dtbo frag 2 |

Consequence for R3: Linux cannot, and must not, switch any panel rail. The
power-type controls are GPIO42 (reset) and, because stock Android does it,
GPIO87/88 in the stock order and timing.

## Stock sequences

### Where each comes from

| Source | Init table | When it runs |
|---|---|---|
| **Vendor kernel `lcm_panel_init` (:210-294) — our reference** | below | stock Android, every screen-on after the first screen-off |
| LK `lk_a.bin`, table at file offset 0xbedf8, 47 entries, `{u32 cmd; u8 count; u8 para[…]}` stride 0xd0, `0xFFFC` = delay ms, `0xFFFD` = end | below | every boot, before any OS (both boots LK probes: dr6110 then sh8802b) |

Extraction (receipt): the parser walks 0xd0-byte entries from the `F0 3C 3C`
entry; the table ends with `0xFFFD` at 0xc15c8. Six entries before it
(0xbe918: `28`, delay 50, `10`, delay 150, `29`, delay 100) are separate
arrays without end markers (LK's suspend table and a display-on table; their
use is not decoded).

### Power on (stock Android, `lcm_prepare` :369-420)

1. GPIO87 (bias 0) high → 2 ms → GPIO88 (bias 1) high (:381-401).
2. Reset GPIO42: low → 15 ms → high → 1 ms → low → 10 ms → high → 10 ms
   (:219-226; vendor `udelay(15*1000)` etc.).
3. Init table (next section).
4. `35 00` (TE on, V-blank only) → `11` (sleep out) → **200 ms** → `29`
   (display on) → **10 ms** (:289-293).

DSI host state around it (vendor `mtk_output_dsi_enable`): power on (rate
1050 Mbps, PHY on, clocks), engine enable, **PHY timing** (vendor formula),
`mtk_dsi_rxtx_control` (from the mode flags: 4 lanes, DIS_EOT,
HSTX_CKLP_EN), PS control, interrupts, exit ULPS, **clock lane LP**
(`clk_hs_mode(0)`), then `drm_panel_prepare` (all init commands in LP),
then `TXRX_CTRL = 0x0001023C` (EXT_TE_EN, non-continuous clock, **EoT on**),
command mode, clock lane HS, then `drm_panel_enable` (backlight). No
DSI_START in command mode; frames are triggered per update.

### Init table (stock kernel; every byte, :230-286)

```
F0 3C 3C          F1 3C 3C          D0 80             (:230-234)
B1 (45 p)  B2 (88)  B3 (40)  B4 (16)  B5 (58)  B6 (7)  B7 00     (:236-242)
BD (25)  BE (114)  DE 5C 00 00  DF (17)  E5 00 FF FF  E7 (10)     (:243-248)
F2 (32)  F3 (31)  F4 (36)  F5 (39)  F6 (21)  FB 11                (:249-254)
C3 CA C9 C8 C7 C6 C5 C4 CD   (187 params each, gamma)              (:255-263)
BF 10                                                              (:264)
CE CA C3                     (187 params each, gamma)              (:265-267)
D4 (18)  D5 (108)  B0 6D  D5 (108)                                 (:268-271)
90 33  91..94 (20 each)  95..9A (17 each)  9B (96)  9C (96)  9D (168)  (:272-285)
E4 (19)                                                            (:286)
```

57 writes, 3080 bytes. No 0x51 inside the table (brightness comes later
from the backlight path).

LK's table for comparison (machine compare of all bytes, values parsed from
the C source and from `lk_a.bin`): the same 45 non-gamma writes byte for
byte and in the same order; LK lacks the 12 gamma writes, and adds
`51 05 00` (after 9D) and `51 FF 03` (after `29` + 10 ms). Delays identical.
So when our driver first takes over after LK, the panel runs LK's gamma
(the panel's own OTP values); after our first off/on cycle it runs the
stock kernel's, exactly as on stock Android.

### Packet types (R2 includes the DSI data type)

MTK convention, both in LK and in the vendor drivers: **cmd < 0xB0 → DCS**
(0x05 no param, 0x15 one param, 0x39 long), **cmd ≥ 0xB0 → generic**
(0x23 one param, 0x29 long). Receipts: vendor panel `lcm_dcs_write`
(:83-86) uses `mipi_dsi_dcs_write_buffer` below 0xB0 and
`mipi_dsi_generic_write` above; legacy `DSI_set_cmdq_V2`
(`video/mt6765/dispsys/ddp_dsi.c:2789`, `if (cmd < 0xB0)`); LK's CMDQ dumps
show `0x00a93902` (0x9D as DCS long 0x39, 169 bytes) and reads
`0x00da1404` (0xDA as generic read 0x14) vs `0x000a0604` (0x0A as DCS read
0x06). Mainline `mipi_dsi_dcs_write_buffer`/`mipi_dsi_generic_write` pick the
same types for these lengths. All commands in **LP** (`MIPI_DSI_MODE_LPM`;
mainline `mtk_dsi_cmdq` never sets the HS bit).

Known stock quirk: LK times out once per init while sending the 169-byte
0x9D (`DSI_WaitForNotBusy: 1000` then a register dump, 9 times in 8 boots),
then carries on; the panel still reads 0x9C. Our driver must not react to a
slow LP long packet by retrying with other bytes.

### Power off (stock Android, `lcm_disable` + `lcm_unprepare` :296-367)

DSI side first (vendor `mtk_output_dsi_disable`): `drm_panel_disable`
(backlight power-down; `ctx->backlight` is NULL on this board, so no
command), wait for the running command-mode frame to finish, then
`drm_panel_unprepare`:

1. `28` (display off) → **50 ms** → `10` (sleep in) → **150 ms**.
2. GPIO42 low.
3. GPIO88 (bias 1) low → 1 ms → GPIO87 (bias 0) low.

Then DSI reset engine, ULPS, disable, power off. LK's own suspend table at
0xbe918 has the same `28/50/10/150`.

Not verified from source: whether Android's brightness path sends
`51 00 00` before screen-off (the framework sets the backlight to 0; the
MTK LED/DRM glue would map it to `lcm_setbacklight_cmdq(0)`). Harmless
either way; we send it only if Stage 0/1 work finds the glue does.

### Reads (allowed: standard DCS)

LK's exact read packets: `0x00013700` (set max return size 1), then
`0x00DA1404` / `0x00DB1404` / `0x00DC1404` (generic read 1 param, BTA) and
`0x000A0604` (DCS read 0x0A). Expected: DA 0x5C, DB 0, DC 0, 0x0A 0x9C. The
vendor ATA check reads DCS 0x04 (3 bytes). Stock ESD check is disabled
(`esd_check_enable = 0`).

### Brightness (R4)

- Format (SH8601Z datasheet PDF p.141, `WRDISBV 51h`): **2 params, DBV[7:0]
  then DBV[9:8]**, 0x000 lowest, 0x3FF highest. Stock Android:
  `lcm_setbacklight_cmdq` maps the Android level 0–255 →
  `level*1023/255`, sends `51 <low> <high>` (:513-526); the maximum is
  `51 FF 03` (0x3FF), which is also what LK leaves every boot.
- Mainline `mipi_dsi_dcs_set_display_brightness()` sends
  `{ v & 0xff, v >> 8 }` = the same byte order (not the `_large` variant).
- Driver: `max_brightness = 1023` (= stock Android 255), values clamped;
  userspace levels map 1:1 onto DBV. Default moderate: 512 (`51 00 02`,
  ≈ Android level 128).
- Not used, never sent: HBM `63h`/`66h`, AOD `48h/49h/4Ah`, `53h` (WRCTRLD,
  dimming/HBM bits on these parts), `55h`/`58h` (ACE/CE), deep standby `4Fh`
  (SH8601Z command list PDF p.85-86). Stock never sends them.

### Timing and mode

- Vendor mode: clock 172051 kHz, h 1080/59/10/64 (htotal 1213),
  v 2340/12/2/10 (vtotal 2364), 60 Hz. In command mode the panel's own
  timing (and TE) sets the refresh; the porches only fill DSI_VSA/VBP/VFP/
  HSA/HBP/HFP registers. The vendor link rate does **not** come from the
  mode clock: `ext_params.pll_clk = 525` → 1050 Mbps.
- Mainline derives the rate from the mode: `pixelclock × 24 / 4` → 172051
  kHz would give 1032.3 Mbps (**not stock**, R6). Plan: mode clock **175000
  kHz** (exactly 1050 Mbps; mainline's mipi-tx then writes PCW
  `0x50C4EC4E`, equal to LK's `MIPITX_PLL_CON0`). Side effect: the mode
  reports ~61 Hz; the panel's real rate is its own.
- D-PHY timing at 1050 Mbps (TIMCON0..3 = DSI +0x110..0x11c). Stock Android
  uses the **vendor formula** (`mtk_dsi_dphy_timconfig`; the panel sets no
  `phy_timcon` overrides, so every field is the formula value):

  | | TIMCON0 | TIMCON1 | TIMCON2 | TIMCON3 |
  |---|---|---|---|---|
  | **stock Android (vendor formula)** | **`0D110A0B`** (lpx 11, prep 10, zero 17, trail 13) | **`1637102C`** (go 44, sure 16, get 55, exit 22) | **`0F320103`** (cont_det 3, sync 1, clk_zero 50, clk_trail 15) | **`0016130B`** (clk_prep 11, post 19, exit 22) |
  | LK (live at handover) | `0C11090A` | `14320F28` | `0E320103` | `0014120A` |
  | mainline formula | `0C0D0B08` | `11200A1E` | `09240100` | `00121109` |

  Mainline's values are shorter in every field; we need a delta that
  programs the stock-Android values (R6).
- DSI_TXRX_CTRL: **stock Android `0x0001023C`** = 4 lanes, EXT_TE_EN,
  HSTX_CKLP_EN (non-continuous clock), DIS_EOT = 0 (EoT packets sent),
  written after panel init. During panel init the vendor's
  `mtk_dsi_rxtx_control` value applies: DIS_EOT and HSTX_CKLP_EN from the
  panel flags (`MIPI_DSI_MODE_EOT_PACKET` in 4.14 meant *disable* EoT,
  vendor :1065-1069; mainline name `MIPI_DSI_MODE_NO_EOT_PACKET`), no
  EXT_TE ("system would hang" comment). LK at handover: `0x27C`
  (continuous clock, no EoT, EXT_TE).
- Other DSI state (LK and stock Android agree): MODE_CTRL 0 (cmd), PSCTRL
  `0x2C030CA8` (packed RGB888, 3240 B/line), MEM_CONTI 0x3C (vendor writes
  `DSI_WMEM_CONTI` in rxtx_control). **Per frame** (vendor
  `mtk_dsi_config_trigger`, MTK_TRIG_FLAG_TRIGGER): mmsys +0xF0 = 1,
  CMDQ0 (+0x200) = **`0x002C3909`** (type 1 = frame data from the engine,
  HS, DCS long 0x39, 0x2C write_memory_start), CMDQ_SIZE (+0x60) = 1,
  DSI_START 0 → 1; EOF: poll for idle. DSI driver data: mainline
  `mediatek,mt8183-dsi` (cmdq 0x200, shadow 0x190) matches these offsets.

## Non-volatile memory (R1)

No SH8802B datasheet is public; the list below comes from the sister SH8601A
(Shenghe, 2019) and SH8601Z (2021) datasheets plus the stock tables. **It is
not complete for the SH8802B.** That is why the driver design is allowlist-only.

| Opcode | What (sister datasheet) | Stock use | Rule |
|---|---|---|---|
| **D0h** | **OTP control: MCS_PROG_EN bit starts OTP programming** (SH8601A §3.7, PDF p.46: VOTP 6.0 V applied, MCS_PROG_EN=1, wait ≥560 ms, MCS_PROG_EN=0) | `D0 80` in both stock tables | only the exact stock `D0 80`, only inside the fixed table; never any other value (Q8) |
| CFh | OTP program error status (read) | none | not needed |
| F0h / F1h | manufacturer command set access (key bytes `3C 3C`; SH8601 equivalents not in the UCS datasheet) | stock unlock | stock bytes only; no lock/unlock variants |
| B0h–FFh (all MCS registers incl. gamma C3–CE, B1–B7, BD–BF, D4/D5, DE/DF, E4–E7, F2–F6, FB) | manufacturer registers; OTP holds "Gamma, Chip ID, MCS register" (SH8601A PDF p.10); meaning per register unknown | stock table only | never written outside the fixed table |
| 90h–9Dh | manufacturer registers below 0xB0 (sent as DCS) | stock table only | same |
| 01h soft reset, 4Fh deep standby, 63h/66h HBM, 48h/49h/4Ah AOD, 53h/55h/58h | user commands, not NVM, but not in stock | never | not in the driver |

Physical note (sister part only, not proven here): SH8601A OTP programming
is "External Mode only" with a 6.0 V VOTP pin, normally left open on a module
(PDF p.10 feature table, PDF p.12 pin table). If the SH8802B module is the
same, `D0 80` cannot burn OTP without VOTP. We do not rely on that: the rule
is "stock byte only".

Writing the gamma tables (C3–CE) loads volatile registers, as every stock
Android screen-on does; it is not an OTP write (OTP programming needs D0h's
MCS_PROG_EN, above).

Driver design for R1/R2: the panel driver holds the stock kernel table as
one `static const` array and sends it with a fixed loop; there is no function
that takes an opcode or payload from outside (no debugfs, no sysfs, no
module parameter for commands, no "init sequence from DT"). The only
variable payload in the whole driver is the 0x51 value, clamped to
0..0x3FF. A build-time check (in `bin/build-boot-img.sh`) compares the
compiled table with the stock bytes hash.

## Mainline 6.18 gaps

| Area | Mainline today | Needed | Upstreamable? |
|---|---|---|---|
| Panel | nothing for SH8802B | new `panel-shenghe-sh8802b.c` (+ binding): stock kernel table, power on/off with GPIO42 and GPIO87/88 as stock, DCS backlight, "already on" handover at probe | yes |
| DSI command mode | `mtk_output_dsi_enable` sets mode and calls `mtk_dsi_start` once; `mtk_dsi_set_vm_cmd` and VDO timing always programmed; no type-1 CMDQ; no EXT_TE | cmd-mode path as stock: init in LP with clock lane LP, then TXRX `0x1023C`, no start; per frame CMDQ `0x002C3909` (size 1), MUTEX_EN, DSI_START 0→1, wait done; TE-paced | yes (others have asked for it; MT8188/8195 phones use cmd panels) |
| CRTC/vblank | vblank comes from the first component's frame-done IRQ (OVL0), periodic only in video mode | CRTC must trigger a frame per commit (and on cursor/plane update); TE-driven or fake vblank | yes, but the biggest piece |
| Mutex | `mtk_mutex_add_comp` sets SOF/EOF = DSI0 (MT8183 table: SOF_DSI0 = 1) | SOF **single** (LK `sof=single, eof=single`, MUTEX0_SOF 0; vendor `MT6873_MUTEX_SOF_SINGLE_MODE 0` for frame-trigger mode); one MUTEX_EN per frame | yes (small) |
| DDP path | `mt8192_mtk_ddp_main`: OVL0 → OVL_2L0 → RDMA0 → COLOR0 → CCORR → AAL0 → GAMMA → POSTMASK0 → DITHER0 → DSI0 | LK: OVL0_2L → OVL0 → RDMA0 → same chain (`mutex 0 value 0x93f7`). Either order works; use mainline's and compare the mmsys routing writes with LK's (`connect mout ovl0 to rdma0 bits 0x1`, `out_s rdma0 to color0 =1`, `in_s dither0 to dsi0 =1`) offline | n/a |
| D-PHY timing | formula from data rate (shorter than stock) | stock-Android values (vendor formula or fixed table for MT6873) | maybe |
| Link rate | from mode clock | mode clock 175000 kHz (exact 1050 Mbps) | yes (DT/panel only) |
| IOMMU | mt8192 `iommu0` + larbs; LK runs **M4U off** (`ddp path m4u off`) | first stages without IOMMU (OVL `iommus` dropped, CMA buffers below 4 GiB, larbs stay bypass as LK left them); IOMMU later, never while LK's path reads memory | DT |
| mmsys | `mediatek,mt8192-mmsys`: probe registers clk-mt8192-mm, reset controller and the `mediatek-drm` device, **writes nothing** | enable it (DISP clocks are needed for the domain anyway) | DT |
| Power domain | DISP (and its children) **deleted from spm** in W2 | add DISP back **without its children** (IPE, ISP, ISP2, MDP, VENC, VDEC, VDEC2, CAM, CAM_RAWA/B/C): none of them has `KEEP_DEFAULT_OFF`, so scpsys would power each on at probe. DISP itself: `scpsys_power_on` on an already-on domain only sets PWR_ON/2ND (set), clears CLK_DIS/ISO (clear), sets RST_B, clears SRAM_PDN bit 8, clears bus protection: idempotent **if** LK left it fully on (Stage 0 reads prove it). `pd_ignore_unused` stays | DT |
| Clocks | `clk_ignore_unused` keeps LK's gates | DRM must claim engine/digital/hs, OVL, RDMA, mutex, DSI clocks before anything is released | n/a |
| mipi-tx | `mediatek,mt8183-mipi-tx` at 0x11e50000, same as stock `mt6873-mipi-tx`; PCW formula matches | enable; check impedance/calibration writes against LK's `DSI_PHY0 REGS` dump in expdb.txt before the first `phy_power_on` | n/a |
| GCE/CMDQ | disabled; mediatek-drm works without it (CPU writes at vblank) | keep off (stock uses GCE for the same register writes; the values are what matters) | n/a |

## Burn-in plan (R5)

- Panel off = the stock Android off path above. Every test ends that way or
  with a black frame plus reset hold (today).
- DRM: DPMS off / CRTC disable → panel `disable` + `unprepare`. Desktop:
  KDE screen-off timeout (gemini-debian Astro target), console
  `consoleblank=60`.
- Static frames in command mode stay in the panel's GRAM indefinitely, even
  if every CPU hangs. Hard hang: the watchdog resets in ~31 s, LK re-inits
  (as today). Soft hang (kernel alive, compositor stuck): an Astro-only
  guard in the panel/DSI driver: if no new frame arrives for N seconds
  (default 600) while not off, run the off path (module parameter, not for
  upstream). Q7 covers whether you want that.
- Fallback stays: `astro-disp` black + reset hold if the DRM driver does not
  bind within a deadline after load.

## Staged plan

Every stage that writes anything has its own written pre-flash check,
following the template at the end, and waits for an explicit yes. All test
images keep `astro-disp`/`astro-console` and the simpledrm buffer at
0x70000000 working until Stage 5 is proven; mediatek-drm and the panel
driver are **modules, not loaded at boot** (blacklisted) until then.

**Stage 0 — read-only, no flash (needs root: `bin/astro-sh` rescue shell or
your `sudo`).** Read and record (`backup/d0-regs.txt`):
GPIO modes `0x10005350` (GPIO41/42), `0x100053a0` (GPIO87), `0x100053b0`
(GPIO88), DIR/DOUT/DIN banks `0x10005020/0x10005120/0x10005220` (GPIO87/88
bits 23/24); SPM DISP `0x10006350`, `0x1000616c`/`0x10006170` bit 20; bus
protection STA `0x10001228` (bits 6, 23), `0x100012ec` (MM_DISP bits),
`0x10001dd8` (bits 8, 12); DSI `0x14010000-0x140101ff` and CMDQ
`0x14010200`; mipi-tx `0x11e50000-0x11e500ff`; mutex `0x14001000-0x140010ff`;
mmsys CG `0x14000100/0x110/0x1a0`. Expected: matches `disp-regs-lk.txt`;
GPIO87/88 mode 1.

**Stage 0 result (2026-11-25, done, read-only; `backup/d0-regs.txt`,
kernel 6.18.58-astro under Debian, `sudo busybox devmem` reads only).**
- SPM DISP ctl `0x350 = 0x0000000D` (RST_B, PWR_ON, PWR_ON_2ND set; ISO,
  CLK_DIS, SRAM_PDN clear); status `0x16c`/`0x170` = `0xF8140A03`, bit 20
  set in both. **Fully on**, so mainline's PWR_* and SRAM writes at probe
  are no-ops.
- Bus protection: `0x228 = 0xE708100E` (DISP bits 6/23 clear),
  `0x2ec = 0xF5FD4BF5` (MM_DISP_2ND bits 1/3/15/17/25/27 clear; MM_DISP bits
  0/2/16/24/26 read set), `0xdd8 = 0x00001996` (MM_2 bits 8/12 read set).
  Mainline clears MM_DISP and MM_2_DISP with `BUS_PROT_WR_IGN` (no ack
  poll), and the **stock MT6873 power-on does the same writes**: vendor
  `clk-mt6873-pg.c` DIS_PROT_STEP1_0 (MM bits 0,2,10,12,14,16,24,26),
  STEP1_1 (MM_2 bits 8,12), STEP2_0 (bits 6,23), STEP2_1 (MM bits
  1,3,15,17,25,27), STEP2_2 (MM_2 bits 9,13), same registers (0x2a4,
  0x2d8, 0xdd0). So the Stage 2 power-on writes equal stock Android's.
- mmsys CG0 `0xF7FC40E0`, CG1 `0xFFFFFFFE`, CG2 `0xFFFFFFFE` (= the
  values the read guard required).
- GPIO: MODE5 `0x11111011` → GPIO41 mode 1 (DSI_TE), GPIO42 mode 0 (GPIO);
  DO1 bit 10 set (GPIO42 high, panel out of reset). MODE10 `0x11111111`,
  MODE11 `0x00111111` → **GPIO87/88 mode 1** (MIPI0_D_SCLK/SDATA), inputs,
  DIN 0.
- DSI: START 1, MODE_CTRL 0, TXRX `0x27C`, PSCTRL `0x2C030CA8`, CMDQ_SIZE 1,
  MEM_CONTI `0x3C`, TIMCON0..3 `0C11090A 14320F28 0E320103 0014120A`,
  shadow `0x6`, CMDQ0 `0x002C3909`. Mutex0 MOD `0x93F7`, SOF 0, EN 0.
  194 registers compared with `disp-regs-lk.txt`: 2 differ, both status
  (INTSTA `0x16` = CMD_DONE|TE_RDY|EXT_TE_RDY from our frames; `+0x1d4`
  `0x07410359`, a counter/debug register).
- mipi-tx: PLL_CON0 `0x50C4EC4E` and the rest (`+0x10 0x44441204`, `+0x30
  0x33076111`, `+0x34 0x01B10001`, `+0x38 0x098B098B`, `+0x3c 0x00FF12E0`)
  equal LK's `DSI_PHY0 REGS` dump.

**Stage 1 — DCS ID/status read through LK's path, no flash.** Shell test on
the running image: stop `astro-console` kicks, write LK's exact read packets
into CMDQ (`0x00013700`, then `0x000A0604`, `0x00DA1404`, `0x00DB1404`,
`0x00DC1404`), DSI_START, poll LPRX_RD_RDY, read RX_DATA, restore CMDQ0
`0x002C3909` / size 1, kick one frame. Writes: DSI host registers only; to the
panel only standard reads. Expect 0x9C, 0x5C, 0, 0. Proves BTA reads work in
our state, which Stage 3's probe uses.

### Stage 1 pre-flash check (2026-11-25) — approved and run (result below)

1. **Images**: none, no flash. Test = `bin/d1-dcs-read.sh` (sha256
   `0f2a03e2edf324cc7694b679f7482660e49a696fd49c4290629b72444620e233`),
   copied to the Astro and run as root under Debian on the running kernel
   (6.18.58-astro, unchanged).
2. **Writes** (all DSI host registers, 0x14010000; values from LK's own log):
   - `systemctl stop astro-console` first (no frame kicks during the test).
   - `astro-disp black` (existing tool): OVL SRC_CON 0, BGCLR 0xff000000,
     MUTEX0_EN, DSI_START, one frame with LK's queued `0x002C3909`.
   - Per read (4 reads): INTSTA +0x0c ← 0; CMDQ0 +0x200 ← `0x00013700`;
     CMDQ1 +0x204 ← `0x000A0604` / `0x00DA1404` / `0x00DB1404` /
     `0x00DC1404`; CMDQ_SIZE +0x60 ← 2; DSI_START +0x00 ← 0 then 1; poll
     LPRX_RD_RDY (INTSTA bit 0, ≤ 100 ms); read RX_DATA0 +0x74; INTSTA ← 0;
     RACK +0x84 ← 1 (as vendor `mtk_dsi_host_send_cmd`); wait not busy.
   - Restore CMDQ0/CMDQ1/SIZE to the values read at the start (CMDQ0 must
     be `0x002C3909` or the script stops before writing), one more black
     frame, then `systemctl start astro-console`.
   - **Panel commands**: only set-max-return-size 1 (0x37) and the reads
     DCS 0x0A, generic 0xDA/0xDB/0xDC: LK's packets byte for byte (expdb
     `DSI_CMDQ_DATA0 : 0x00013700`, `DATA1 : 0x000a0604 / 0x00da1404 /
     0x00db1404 / 0x00dc1404`). No write command reaches the panel except
     LK's write_memory_start frame (black).
   - Not touched: GPIO42 (unless a step fails), any rail, PMIC, mipi-tx,
     PHY timing, TXRX, mode, mutex SOF/MOD, OVL addresses.
3. **Power at probe**: nothing probes; no driver or DT change.
4. **R1**: no NVM opcode, reads only. **R2**: LK's packets. **R3**: no rail,
   no reset in the normal path. **R4**: brightness unchanged (LK's, as on
   every boot). **R5**: panel black during the test (pixels off), console
   back afterwards with its 60 s idle blank. **R6**: link untouched.
   **R7**: astro-disp/astro-console unchanged; any failure restores the CMDQ
   and sends a black frame, or holds reset if the frame fails.
5. **Burn-in bound**: no static image; black from the start of the test
   until astro-console restarts (≈1 s of reads).
6. **Escapes**: kernel/config unchanged, no PMIC access (0xa12 not at risk).
   A hung bus from a DSI register access would stop systemd feeding the
   watchdog → reset in ~31 s → LK re-inits the panel (as every boot).
7. **Undo**: nothing persistent. Expected output: 0x0A `type 0x21 value
   0x9C`; DA `type 0x11 value 0x5C`; DB, DC value 0x00. Anything else: stop
   and report, no retry with other packets.

**Stage 1 result (2026-11-25, user approved "go ahead").**
- First run stopped before any read: under `sudo sh` the PATH has no
  `devmem` (Debian keeps busybox applet links in `/usr/libexec/astro-bb`,
  which only the astro-console unit puts on PATH), so `astro-disp black`
  failed and the script exited (its own guard). Nothing was written by the
  script. The approved fallback black frame was then sent with the same
  `astro-disp black` (`frame done (3 ms)`). The console itself was never
  affected (its unit sets the PATH; journal shows `frame done`).
- Rerun, same script (sha256 `0f2a03e2…e233`) with
  `PATH=/usr/libexec/astro-bb:$PATH`:
  - before: CMDQ0 `0x002C3909`, CMDQ1 `0x00039651`, SIZE 1; black frame done.
  - **DCS 0x0A: RX_DATA0 `0x12009C21` → 0x9C** (DCS short read response).
  - **0xDA: `0x14005C11` → 0x5C**; **0xDB: `0x14000011` → 0x00**;
    **0xDC: `0x14000011` → 0x00** (generic short read response).
  - Each response within 1 ms; RX words identical to LK's
    (`DSI_RX_DATA0 : 0x14005c11 / 0x14000011`, `0x12009c21`).
  - after: CMDQ0/CMDQ1/SIZE restored, black frame done, astro-console active.
- So BTA reads work through LK's DSI state, and the panel is the SH8802B in
  normal mode (booster, sleep out, display on). No panel write besides the
  black frames.

**Stage 2 — DT + power domain, no DRM (flash).** spm DISP back without
children; mmsys, mutex enabled; dsi0, mipi_tx0, OVL/RDMA/… still disabled;
`CONFIG_DRM_MEDIATEK=m` built but not loaded. Check: genpd `disp` on,
no "failed to power on", SPM/bus-protect registers equal to Stage 0, console
still lit by `astro-disp`, 0xa12 = 0x21e0.

### Stage 2 pre-flash check (2026-11-25) — approved (user: "I'm good with your plans")

1. **Image**: `boot-d2.img` sha256
   `813fdf5bde5056d779b7f86302b9fa79918bc73e9954552d7d4ab32695fcfacf` (on
   Monolith `~/Build/astro-backup/`), kernel **#16** 6.18.58-astro
   (`Image.gz` `586d1786…9b65`, DTB `0ddd7e0c…db76`, boot DTB
   `240f8496…fdad`). Writes `boot_a` only. Matching module tree staged on
   the Astro in `~/mod-k16` (84 MiB; every module Debian loads today is in
   it). Changes vs kernel #13 (boot-w2):
   - DTS: spm keeps CONN and gets **DISP back with all seven children
     deleted** (IPE, ISP, ISP2, MDP, VENC, VDEC(+VDEC2), CAM(+RAWA/B/C));
     `mmsys` and `mutex` okay. Everything else on DISP stays disabled
     (checked in the compiled DTB: the mutex is the only enabled DISP
     consumer; dsi0, ovl*, rdma*, color/ccorr/aal/gamma/postmask/dither,
     smi, larb0/1, m4u disabled).
   - Config: `CONFIG_MTK_MMSYS=y` (was `=m`, never loaded because the node
     was disabled). `CONFIG_DRM_MEDIATEK` still unset, `PHY_MTK_MIPI_DSI`,
     `MTK_IOMMU`, `MTK_CMDQ` still off.
   - Guard: spm may list exactly CONN (1) and DISP (9), no nesting;
     negative test (DISP with a child) refused.
2. **Writes at probe** (no panel command, no DSI/OVL/mutex register):
   - scpsys DISP power on (`scpsys_power_on`), on SPM `0x10006350`
     (now `0xD`): set PWR_ON, PWR_ON_2ND (set), clear CLK_DIS, ISO (clear),
     set RST_B (set), clear SRAM_PDN bit 8 (clear; ack bit 12 already 0).
     Net change: none.
   - Domain clocks `disp_sel`, `mm_smi_infra` (CG0 bit 11),
     `mm_smi_common` (bit 17), `mm_smi_gals` (bit 27), `mm_smi_iommu`
     (CG1 bit 0): enable = write the CLR register; all already ungated
     (CG0 `0xF7FC40E0`, CG1 `0xFFFFFFFE`). Net change: none.
   - Bus protection clear (reverse table order): INFRA `0xdd0` ← bits 9|13
     (poll `0xdd8`: already 0), `0x2d8` ← bits 1|3|15|17|25|27 (poll
     `0x2ec`: already 0), `0x2a4` ← bits 6|23 (poll `0x228`: already 0),
     `0xdd0` ← bits 8|12 and `0x2d8` ← bits 0|2|10|12|14|16|24|26 (no
     poll). Same registers and masks as the stock MT6873 power-on
     (`clk-mt6873-pg.c` DIS_PROT_STEP*); the last two groups read "set" in
     STA and are cleared by stock on every power-on too.
   - mmsys probe: registers clk-mt8192-mm gates, a reset controller and an
     unbound `mediatek-drm` device; no register write. mutex probe: gets
     its clock and maps registers; no write.
   - `pd_ignore_unused`, `clk_ignore_unused` stay: nothing is switched off
     later.
3. **Power**: no rail, no regulator, no PMIC; CONN unchanged
   (KEEP_DEFAULT_OFF).
4. **R1/R2**: no panel traffic. **R3**: no rail; GPIO42 untouched by the
   kernel. **R4**: brightness untouched. **R5**: display path untouched;
   astro-console keeps driving LK's path (5 frames/s while active, black
   after 60 s idle). **R6**: link untouched. **R7**: astro-disp/
   astro-console and the 0x70000000 buffer unchanged.
5. **Burn-in bound**: as today (console black after 60 s idle; LK's orange
   frame during boot as always).
6. **Escapes**: watchdog path unchanged; PMIC drivers and DT unchanged
   (guards pass), so 0xa12 stays out of reach; read it after boot
   (expect `0x21e0`). If the DISP power-on hung (it should not: every
   poll's condition is already true), the watchdog resets in ~31 s.
7. **Order and undo**:
   1. On the Astro (agent, with your yes): `mv /lib/modules/6.18.58-astro
      /lib/modules/6.18.58-astro.k13bt`, move `~/mod-k16/6.18.58-astro`
      into `/lib/modules/`, `depmod -a 6.18.58-astro` (kernel #13 keeps
      running until the reboot; no module is reloaded).
   2. You, on Monolith: `cd ~/Build/astro-backup && mtk w boot_a
      boot-d2.img`, then reboot the Astro into the preloader window as for
      W2 (board stays in DA mode after the write until a ~10 s power hold).
   3. Undo: `mtk w boot_a boot-w2.img` (kernel #13) and move
      `6.18.58-astro.k13bt` back (rescue shell or Debian).
8. **After boot (agent, read-only)**: `uname -v` = #16; dmesg for
   `scpsys`/`disp`/`mtk-mmsys`/`mutex` errors; genpd summary (`disp` on,
   `conn` as before); SPM `0x350`, `0x16c/0x170`, bus-protect STA, CG0/CG1
   re-read and compared with Stage 0; 0xa12; Wi-Fi up; console visible
   (you).

**Stage 2 result (2026-11-25).** User flashed `boot-d2.img`
(`813fdf5b…`); boots to Debian, kernel #16; user: console still up.
- genpd: `disp` on (consumer `14001000.mutex`), `conn` on (consys active);
  "Not disabling unused power domains"; no scpsys/mmsys/mutex error. mmsys
  bound to `mtk-mmsys`, mutex to `mediatek-mutex`, `clk-mt8192-mm` loaded.
- Registers identical to Stage 0: SPM `0x350 = 0xD`, `0x16c/0x170 =
  0xF8140A03`; bus protect `0x228 = 0xE708100E`, `0x2ec = 0xF5FD4BF5`,
  `0xdd8 = 0x1996`; CG0 `0xF7FC40E0`, CG1/CG2 `0xFFFFFFFE`; DSI TXRX
  `0x27C`, TIMCON0 `0x0C11090A`; mutex0 MOD `0x93F7`.
- 0xa12 = `0x21e0`. Wi-Fi up (192.168.0.138), astro-console active.
- dmesg otherwise as on #13 (afe-pcm -110, MFD of_node notes, UFS reset
  controls).

**Stage 3 — mediatek-drm takeover, as stock Android boots (flash).**
mediatek-drm + mtk_dsi command-mode delta + panel driver as modules; load by
hand. Panel probe = stock: assume LK left it on (`prepared/enabled = true`),
**send nothing at probe**. DSI first enable = stock first enable (power on
only; LK's PHY timing and TXRX stay). Then: black frame, `51` moderate, a
short test pattern, black, then the stock off path. First time Linux sends
panel commands: only frame data (`2C`/`3C`), `51` and the off sequence.
Fallback: if the driver does not bind in 10 s, the test script runs
`astro-disp black` + reset hold.

### Stage 3 pre-flash check (2026-11-25) — awaiting an explicit yes

1. **Image**: `boot-d3.img` sha256
   `e34f96a30d966b1d66a5e5992d59c230d93dada0a104f3a302a5a19485833022`
   (Monolith `~/Build/astro-backup/`), kernel **#18** (`Image.gz`
   `dd967c2c…e8d7`, DTB `e3e22955…1695`). Modules staged in `~/mod-k18`
   on the Astro: `mediatek-drm.ko` `f3dbe5ab…b0c3` (rebuilt: + firmware framebuffer removal at bind),
   `panel-shenghe-sh8802b.ko` `17916e83…fc12`, `phy-mtk-mipi-dsi-drv.ko`
   `931e2226…8265`. Test script `bin/d3-drm-test.sh` `d309774a…734e`.
   Writes `boot_a` only.
2. **Code (kernel/delta, all upstream-shaped):**
   - `drivers/gpu/drm/panel/panel-shenghe-sh8802b.c` (new, sha256 pinned
     in `build-boot-img.sh`): the stock init table as one const stream
     (54 writes, checked byte for byte against the vendor source, stream
     sha256 `3d925a04…68e5`), stock power on/off, DCS backlight 0..0x3ff
     (default 0x200), `prepare_prev_first`. First prepare after load sends
     nothing (bootloader left the panel on, as the vendor probe).
     `allow_init=0` (module parameter, default): after an off, a prepare
     sends nothing and keeps reset low. The init table is unreachable in
     Stage 3.
   - `mtk_dsi.c`: `mediatek,mt6873-dsi` (stock-Android D-PHY timing,
     host-checked: `0D110A0B 1637102C 0F320103 0016130B`; no shadow write).
     Command mode: no engine reset at bind or power-on, no video-mode
     registers, masked PSCTRL, MEM_CONTI 0x3C; enable ends with TXRX
     DIS_EOT cleared and EXT_TE_EN set (stock `0x1023C`); per-frame trigger
     (mutex re-armed, CMDQ0 `0x002C3909`, START 0→1); off waits for the
     frame instead of a video-mode stop.
   - `mtk_crtc.c`, `mtk_ddp_comp.[ch]`, `mtk_disp_drv.h`: command-mode CRTC
     (mutex SOF single, config written before each trigger, frame-done IRQ
     completes the flip, disable waits for the black frame).
   - `mtk-mutex.c`: DSI0 is a mutex module on MT8192/MT6873 (bit 12, as
     vendor `MT6873_MUTEX_MOD_DISP_DSI0` and LK's MOD `0x93F7`). Built in.
   - `phy-mtk-mipi-dsi*.c`: `mediatek,mt6873-mipi-tx`, the vendor
     prepare/unprepare sequence (PLL left alone if already on; no
     impedance writes; lanes released at power on).
   - DT: dsi0 + panel@0 (reset GPIO42 active low, bias GPIO87/88,
     pinctrl TE/reset as LK), mipi_tx0, main path OVL0…DITHER0 okay, OVL0/
     OVL_2L0/RDMA0 without `iommus` (CMA buffers, larbs untouched).
   - Config: `DRM_MEDIATEK=m`, `PHY_MTK_MIPI_DSI=m`,
     `DRM_PANEL_SHENGHE_SH8802B=m`, DP/HDMI off; IOMMU and CMDQ off.
   - Guards: DRM only as a module, panel source pinned, real DSI node may
     only carry panel@0 `shenghe,sh8802b` (negative test with a stock-style
     compatible refused), spm unchanged (CONN + childless DISP).
3. **At boot**: nothing new runs. The modules are blacklisted
   (`/etc/modprobe.d/astro-d3.conf`); astro-console drives LK's path as
   today. Built-in change: only the mutex driver (no write at probe).
4. **The test** (agent runs it, you watch the panel):
   1. stop astro-console (its stop hook sends a black frame);
   2. modprobe PHY, panel, mediatek-drm. Writes, in order:
      - PHY probe: none. Panel probe: pinctrl GPIO41 mode 1 / GPIO42 mode 0
        (unchanged); GPIO42 output high (unchanged); **GPIO87/88 → GPIO
        mode, output high (as the stock probe; LK leaves them in mode 1)**.
      - Modeset (fbcon): mmsys routing for the mainline path order, mutex
        MOD `0x13F7` (OVL0, OVL_2L0, RDMA0, COLOR0, CCORR, AAL0, GAMMA,
        POSTMASK0, DITHER0, DSI0) and SOF 0, component config (1080×2340,
        bypass), DSI enable, PHY timing → stock-Android values, PSCTRL
        fields, interrupts; PHY PLL left as LK set it (PCW `0x50C4EC4E`);
        lanes: TXRX `0x1007C`, D-PHY reset pulse, ULP leave, then
        `0x1023C`, clock lane HS.
      - **Panel traffic**: none at prepare; enable: set max return size +
        DCS read 0x0A (logged, expect 0x9C); brightness `51 00 02`
        (0x200, stock mapping ≈ Android level 128; stock max is `51 FF 03`);
        then frames (`2C`/`3C` pixel data) only when the console changes.
   3. console visible for 20 s at 0x200, registers read back;
   4. DPMS off (`fb blank 4`): black frame, then the stock off: `28`,
      50 ms, `10`, 150 ms, GPIO42 low, GPIO88 low, 1 ms, GPIO87 low; DSI
      to ULPS and off, PHY PLL off. The panel stays off until a reboot.
5. **R1**: no NVM opcode can be sent: the only manufacturer table is
   unreachable (`allow_init=0`), the only variable byte is 0x51's value.
   **R2**: stock bytes only (0x0A read, `51 00 02`, `28`/`10`, frames).
   **R3**: no rail; reset only after `28`/50 ms/`10`/150 ms; GPIO87/88 as
   stock Android. **R4**: 0x200 ≤ stock 0x3FF; no HBM. **R5**: lit ≤ ~25 s,
   ends off; you watch. **R6**: 4 lanes, 1050 Mbps (PLL untouched), RGB888,
   command mode, stock-Android D-PHY timing and TXRX. **R7**: astro-console
   works at boot as today; if the driver does not bind within 10 s the
   script sends `28`/`10` through the live DSI (LK's own off packets),
   else a black frame, reset hold only as the last resort.
6. **Escapes**: watchdog path unchanged; no PMIC change; 0xa12 read after.
7. **Order**: (a) agent: install `~/mod-k18` as `/lib/modules/6.18.58-astro`
   (keep #16's as `.k16`), depmod, write the blacklist; (b) you: `cd
   ~/Build/astro-backup && mtk w boot_a boot-d3.img`, reboot as before;
   (c) agent: check boot (#18, console up, modules not loaded, 0xa12),
   then run `d3-drm-test.sh` while you watch.

**Stage 3 test 1 result and re-run (2026-11-25).** First boot of #18:
blacklist file empty (not flushed before the hard reset), so the modules
autoloaded next to astro-console; panel switched off through the driver.
Test 1 (blacklist fixed, framebuffer removal added to mtk_drm_bind):
takeover registers exactly as planned, but no frame completed: LK's
reverse-order OVL routing (OVL_MOUT_EN `0x9`, OVL0_MOUT_EN RDMA0, OVL0
BGCLR_SEL_IN) stayed set next to mainline's, the OVLs fed each other's
background. Off path ran. Re-run image `boot-d3b.img` `76cc5770…34e4`,
kernel #19: mt8192 OVL routes write the whole selectors (clearing LK's
bits), mtk_crtc turns the first OVL's background input off;
`mediatek-drm.ko` `4a0c7f13…ddae`; panel and PHY modules unchanged
(panel source still the pinned one); test script `76d3ae97…5b65` (also
dumps routing/OVL registers). Panel traffic and every other point of the
check above unchanged.

**Stage 3 result (2026-11-25): passed.** Kernel #19, `mediatek-drm.ko`
`120c114e…fd80` (on top of the re-run image: polled command-mode
transfers, read = RD_RDY → RACK → CMD_DONE, as the vendor driver). Run 5:
- takeover: no panel init; **power mode read `0x9C`**; console moved from
  simpledrm to mediatek-drm (fb0) and drawn through the command-mode path;
  **brightness `51 00 02` applied (user: visibly dimmer)**;
- registers: TXRX `0x1023C`, TIMCON `0D110A0B 1637102C 0F320103
  0016130B`, PSCTRL `0x2C030CA8`, CMDQ0 `0x002C3909`, PLL untouched
  (`0x50C4EC4E`), routing OVL_MOUT_EN `0x6`, OVL0_2L_MOUT RDMA0, OVL0
  mout cleared, RDMA0 sel `0x3`, OVL0 background input off, OVL_2L0 on;
- DPMS off: stock off sequence without timeouts, then GPIO42 low, GPIO88/87
  low, DSI off, PHY PLL off;
- 0xa12 `0x21e0` before each run.
Findings on the way (all fixed in the delta): rootfs writes need `sync`
before a hard reset (blacklist came back empty); LK's reverse-order OVL
routing must be cleared; the DSI interrupt is not delivered while the
engine waits for RACK, so command-mode transfers poll as the vendor does.
Open: the DPMS-off step took ~20 s longer than the script's own sleeps
(nothing in dmesg); to be measured in Stage 4.

**Stage 4 — full stock screen-on (flash or module reload).** Stock DSI
enable (stock PHY timing, rxtx, LP init) and panel `prepare`: GPIO87/88,
reset 15/1/10/10 ms, the 57-write stock table, `35 00`, `11`, 200 ms, `29`,
10 ms, TXRX `0x1023C`, brightness. First time Linux sends the manufacturer
table. Read 0x0A = 0x9C after it. Short exposure, then off.

### Stage 4 pre-flash check (2026-11-25) — approved ("yep")

1. **No flash, no new code.** Kernel #19 and the installed modules as in
   the Stage 3 result (`mediatek-drm.ko` `120c114e…fd80`,
   `panel-shenghe-sh8802b.ko` `17916e83…fc12`, source pinned
   `b7553237…6980`). The only change: the panel module is loaded with
   `allow_init=1`. Test script `bin/d4-drm-test.sh` `35d78c00…2450`
   (copied to the Astro, synced). Start state: fresh boot, LK's console.
2. **Sequence:**
   1. As Stage 3: stop astro-console (black frame), load PHY, panel
      (`allow_init=1`), mediatek-drm; takeover with no panel init (read
      0x0A, `51 00 02`); console; then DPMS off 1: `28`, 50 ms, `10`,
      150 ms, GPIO42 low, GPIO88 low, 1 ms, GPIO87 low; DSI off, PHY PLL off.
   2. 5 s off.
   3. **DPMS on = stock screen-on** (vendor `lcm_prepare`):
      - DSI/PHY power on: PHY PLL from off with the vendor MT6873 sequence
        (PLL_CON4 `0x00FF12E0`, LANE_CON `0x3FFF0180`→`0x3FFF0080`, PCW
        `0x50C4EC4E`, POSDIV 1, PLL on, SW_ANA_CK on; lanes released), D-PHY
        timing `0D110A0B 1637102C 0F320103 0016130B`; lanes ready with
        TXRX `0x1007C` (EoT off, clock lane LP) for the init, as stock.
      - GPIO87 high, 2 ms, GPIO88 high; reset: low 15 ms, high 1 ms, low
        10 ms, high 10 ms (GPIO42).
      - **The 54-write stock table** (stream sha256 `3d925a04…68e5`, byte
        identical to the vendor source), all LP, cmd < 0xB0 DCS, else
        generic: `F0 3C 3C`, `F1 3C 3C`, **`D0 80`** (approved, Q8), B1–B7,
        BD, BE, DE, DF, E5, E7, F2–F6, FB, gamma C3/CA/C9/C8/C7/C6/C5/C4/CD,
        BF 10, gamma CE/CA/C3, D4, D5, B0 6D, D5, 90–9D, E4.
      - `35 00`, `11`, 200 ms, `29`, 10 ms; then TXRX `0x1023C`, clock HS.
      - enable: read 0x0A (expect `0x9C`), `51 00 02`; frames.
      - If any write fails, the driver stops sending and runs the off
        sequence (`28`/`10`, reset, bias low).
   4. Console 10 s at 0x200, then DPMS off 2 (stock off, as step 1).
   Each off and the on are timed (the Stage 3 off took ~20 s longer than
   expected).
3. **R1**: no command outside the stock table; `D0 80` only inside it
   (your approval); the table is const and pinned. **R2**: stock bytes,
   order, packet types and delays (vendor `lcm_prepare`/`lcm_panel_init`).
   **R3**: no rail; reset and bias in the stock order; reset only after
   `28`/`10` on every off. **R4**: 0x200; no 0x51 inside the table (stock
   kernel table has none). **R5**: two lit windows (~10 s each) plus the
   takeover; ends off; you watch. **R6**: 1050 Mbps, 4 lanes, RGB888,
   stock-Android timing and TXRX. **R7**: a reboot restores LK's console;
   if the driver does not come up the script sends LK's `28`/`10`.
4. **Escapes**: no kernel change, no PMIC access; 0xa12 read before.
5. **Expected on glass**: console (dimmer) → dark → after ~5 s the panel
   wakes (stock gamma now, colours may look slightly different from LK's)
   → console → dark.

**Stage 4 result (2026-11-25): passed.** Fresh boot, kernel #19, panel
module with `allow_init=1`, script `35d78c00…2450`:
- takeover as Stage 3 (power mode `0x9C`, console, `51 00 02`); DPMS off 1
  in 0.21 s (stock 50 + 150 ms + overhead);
- **DPMS on = first Linux screen-on**: PHY from off (read back after:
  PLL_CON1 `0x33076111`, PCW `0x50C4EC4E`, LANE_CON `0x80`, all equal to
  LK's), bias + reset 15/1/10/10 ms, the 54-write stock table, `35 00`,
  `11`, 200 ms, `29`, 10 ms: **power mode `0x9C`**, no error; TXRX
  `0x1023C`, timing as stock Android; console back at 0x200;
- DPMS off 2 in 0.21 s; GPIO42/87/88 low; 0xa12 `0x21e0` before and after.
- The "~20 s slower off" of Stage 3 was the test script reading 20
  DSI/PHY registers with their clocks gated (each read stalls), not the
  driver; the scripts no longer read them after an off.

**Stage 5 — console and desktop.** fbdev emulation on mediatek-drm, DPMS,
idle off, retire `astro-disp`; then panfrost.

**Stage 5a result (2026-11-25): console on mediatek-drm by default.**
Rootfs only (gemini-debian `overlay-astro`): Stage 3 blacklist removed,
`options panel_shenghe_sh8802b allow_init=1`, `astro-console.service`
disabled, `astro-display.service` + `/usr/bin/astro-display-check`
(waits ≤15 s for mediatek-drm, sets the console blank to 60 s, else starts
astro-console on LK's path). One module fix: mediatek framebuffers get a
dirty callback (`drm_gem_fb_create_with_dirty`), so fbcon drawing becomes
commits and frames (without it the command-mode panel froze on the last
commit; module `ec1a2330…5a56`). Results (user on glass): boot → console
on mediatek-drm at 0x200; 60 s idle → stock off (GPIO42/87/88 low,
`bl_power 4`); keypress → stock screen-on (`0x9C`, three cycles logged);
typing shows; blanks while logged in too (the old astro-console limit is
gone). Frames ~5/s with the cursor blink.
Open for Stage 5b: hang-proof off path (R5) before unattended use, CMA
(32 MiB) or IOMMU for a desktop, KDE screen-off (DPMS), then panfrost.

**Stage 5b (2026-11-25).**
- Idle-off guard (`mediatek_drm.idle_off_s`, default 600 s; module only):
  tested with 20 s and the cursor blink off: stock off after 20 s without a
  frame, keypress → stock screen-on, `0x9C`. Defaults restored.
- Pre-flash check, `boot-d5b.img` `c81d2e19…4703` (writes `boot_a`):
  kernel #19 unchanged (`Image.gz` `d23428d8…317b`, DTB `e3e22955…1695`);
  the only change is `cma=256M` on the command line (was the 32 MiB
  default, placed at `0xfb800000`, 13 MiB in use by the console). CMA comes
  from free memory below 4 GiB; LK's mblocks are all in `/reserved-memory`.
  No PMIC, display or panel change; `mediatek-drm.ko` `0aa9ec9c…90bc`
  (guard log fix) installed and synced. Check after boot: `CmaTotal`
  262144 kB, console on mediatek-drm, 0xa12.
- Result: flashed by the user; `CmaTotal` 262144 kB (243 MiB free with
  the console up), console on mediatek-drm (`0x9C`), Wi-Fi up, 0xa12
  `0x21e0`.

### Pre-flash check template (each stage fills it in)

1. Images and sha256; partitions written.
2. Every register the image or test writes (address, value, why, source of
   the value), and every panel command (opcode, bytes, type, delay) with its
   stock receipt.
3. What powers on at probe (genpd, clocks, regulators) and why it was
   already on.
4. R1-R7 one by one.
5. Burn-in bound: longest time a static image can be lit.
6. Escapes: kernel/config changes vs the established ones; 0xa12 after.
7. Undo path and fallback if the driver fails to probe.

## Decisions (user, 2026-11-25)

Reference = stock Android steady state. That settles the former questions:

1. Gamma tables: **send C3–CE** as the stock kernel does (57-write table).
2. Brightness: no 0x51 inside the table; stock mapping, cap 0x3FF, default
   moderate (512).
3. GPIO87/88: **drive them as the stock kernel does** (87 high, 2 ms, 88
   high before reset; 88 low, 1 ms, 87 low after reset low).
4. DSI link: stock kernel values (vendor-formula PHY timing, TXRX
   `0x1023C` after init, LP init with clock lane LP).
5. Link rate 1050 Mbps via mode clock 175000 kHz (stock rate; mainline has no
   separate HS-rate input).
6. Reset timing: stock kernel's 15/1/10/10 ms.
7. Panel rails: **no schematic knowledge** (user). Treated as board
   always-on and not controllable; no rail is ever touched. Tests are
   supervised: the user watches the panel during every lit test and turns it
   off if anything looks wrong. The soft-hang guard is not needed for
   supervised tests; R5 still requires a hang-proof off path before anything
   ships unattended (decide at Stage 5).
8. `D0 80`: **approved** (user), only as part of the fixed stock table and
   only from Stage 4 on. No other D0h value, ever.

No open questions. Stages 0–4 done; next: Stage 5 (console and desktop on mediatek-drm by default).

## Correction (2026-11-26): the shipped Android kernel sends no gamma tables

Checked the stock kernel *binary* (`backup/boot_a.kernel`, "Linux version
4.14.186 … Wed May 24 18:56:15 BST 2023", gunzipped) against the source in
`astro-kernel` (`panel-sh8802b-vdo.c` `lcm_panel_init`, gamma writes inside
`#if 1`). All 31 long non-gamma writes of the source are in the binary's
rodata, contiguous and byte-identical (0xfab782–0xfabd15). **None of the 12
gamma writes (C3–CE, 137 bytes each) is anywhere in the binary**, and no
array with the gamma header (`Cx 00 00 FF 04 00…`) exists: F6 (0xfab9c8,
22 bytes) is followed directly by D4 (0xfab9e2). So the kernel that ran on
the Astro under Android did **not** load the gamma tables, like LK: the
panel ran its OTP gamma. The released source is not what shipped.
Our driver (decision 1 above, based on the source) sends all 12 after the
first off/on. That is not the stock steady state. Pending the user's
decision: drop the 12 gamma writes so our table = shipped kernel = LK.

## Stage G1 pre-flash check (2026-11-26) — approved ("ready")

Change (modules only, kernel #23 unchanged, no boot image, no mtk write):
`panel-shenghe-sh8802b.ko` `16129a3f…` (source `e1c03287…`, PANEL_SHA in
build-boot-img.sh updated) and `mediatek-drm.ko` `0b630611…`, built from
kernel/delta (build log out/build-gam1.log), vermagic
`6.18.58-astro SMP preempt mod_unload aarch64` = running kernel.

1. **Panel init table = the shipped Android kernel's** (correction above):
   the 12 gamma writes C3–CE removed; the remaining 42 writes are byte- and
   order-identical to the stock source minus gamma, and all 31 long ones sit
   in the shipped binary's rodata in the same order. Then 35 00, 11, 200 ms,
   29, 10 ms as before. Reset/bias GPIO order and delays unchanged. Only
   fewer writes; nothing added. Takeover after boot still sends nothing.
2. **Read-only debugfs `sh8802b/dcs_regs`** (test aid): four 1-byte standard
   DCS reads, the same packet type as the existing 0Ah power-mode read —
   0Ah RDDPM, 54h RDCTRLD1, 56h RDCTRLD2 (ACL), 59h RD_CE (SRE). No
   set-maximum-return-size packet (panel default 1), no write. Refused
   unless the panel is lit; serialised with brightness writes and
   enable/disable by a driver mutex.
3. **mtk_dsi**: host transfers (commands, reads) and command-mode frame
   triggers now take one mutex, so a read/command never overlaps a frame
   (each already waited for the link to be idle; the gap was between those
   checks). Lock order idle_lock → xfer_lock and panel lock → xfer_lock
   only; no path takes them the other way.

Rules: **R1** no OTP/MTP/NVM command. **R2** shipped stock bytes only
(fewer than before); reads are standard DCS. **R3** no rail or GPIO change.
**R4** brightness path unchanged (default 512, cap 0x3FF). **R5** idle-off
guard, fbcon blank, greeter and Plasma idle unchanged. **R6** link, lanes,
format, timing unchanged. **R7** the previous modules stay on the device.

Deploy: copy both .ko into /lib/modules/6.18.58-astro (old ones kept),
depmod, sync, reboot.
Test (user watching): (a) boot, takeover as before (power mode 0x9C);
read dcs_regs = LK state. (b) let it blank, wake: first init without gamma;
power mode 0x9C; read dcs_regs again. (c) pattern + Plasma text at 512 and
1023, compared with the earlier photos.
Expected reads (sister-chip defaults): 54h 0x28 (BCTRL, DISP_DIM),
56h 0x00 (ACL off), 59h 0x00 (SRE off). Anything else is reported, not
changed.

**Stage G1 result (2026-11-26): passed.** Modules installed on kernel #23
(old ones in /var/tmp/modules-pre-g1), reboot. Takeover as before (power
mode 0x9C). dcs_regs in the bootloader's state: 0Ah 0x9C, 54h **0x20**
(BCTRL on, DISP_DIM off; the sister chip's default is 0x28), 56h 0x00 (ACL
off), 59h 0x00 (SRE off). First Linux screen-on without the gamma tables
(greeter blank → key): power mode 0x9C, same four values. So SRE and ACL are
off in both states. Pattern at 512 and 1023 (user): "both tests looked much
better than before"; text also better. The stock-source gamma tables were
the main cause of the rough text after the first wake. Side finding: the
greeter ran at backlight 114, not 512 (KWin output config brightness 0.5).

## Android's SoC-side picture processing (2026-11-26)

From the P0 `super.bin` (vendor_a, read-only, on Monolith): vendor
build.prop `ro.vendor.mtk_pq_support=2`, `ro.vendor.mtk_aal_support=1`,
`ro.vendor.mtk_pq_color_mode=1`; service `vendor.mediatek.hardware.pq@2.2`.
Customer tuning in `libpq_cust_base.so` (pqparam tables, cust_gamma, DRE,
gamut matrix, MDP sharpness) and `libaal_cust.so`: ReadabilityEnhancementMode
25, ReadabilityLevel 207, ESS_alg_mode 31, SmartBacklightStrength/Range 128,
LcmGamma 2.2 (float), DRE and ESS level controllable by the kernel.
So under Android the COLOR/AAL/DRE blocks processed the image in user space
(MediaTek's proprietary AAL/PQ algorithms, partly ambient-light driven).
Mainline here keeps all of them in bypass/identity: the panel receives the
framebuffer pixels unmodified.
Static parts decoded (libpq_cust_base.so): `cust_gamma` = 15 presets x RGB x
512 (u16); preset 7 is identity, 0-6 scale blue down (warmer), 8-14 red
down (cooler): a colour-temperature slider, nothing panel-specific.
`gamut_matrix_en` 1, `BT709_c*` in 13-bit fixed point (8192 = 1.0):
[1.069 -0.061 -0.008; -0.031 1.039 -0.008; -0.031 -0.030 1.092], a
saturation boost; the name suggests video (BT.709) content, scope unknown.
`pqparam_table` 7 rows of the 15-field DISP_PQ_PARAM (sharpness, global sat,
partial Y, hue adj x4, sat adj x4, contrast, brightness, ccorr, ...), e.g.
row 0 {2,4,0, 9,9,12,12, 0,6,10,10, 4,4,0,0}: region (skin/grass/sky) hue and
saturation tweaks for the COLOR engine. That engine is region-based (not a
matrix or 1D LUT), undocumented, and not programmable through mainline DRM.
Decision: no reproduction for now. The dynamic AAL/DRE/readability part is
closed and content/ambient driven; the static part is a colour-temperature
set (Plasma Night Light covers it), a vivid-style saturation matrix, and
COLOR-engine region tweaks with no mainline interface. None is a panel
correction; the panel's own OTP gamma is in use.
