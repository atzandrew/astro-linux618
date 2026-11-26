# Touchscreen on the Astro: stock reference and plan, 2026-11-25

## Stock

- Stock dtbo has two candidates: fragment@33 GT9896S on SPI7 and
  fragment@34 **GT9897 on I2C0 0x5d** (400 kHz). The stock log uses the
  I2C one: `goodix_i2c_probe` "ic type is BerlinA", `rom_pid:BERLIN`,
  `pid:9897`, `vid:06 01 03 21`, input `goodix_ts` + `goodix_ts,pen`;
  firmware runs from the chip's flash ("no valid normal config found").
- IRQ GPIO21 falling (`irq-flags` 2), reset GPIO20, 1080 × 2340, pen.
- `vtouch` = `mt_pmic_vtp_ldo_reg` = MT6360 LDO2 "VTP" (stock range
  1.2–3.6 V, `regulator-default-on`); neither the vendor touch driver nor
  the MT6360 LDO driver sets a voltage: it runs at the value it holds
  (mainline reads 1.8 V, off at boot).
- Pins (fragment@35): INT GPIO21 input, RST GPIO20 output; I2C0 =
  GPIO204/205 mode 1 (already set by LK).
- Vendor power-on (`goodix_brl_hw.c brl_power_on`): avdd on, 15 ms, reset
  high, then for Berlin-A `brl_reset_after`: 5 ms, hold CPU (0x0002 =
  01 00, check 0x2000), CLK_STA0 0xD807 = 0xFF, CLK_STA1 0xD806 = 0x77,
  TRIM_D12 0xD006 = 0x3C, 5 ms, soft reset 0xD808 = 0xFA.

## Mainline

`goodix_berlin` (core + i2c/spi): GT9897 (Berlin-A addresses
`*_ADDR_A`) is known to the SPI front end only. Power-on: vddio, 3 ms,
avdd, 15 ms, reset released, 4 ms; **no** Berlin-A `reset_after` writes.

Decision (user, 2026-11-25, option a): mainline as is (add the GT9897
I2C entry only); the vendor `reset_after` writes only if touch misbehaves.

## T1 findings (2026-11-26, kernel #23, `boot-tp1.img`)

- At the boot-default VTP 1.8 V the GT9897 NACKs every address on I2C0
  (scan with VTP on, reset GPIO20 high: nothing), 10 confirm retries over
  220 ms all `-ENXIO`. Not timing, not the bus format (vendor I2C uses the
  same 4-byte big-endian address).
- Stock shipped kernel: the FocalTech driver probes first on every boot
  (`fts_power_source_init`: `regulator_set_voltage(vtouch, 2600000,
  3300000)`, lowest = 2.6 V), fails ("not focal IC"), then the Goodix
  driver enables vtouch. **VTP 2.6 V** (user choice): the chip confirms on
  the first try (`aa × 8`), input "Goodix Berlin Capacitive TouchScreen"
  — without the vendor Berlin-A `reset_after` writes (decision a holds).
- Orientation (KWin, panel orientation Right Side Up): top-left landed
  bottom-left, top-right bottom-right → the touch X axis runs opposite to
  the panel's: DT `touchscreen-inverted-x`. X greeter (xrandr right):
  libinput CalibrationMatrix `0 1 0 -1 0 1` (rootfs
  `/etc/X11/xorg.conf.d/30-astro-touch.conf`).
