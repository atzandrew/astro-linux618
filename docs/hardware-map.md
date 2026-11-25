# Hardware map — Astro Slide 5G (MT6873)

Sources: vendor tree `astro-kernel` (Planet 4.14.186 BSP, commit
`a79860700`), mainline v6.18.58 (`kernel/BASE`). Unverified on-device
facts are marked *(vendor src)*; the live P0 dump will confirm or correct.

## SoC: MT6873 rides on mainline MT8192 (2026-11-25)

- Address map: `bin/dt-addr-compare.py <vendor mt6873.dts> <mainline mt8192.dtsi>`
  → vendor 380 addressed nodes, mainline 102, **97 at identical addresses**.
  Mainline-only: `0x11bc10` performance-controller, `0x1100bc00` svs,
  `0x11230000` pcie, `0x11234000` spi, `0x11c10000` efuse (to check whether
  these exist on MT6873 under other names or not at all).
- Pins: vendor `drivers/pinctrl/mediatek/pinctrl-mtk-mt6873.h` vs mainline
  `pinctrl-mtk-mt8192.h`: 228 `MTK_PIN` each; 1111 vs 1119
  `MTK_FUNCTION`; the only difference is mainline's 8 extra GPIO-only
  entries for GPIO220–227. Mux functions otherwise identical.

## Board (vendor src)

`arch/arm64/configs/k6873v1_64_defconfig`, `arch/arm64/boot/dts/mediatek/mt6873.dts`
(appended DTB `mediatek/mt6873`), ODM customisation by Aeon
(`aeon_gpio.dtsi`, `drivers/misc/mediatek/gpio/aeon_gpio.c`).

| Block | Vendor | Mainline 6.18 starting point |
|---|---|---|
| PMIC | MT6359P (+ MT6315 buck for CPU/GPU) | `mt6359` MFD/regulator/codec, `mt6315-regulator` |
| Charger / Type-C | MT6360 (TCPC, flashlight), FUSB301A switch (GPIO94 irq) | `mt6360` drivers |
| Storage | UFS and eMMC both enabled — check on device | `ufs-mediatek` / `mtk-sd` |
| GPU | Mali Valhall (G57 MC5), r25p0 | panfrost (`mediatek,mt8192-mali`; G57 is job-manager Valhall, not panthor) |
| Wi-Fi/BT/GPS | CONSYS 6873 (`MTK_COMBO_CHIP_CONSYS_6873`) | none; port gen-3 CONSYS like the Cosmo |
| Display | LCM `td4330_fhdp_dsi_cmd_auo_rt5081` 1080×2340 (MTK reference default — real panel TBD) | simpledrm first |
| HDMI | LT8912B DSI→HDMI bridge (`panel-vt-lt8912b-vdo.c`, `mtk_lt8912b.c`), HDMI det GPIO98 | `lontium-lt8912b` bridge |
| Touch | GT9897 (`TOUCHSCREEN_MTK_TOUCH`), FTS also built | `goodix-berlin`? check |
| Keyboard | AW9523 (`drivers/misc/mediatek/aw9523/aw9523_key.c`) | Cosmo/Gemini AW9523 driver |
| Slide sensor | hall EINT (`drivers/input/hall/hall.c`) | `gpio-keys` SW_LID |
| Other Aeon | function key, uswitch, usbl_det, aeonusb, keyboard light PWM, wireless charge enable, speaker enable GPIO30 | per block |
| Audio | `SND_SOC_MT6873_MT6359` | `mt8192-mt6359` machine as template |
| Cameras | imx586, s5k3l8, imx214, gc5035 | gc5035 from cosmo |
| Fingerprint | goodix-fp | later |
