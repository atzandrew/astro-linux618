# Step 2 plan: pwrap + MT6359P core + power key (Esc)

Status: **for review** (2026-11-25). Nothing here is built or flashed yet.
Policy: mainline drivers and bindings, small upstreamable deltas, vendor
BSP as the reference for facts only (AGENTS.md). All device values below
were read on chg2 (kernel #8) with read-only accesses (`devmem` reads of
the pwrap block; PMIC reads through pwrap WACS2 with `/tmp/pmicrd`).

## Why this is the risky step

The MT6359P holds the 10 s power-key reset, our main escape (rule 5).
Its control is **STRUP_CON12 0xa12** = `0x21e0` now:
bit 13 `PWRKEY_RST_EN` = 1, bits 15:14 `PWRKEY_RST_TD` = 0 (8 s, vendor
Kconfig table 0→8 s, 1→11 s, 2→14 s, 3→5 s), bit 12 `PWRKEY_KEY_MODE` = 0
(power key alone). Stock Android writes exactly these values at every boot
(`drivers/input/keyboard/mediatek/mt6873/hal_kpd.c`
`long_press_reboot_function_setting`, `ONEKEY_REBOOT_NORMAL_MODE=y`,
`KPD_PMIC_LPRST_TD` default 0).

The Cosmo lost this escape once (cosmo-linux618 try9): mainline
`mtk-pmic-keys` used the wrong bit layout and cleared the reset enable.

## 1. pwrap (`drivers/soc/mediatek/mtk-pmic-wrap.c`, compatible `mediatek,mt6873-pwrap`)

Mainline already has an mt6873 entry and `mt8192.dtsi` already has the
node. What its probe does on this board, against the vendor driver
(`astro-kernel drivers/soc/mediatek/mtk-pmic-wrap.c`, `pwrap_mt6873`,
caps `ARB_V3`) and the live registers:

| Probe action | Mainline | Vendor (stock) | Live value | Effect |
|---|---|---|---|---|
| `assigned-clocks`: PWRAP_ULPOSC_SEL → OSC_D10 | reparent | enables both | parent already `osc_d10` | none (same parent) |
| read INIT_DONE2 (mainline offset 0) | skip init if ≠ 0 | reads PMIF_INIT_DONE (0x0) | 0x00000001 | init skipped, as stock |
| WACS2_RDATA bit 15 check | 0xCA8 | same | 0x00008441 | passes |
| `WDT_SRC_EN` = 0xffffffff | **undefined → offset 0** | **also undefined → offset 0** | 0x1 | stock does the same write |
| TIMER_EN/TIMER_CTRL 0x3E0 = 3 | yes | yes | 3 | unchanged |
| INT_EN / IRQ_EVENT_EN_3 0x448 | = 0x30 | \|= 0x30 | 0 | same result (0x30) |
| IRQ handler: read flags, clear | **INT_FLG/INT_CLR undefined → offset 0** | IRQ_FLAG_3 0x450 / IRQ_CLR_3 0x454 | 0 / 0 | mainline never clears a real flag: level IRQ would storm |

**Delta (upstreamable bug fix):** add `[PWRAP_INT_FLG] = 0x450` and
`[PWRAP_INT_CLR] = 0x454` to `mt6873_regs` (vendor offsets), so the
handler acks the real flags. Recommended as well: skip the `WDT_SRC_EN`
write when the SoC has no such register (mt6873 has none in either map)
instead of writing 0xffffffff to offset 0. Stock does write it, so this is
a cleanliness fix, not a safety one; it can be left out for a stock-equal
first test.

No PMIC register is written by the pwrap probe (init is skipped).

## 2. MT6359P core (`drivers/mfd/mt6397-core.c` + `mt6358-irq.c`)

- Reads `MT6359_SWCID` (chip ID). HWCID 0x8 = 0x5930 (MT6359P).
- Creates a device for **every** MT6359 function, with or without a DT
  node: auxadc, regulator, rtc, sound, keys, accdet. Any built-in driver
  binds. Config keeps all but keys off: `REGULATOR_MT6359=n` (**today =y
  from defconfig**, harmless only because pwrap is off),
  `RTC_DRV_MT6397=n`, `MEDIATEK_MT6359_AUXADC=n`, `SND_SOC_MT6359=n`,
  `SND_SOC_MT6359_ACCDET=n`.
- IRQ init **writes 0 to every interrupt-enable register** (vendor does a
  disable-all at init too, then drivers enable their own). Values LK left:

  | Reg | Name | Now | After |
  |---|---|---|---|
  | 0x1418 | BUCK_TOP_INT_CON0 | 0x0000 | 0 |
  | 0x1b14, 0x1b1a | LDO_TOP_INT_CON0/1 | 0xffff, 0x3fff | 0 |
  | 0x910 | PSC_TOP_INT_CON0 | 0x0025 | 0, then keys set 0x0005 |
  | 0x528 | SCK_TOP_INT_CON0 | 0x0000 | 0 |
  | 0xc32, 0xc38 | BM_TOP_INT_CON0/1 | 0x0000 | 0 |
  | 0xf92 | HK_TOP_INT_CON0 | 0x0000 | 0 |
  | 0x2328 | AUD_TOP_INT_CON0 | 0x0000 | 0 |
  | 0x188 | MISC_TOP_INT_CON0 | 0x0000 | 0 |

  These only gate the PMIC's interrupt line to the AP (EINT 214, unused
  today). LDO over-current protection itself is separate hardware.
- PMIC interrupt: pio EINT 214, level high (stock DTB).

DT: a minimal child of `&pwrap`, not mainline `mt6359.dtsi` (that one
describes regulators, RTC and codec):

```dts
&pwrap {
	pmic: pmic {
		compatible = "mediatek,mt6359";
		interrupts-extended = <&pio 214 IRQ_TYPE_LEVEL_HIGH>;
		interrupt-controller;
		#interrupt-cells = <2>;

		keys {
			compatible = "mediatek,mt6359-keys";
			mediatek,long-press-mode = <1>;	/* one key, as stock */
			power-off-time-sec = <0>;	/* raw TD field: 8 s, as stock */
			power { linux,keycodes = <KEY_ESC>; wakeup-source; };
			/* no home key on the Astro */
		};
	};
};
```

## 3. Power key (`drivers/input/keyboard/mtk-pmic-keys.c`)

Register layouts (vendor `include/linux/mfd/mt6359{,p}/registers.h`):

| Field | MT6359 | **MT6359P (ours)** | Mainline `mt6359_regs` |
|---|---|---|---|
| PWRKEY_RST_EN | 0x14a bit 9 | **0xa12 bit 13** | 0x14c bit 6 |
| PWRKEY_RST_TD | 0x14a bits 13:12 | **0xa12 bits 15:14** | 0x14c bits 9:8 |
| PWRKEY_KEY_MODE | 0x14a bit 8 | **0xa12 bit 12** | — |
| 0x14a bit 5 | WDTRSTB_DEB | WDTRSTB_DEB | "HOMEKEY_RST" |

Mainline's table is the MT6397/MT6358 layout at 0x14c, the **SET alias**
of 0x14a (0x14e is CLR). It is wrong for both MT6359 variants; with any
long-press setting it would set watchdog-reset bits in TOP_RST_MISC.
(Today, with no DT properties, the read-modify-write reads 0 from the SET
alias and writes nothing, but that is luck, not design.)

**Delta (upstreamable bug fix):**
- MT6359P table: `pmic_rst_reg` = STRUP_CON12 0xa12, pwrkey `rst_en_mask`
  BIT(13), homekey (two-key mode) BIT(12), `rst_lprst_mask` GENMASK(15, 14).
- Pick it when HWCID (0x8) reads 0x5930; for any other MT6359 ID keep the
  current behaviour unchanged. (A plain-MT6359 table, 0x14a bits 9/8/13:12,
  is the same fix for that chip, but we can't test it here.)
- With the DT above, the driver computes mask 0xf000 / value 0x2000; 0xa12
  & 0xf000 is 0x2000 already, so `regmap_update_bits` **writes nothing**.
  The driver now states the stock configuration rather than relying on
  luck.

**Esc vs power:** as on the Cosmo, the kernel reports the key as
`KEY_ESC` (DT `linux,keycodes`, no driver change). "Hold for power" is a
userspace policy for the rootfs (logind / a small daemon), not a kernel
tap/hold split. That keeps the driver mainline. (Replaces the in-kernel
split in the old AGENTS.md plan.)

Debounce status: TOPSTATUS 0x2a bit 1 (mainline `deb_mask` 0x2: matches,
0 = pressed). Press/release IRQs: PWRKEY / PWRKEY_R (mainline
`key_release_irq = true`).

## Config

```
CONFIG_MTK_PMIC_WRAP=y
CONFIG_MFD_MT6397=y          # already y
CONFIG_KEYBOARD_MTK_PMIC=y   # image B only (below)
CONFIG_REGULATOR_MT6359=n
CONFIG_RTC_DRV_MT6397=n
CONFIG_MEDIATEK_MT6359_AUXADC=n
CONFIG_SND_SOC_MT6359=n
CONFIG_SND_SOC_MT6359_ACCDET=n
CONFIG_SPMI_MTK_PMIF=n
```

The rule-5 guard in `bin/build-boot-img.sh` is narrowed from "no pwrap"
to this exact shape: the pwrap child is `mediatek,mt6359` with only a
`keys` child; regulator/rtc/auxadc/sound/accdet drivers absent; the keys
delta present (a marker string in the built driver).

## Test order (two images, each with a written pre-flash check)

- **Image A, pwrap + MT6359P core, no keys driver.** Proves the bus and
  the IRQ init in isolation. Checks: probe log, regmap debugfs read of
  0xa12 = 0x21e0 and 0x14a = 0x0225 (unchanged), IRQ enables as in the
  table, no pwrap IRQ storm. Then both escapes: power-key hold, and the
  watchdog (`astro.wdtest=1` variant).
- **Image B, + keys (with the delta).** Checks: 0xa12 still 0x21e0, Esc
  reaches the console, press/release both seen, then both escapes again.

If image A or B ever reads 0xa12 with bit 13 clear: stop, don't power off.
Rewrite it from the running shell (stock value 0x21e0, one written
command for the user), then re-check before any reset.
