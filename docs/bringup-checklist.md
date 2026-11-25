# Astro bring-up checklist

Every hardware block the Astro Slide 5G needs under mainline 6.18: where
it sits, what mainline offers, what is done, and the order to do the rest.
Written 2026-11-25 (end of day 1) from the stock DTB and `dtbo` overlay
(`backup/`, decompiled), the vendor 4.14 BSP (`astro-kernel`), live stock
values (`docs/p0-findings.md`) and the bring-up so far
(`docs/session-log.md`). Format and many lessons from
`cosmo-linux618/docs/bringup-checklist.md`; the Cosmo row named in Notes
is the closest done equivalent.

Status: ✅ working on our kernel · 🔶 partly / interim · ⬜ not started ·
➖ out of scope for now. Mainline: **yes** = driver upstream (MT8192 /
MT6359 family), **fix** = upstream driver plus a delta, **port** = vendor
or Cosmo code to carry, **new** = nothing usable anywhere, **check** = not
confirmed. Order: the number in the last column is the suggested sequence
(see "Order" at the end); **rule 5** = touches the PMIC or a reset path
and needs a written pre-flash check and both escapes re-observed.

## Core platform

| | Block | Part / location | Mainline | Notes | Order |
|---|---|---|---|---|---|
| ✅ | Boot via LK | `boot_a` v2 (Image.gz + DTB), `dtbo_a` = `dtbo/astro-lk.dts` | — | LK contract in AGENTS.md and session log | — |
| ✅ | CPUs, GIC, timers | MT6873 on `mt8192.dtsi`, 4×A76 + 4×A55 | yes | all 8 online; no cpufreq/idle yet | — |
| ✅ | Watchdog / reboot | TOPRGU `mtk_wdt` | fix | escape observed (wdtest) | — |
| ✅ | Power-key 10 s reset | MT6359P STRUP_CON12 bit 13 (0x21e0) | (hardware) | observed on kernels #3 and #5; Linux never writes it | — |
| ✅ | USB device (gadget) | mtu3 `11201000`, t-phy, right-hand port | fix | U2 force bits (tphy delta); CDC-ECM + shell | — |
| ✅ | Console | own buffer at 0x70000000 through LK's command-mode DSI path | — (interim) | `astro-disp` / `astro-console`, idle blank 60 s; replaced by the DSI driver | 6 |
| ✅ | UFS | `11270000.ufshci`, SK hynix H9HQ15AFAMADAR | fix | G3B ×2, 991 MB/s read; legacy-IP and adapt-type guards; **read-only in init** | — |
| ✅ | Esc/power key | MT6359P PWRKEY (TOPSTATUS bit 1) | fix (`mtk-pmic-keys` MT6359P delta) | pmicB: KEY_ESC press/release; reset layout STRUP_CON12, stock one-key 8 s stated in DT, nothing written (docs/pmic-plan.md). Hold-for-power = rootfs userspace, as on the Cosmo | **1** rule 5 |
| ⬜ | PMIC core (pwrap + MT6359P MFD) | `pwrap@10026000`, EINT 214 | yes | comes with the keys; regulator/RTC/ADC/codec drivers stay off until audited; pwrap probe writes at undefined mt6873 offsets (watch) | **1** rule 5 |
| ⬜ | Volume keys | keypad `kp@10010000` (stock `kpd-hw-init-map` = VOLDOWN, VOLUP) | check (`mt6779-keypad`) | | 3 |
| ⬜ | Slide sensor (hall) | vendor `drivers/input/hall/hall.c` EINT | yes (`gpio-keys` SW_LID) | pin to read from vendor DT; Cosmo: lid row | 3 |
| ⬜ | Root filesystem | UFS `userdata` (sdc56) or `super` (sdc55) | — | decide the LU, lift the ro guard for it only; Debian via gemini-debian (Astro target) | **2** |
| ⬜ | RTC | MT6359P RTC | yes (`rtc-mt6397`) | check the vendor year encoding (Cosmo needed a delta) | 4 rule 5 |
| ⬜ | Regulators audit | MT6359P + MT6315 (CPU/GPU bucks via SPMI) | yes | every rail vs stock before any regulator driver binds; Cosmo: regulators row (VEMC lesson) | 4 rule 5 |
| ⬜ | cpufreq / DVFS | MT6315 bucks, CPU tables | check (mt8192 cpufreq-hw node not on MT6873) | needs the regulator audit first | 5 |
| ⬜ | Thermal | LVTS | check (mainline nodes not in vendor DT) | | 5 |
| ⬜ | cpuidle / suspend | SPM, MCUPM / SSPM | port | Cosmo: deep-sleep row (vendor ATF/SPM quirks) | 8 |
| ⬜ | Power off | MT6359P | new (Cosmo `mt6358-poweroff` pattern) | | 4 rule 5 |
| ⬜ | Other multi-channel I2C | i2c2/4/9 (`ch_offset_default 0x100`) | yes (DT `reg` +0x100) | same fix as i2c8 | with each device |
| ⬜ | microSD | msdc1, card-detect GPIO23 (active low, stock DTB) | yes (`mtk-sd`) | PMIC rails VMCH/VMC (rule 5); Cosmo: microSD row | 7 rule 5 |
| ➖ | Debug UART | UART0 | yes | no pads known | — |

## Power and USB

| | Block | Part / location | Mainline | Notes | Order |
|---|---|---|---|---|---|
| ✅ | Charger | MT6360 PMU `@34` (i2c5), INT GPIO24 (chg2: mainline mt6360-chg + adc, 500 mA SDP) | yes (`mt6360-charger`) | Cosmo used MT6370; BC1.2, input limits, temperature stop | 4 |
| ⬜ | Battery level | MT6359P gauge | new (Cosmo `mt6358-gauge` pattern) | | 5 |
| ⬜ | Type-C / PD | MT6360 TCPC `@4e` (i2c5), INT GPIO25 | yes (`tcpci_mt6360`) | sink first | 5 |
| ⬜ | Second USB-C port | FUSB301A `@25` (i2c6), vendor uswitch / aeonusb mux (GPIO13/127) | new (Cosmo `cosmo-fusb301a`) | left port; host mode | 7 |
| ⬜ | USB host mode | SSUSB xhci | fix | VBUS source per port | 7 |
| ⬜ | Wireless charging | Aeon enable GPIO | check | | later |

## Display and input

| | Block | Part / location | Mainline | Notes | Order |
|---|---|---|---|---|---|
| ✅ | Keyboard | AW9523 `@5b` (i2c8 at +0x100) | port (Cosmo driver) | keymap = stock; repeat 500 ms | — |
| ✅ | Console Fn layer | kernel default keymap | — | Planet US layout = gemini-debian `cosmo(us)`; UK variant possible | — |
| 🔶 | Keyboard backlight | GPIO28 (vendor PWM0 at 100 %) | yes (`gpio-leds`) | on/off only; used for boot codes | later |
| ⬜ | Panel (DSI) | SH8802B AMOLED 1080×2340, **command mode**, 4 lanes | port (`panel-sh8802b-vdo.c`) | mediatek DRM + DSI cmd mode; burn-in rules; DCS 0x51 brightness, 0x28/0x10 off | **6** |
| ⬜ | Display pipeline | OVL/RDMA/DSI (mt8192), IOMMU, mmsys, SCPSYS domains | yes | power domains and M4U first | **6** |
| ⬜ | Touch | GT9897 `@5d` (i2c0; GT9896S SPI variant also listed) | check (`goodix-berlin`) | which variant this unit has | 7 |
| ⬜ | HDMI out | LT8912B `@48` (i2c6), det GPIO98; SiI9022 also listed | yes (`lontium-lt8912b`) | needs DSI | later |
| ⬜ | Notification LEDs | red/green/blue (`mediatek,red` …) | check (MT6359 ISINK?) | | later |
| ⬜ | Vibrator | `mediatek,vibrator` (PMIC LDO) | check (`regulator-haptic`) | rule 5 | later |

## Graphics, media

| | Block | Part / location | Mainline | Notes | Order |
|---|---|---|---|---|---|
| ⬜ | GPU | Mali-G57 MC5 (Valhall JM) | yes (panfrost, `mt8192-mali`) | needs MT6315 GPU buck + SCPSYS | 8 |
| ⬜ | Video decode/encode | vdec/venc | yes (mt8192) | | later |
| ⬜ | Front camera | GC5035 (sub) | port (Cosmo) | Cosmo: front camera row | later |
| ⬜ | Rear cameras | IMX586 main, + EEPROM/AF (i2c2/i2c4) | new | | — |

## Connectivity, audio, other

| | Block | Part / location | Mainline | Notes | Order |
|---|---|---|---|---|---|
| ⬜ | Wi-Fi / BT / GPS | CONSYS 6873 | port (Cosmo gen-3 CONSYS) | big job, as on the Cosmo | 9 |
| ⬜ | Audio | MT8192-family AFE + MT6359 codec | yes (`mt8192-mt6359` template) | speaker enable GPIO30; amp part to check (AW6302?) | 9 |
| ⬜ | NFC | `nfc@28` (i2c3) | check | | later |
| ⬜ | Fingerprint | cdfinger FPS1098 (SPI) | new | | — |
| ➖ | Modem (5G) | md1img | — | | — |

## Order

1. **Esc/power key = first PMIC step** (pwrap + MT6359P MFD + fixed
   keys). Re-observe both escapes. Opens everything else on the PMIC.
2. **Root filesystem on UFS** → Debian (gemini-debian Astro target, Fn
   layer = cosmo xkb). After this, work moves off the initramfs.
3. Volume keys, slide sensor (small, DT mostly).
4. Regulator audit, then RTC, power off, charger (MT6360 on i2c5; i2c5
   is not multi-channel in the vendor DT, so mainline's base is right).
5. Battery gauge, Type-C PD, cpufreq/thermal.
6. **Display**: SCPSYS/IOMMU/mmsys, mediatek DRM with command-mode DSI,
   SH8802B panel; retires `astro-disp`.
7. Touch, second USB-C port and host mode.
8. GPU (panfrost), suspend.
9. Wi-Fi/BT, audio.
Later: HDMI, LEDs, vibrator, NFC, cameras, video codecs.
