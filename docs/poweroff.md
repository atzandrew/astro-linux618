# Power-off on the Astro (MT6873 + MT6359P): stock path and the fix, 2026-11-25

User goal (2026-11-25): power off completely and stay off when not on
USB.

## Symptom

`poweroff` comes back: mainline calls PSCI SYSTEM_OFF, which the vendor
ATF does not act on, and the hang ends in a TOPRGU reset with the "bypass
power key" flag set (`NONRST_REG2` = `0x40002000`, bit 13, read
2026-11-25), so LK boots Linux again.

## Stock (vendor 4.14, k6873v1_64_defconfig)

- `CONFIG_MFD_MT6358=y`, `CONFIG_RTC_DRV_MT6358=y`, `CONFIG_MTK_PMIC_CHIP_MT6359P=y`;
  `CONFIG_MTK_RTC` builds only `mtk_rtc_debug.o` here (rtc Makefile), so
  the MT6771-style `mt_power_off()`/BBPU sequence is **not** used.
- `drivers/mfd/mt6358-core.c` probe: `pm_power_off = mt6358_power_off`:
  `regmap_update_bits(PMIC_RG_PWRHOLD_ADDR, 1, 0)`, i.e. MT6359P
  `PPCCTL0` (0xa08) bit 0 `RG_PWRHOLD` = 0 (`include/linux/mfd/mt6359p/registers.h`).
- `drivers/rtc/rtc-mt6358.c` `.shutdown`: only re-arms a pending power-on
  alarm (none set here). MT6315 shutdown (power-off sequence bit) as
  mainline `mt6315-regulator`.
- Charger present: the PMIC stays up; the vendor "charger" reset on wdt_v2
  (`mtk_wdt_v2.c` `wdt_arch_reset()`, `wd_api.c` `"charger"` → no
  `WD_SW_RESET_BYPASS_PWR_KEY`) clears `NONRST_REG2` bit 13, sets
  `WDT_MODE` = KEY | EXTEN without IRQ/dual mode, `SWRST` 0x1209: LK
  decides (power-off charging or off).

## Fix (`drivers/power/reset/mt6359-poweroff.c`, mt6397-core cell)

`mediatek,mt6359-pwrc` (DT child of the MT6359 node, opt-in) registers a
`SYS_OFF_MODE_POWER_OFF` handler (above PSCI): `RG_PWRHOLD` = 0; wait
11 × 100 ms; still on → the vendor charger reset (bit 13 cleared).
Read 2026-11-25: `PPCCTL0` = 0x0001, `WDT_MODE` = 0x7D.

## Power-off with USB plugged in (2026-11-26)

`systemctl poweroff` with the charger online (kernel #23, `boot-tp2.img`):
the board came back up in Debian ~1 min later (user). Not a fault of the
power-off path. This boot's cmdline has `androidboot.bootreason=usb`, and
the bootloader's `/chosen/atag,boot` says boot mode **8 =
KERNEL_POWER_OFF_CHARGING_BOOT** (vendor `mtk_boot_common.h`). So LK did
what stock does: it saw the charger and started the kernel in off-mode
charging (KPOC). Stock Android then runs its charger UI. In KPOC the vendor
kernel powers off when the charger goes away (`mt_kpoc_power_off_check`),
and Android's charger UI boots normally on a power-key press. We have no
KPOC handling, so Debian boots normally. Next: an off-mode charging target
in Debian (design for the user to decide). pstore was empty, so it isn't
confirmed which half of mt6359-poweroff ran; the outcome (KPOC) is the one
expected after the fallback reset.
