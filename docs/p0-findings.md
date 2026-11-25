# P0 findings — Astro Slide 5G

## Live, stock Android, non-root adb shell (2026-11-25, via Monolith)

| Item | Value | Receipt |
|---|---|---|
| Build | `Planet/Astro_Slide_5G_Transformer/Astro:11/RP1A.200720.011/1733015923:user/release-keys`, patch 2023-03-05 | `getprop ro.build.fingerprint` |
| Kernel | 4.14.186, built 2023-05-24 | `uname -a` |
| Board / platform | `k6873v1_64`, `mt6873` | `ro.product.board`, `ro.hardware` |
| Lock state | **locked**, verified boot **green**, AVB 1.1, verity enforcing | `ro.boot.flash.locked=1`, `ro.boot.vbmeta.device_state` |
| OEM unlock | allowed (`sys.oem_unlock_allowed=1`, `ro.oem_unlock_supported=1`) | getprop |
| Slots | **A/B**, current `_a` | `ro.boot.slot_suffix` |
| Boot images | `boot_a/b` + **`vendor_boot_a/b`** + `dtbo_a/b` (header v3 likely — confirm from image) | `/dev/block/by-name` |
| Dynamic partitions | yes (`super` = sdc55) | `ro.boot.dynamic_partitions` |
| Storage | **UFS** (`11270000.ufshci`; partitions on `sdc`, preloader in LU boot0/boot1 — named `mmcblk0boot*` links); eMMC host `11f60000.mmc` also listed in boot_devices | `ro.boot.boot_devices`, by-name links |
| `dtb_idx` / `dtbo_idx` | 0 / 0 | getprop |
| Display | 1080×2340, density 480 | `wm size`, `wm density` |

Partitions (by-name → sdc N): misc 1, para 2, expdb 3, frp 4, nvcfg 5,
nvdata 6, vbmeta_a 7, vbmeta_system_a 8, vbmeta_vendor_a 9, vbmeta_b 10,
…_b 11/12, metadata 13, protect1 14, protect2 15, seccfg 16, otp 17,
md1img_a 18, spmfw_a 19, pi_img_a 20, dpm_a 21, scp_a 22, sspm_a 23,
mcupm_a 24, cam_vpu1-3_a 25-27, gz_a 28, lk_a 29, boot_a 30,
vendor_boot_a 31, dtbo_a 32, tee_a 33, sec1 34, proinfo 35, nvram 36,
boot_para 37, logo 38, _b copies 39-54, super 55, userdata 56,
flashinfo 57.

I2C devices bound (names unreadable as shell; guesses from vendor src):

| Bus-addr | Likely |
|---|---|
| 0-0038, 0-005d | touch: FocalTech FTS (0x38), Goodix GT9897 (0x5d) |
| 2-0010, 2-001a, 2-0050, 2-0072 | rear camera sensors/EEPROM/VCM |
| 3-0028 | ? |
| 4-001a, 4-0050 | camera sensor + EEPROM |
| 5-001a, 5-0034, 5-004e, 5-0064 | **MT6360** PMIC / PMU / TCPC / LDO (its 4 standard addresses) |
| 6-0025, 6-0034, 6-0039, 6-003e, 6-0048, 6-0050 | 0x48 LT8912B? 0x39 SiI902x TPI? others TBD |
| 8-0051, 8-005b | 0x5b **AW9523** keyboard? |
| 9-0051 | ? |

Blocked without root: `/proc/cmdline`, `/proc/partitions`, fb0 sysfs,
dmesg, `/proc/device-tree`, i2c device names. These come from mtkclient
reads (lk, boot, vendor_boot, dtbo, expdb) instead.

## mtkclient preloader connection (2026-11-25)

`mtk printgpt` caught the preloader after `adb reboot` (no buttons):
MT6873, HW code 0x886, subcode 0x8a00, HW ver 0xca00. Target config 0x0:
**SBC disabled, SLA disabled, DAA disabled**, no root cert, no memory
read/write auth → "Device is unprotected". DA: `MTK_DA_V5.bin` (xflash),
mtkclient patches hash_check / get_vfy_policy / anti-rollback in DA.
WDT 0x10007000, UART0 0x11002000. mtkclient disables the WDT on connect.
After the first command the board stays in DA mode (`0e8d:2000`) and the
next `mtk` handshake fails until a 10 s power-key hold (same as Cosmo).
Full GPT: `~/Build/astro-backup/printgpt.log` on Monolith. super = 6 GiB,
userdata ≈ 112 GiB, UFS user LU total 0x1dcb019000 (≈119 GiB).

## Boot chain, from the P0 dumps (2026-11-25)

Copies on Hydra in `backup/boot-chain/` (gitignored), checksums match
Monolith's `SHA256SUMS`.

- **boot_a: Android boot header v2**, page 2048. Kernel gzip (Image.gz,
  0xa04071 B → 28.8 MB) @0x40080000, ramdisk gzip 0x81a9e3 @0x47c80000,
  tags 0x4bc80000, **DTB in the v2 dtb section** (0x29dc9 B, wrapped in an
  Android DT table, magic `d7b7ab1e`, 1 entry, id 0), os 11.0.0 / 2023-03.
  Cmdline: **`bootopt=64S3,32N2,64N2 buildvariant=user`** — same `bootopt=`
  pattern as the Cosmo.
- **vendor_boot_a/b: all zeros** (partition present, unused).
- **dtbo_a**: DT table, 1 overlay entry, 293 fragments. Carries the panel
  list under DSI: `panel1@0 "vt,dr6110,vdo"`, `panel2@0 "sh8802b,vdo"`,
  `panel3@0 "vt,lt8912b,vdo"` (HDMI bridge), `lt8912@48`, AW9523 pinctrl,
  Goodix touch (1080×2280/2340 variants), placeholder `atag,videolfb-*`.
- Model/compatible of base DTB: `"MT6873"` / `"mediatek,MT6873"`.

## Panel and LK framebuffer (expdb LK log, several boots)

- LK probes `vt_dr6110_fhdp_dsi_vdo_x900` (i=0) then
  `sh8802b_fhdp_dsi_vdo_x900` (i=1); both read ID `0x5c`;
  **"we will use lcm: sh8802b_fhdp_dsi_vdo_x900"** on every boot.
  Android kernel also runs `sh8802b lcm_prepare`. `x900` = Planet project.
- **Panel is SH8802B AMOLED, 1080×2340, 4-lane DSI, RGB888, PLL 525 MHz,
  in COMMAND MODE**: LK dump `DSI Mode: CMD_MODE`; vendor driver
  `astro-kernel/drivers/gpu/drm/panel/panel-sh8802b-vdo.c:679` sets only
  `MIPI_DSI_MODE_LPM | MIPI_DSI_MODE_EOT_PACKET` (video flags commented out
  at :681-684) despite the "vdo" name. Timings :453-460 (clock 172051),
  64×129 mm (:615-616). Backlight via DCS 0x51.
- **LK framebuffer: 0x7dd80000, size 0x1d80000**, pitch **4352**
  (1088 px), format MTK `eBGRA8888` (= memory B,G,R,A; expect simplefb
  `a8r8g8b8` — verify with a test pattern), OVL1 layer 0. 3 buffers of
  1088×2368×4 (`DISP_GetFBRamSize` 30916608). Boot logo layer separately
  at 0x7e754000 pitch 4320.
- I2C bus 6 addr 0x3e ACK errors in LK = LCD bias chip probe (not fitted;
  AMOLED).

### Consequence for first boot (differs from the Cosmo)

The Cosmo panel was video mode: the display engine kept scanning LK's
buffer, so simpledrm just worked. A **command-mode** panel keeps its own
GRAM and only updates when the DSI engine is triggered for a frame. After
handoff the screen will most likely freeze on the last frame LK sent; plain
simpledrm writes will probably not appear. Options (to decide before first
boot): (a) a minimal "frame kick" — re-trigger LK's already-configured
mutex/DSI path periodically from the kernel (no panel init sent, no
re-config); (b) bring up mediatek DRM with a command-mode DSI path early;
(c) first boots blind, signs of life via expdb/ramoops + USB gadget.

## Reset escapes — what the stock logs and source say (2026-11-25, not yet observed under our kernel)

**SoC watchdog (TOPRGU 0x10007000).** LK configures it enabled: `[WDT]
mtk_wdt_mode LK config mode value=7d` (bit 0 EN set); the stock 4.14
kernel's dump at reset shows `MTK_WDT_MODE:0x7d`, `MTK_WDT_LENGTH:0xffe0`,
`MTK_WDT_INTERVAL:0xfff` (expdb). Same mode/length as the Cosmo (~31 s).
Some boots log mode `0x30` (EN clear) — check which path that is (meta /
recovery / fastboot?) before relying on it.

**PMIC power-key long-press reset (MT6359P).**
- Observed today, **pre-kernel only**: three ~10 s power holds reset the
  board out of mtk DA mode. Preloader log: `#T#Long Pressed Reboot=39`,
  `[pmic_wdt_set] TOP_RST_MISC=0x221`.
- On MT6359P the live control is **`STRUP_CON12` (0xa12)**:
  `RG_PWRKEY_RST_EN` bit 13, `RG_PWRKEY_RST_TD` bits 15:14,
  `RG_PWRRST_TMR_DIS` bit 11 (`astro-kernel/.../mt6873/include/mach/upmu_hw.h:6840-6855`).
  The `TOP_RST_MISC` copies are `_RSV` fields, and vendor
  `MT6359_TOP_RST_MISC` is **0x14a** with 0x14c = `_SET` (`upmu_hw.h:154-156`).
- Mainline `mtk-pmic-keys` (`mt6359_regs`) does read-modify-write on
  `MT6359_TOP_RST_MISC` = **0x14c** — on this PMIC that is the SET alias of
  the reserved copy. Effect unknown → **`&mt6359keys` stays disabled** and
  the boot-image build refuses a DTB that enables it (port the Cosmo check).
- Stock Android flips long-press to shutdown at runtime (`restore pmic
  long_press_mode = SHUTDOWN`); irrelevant to our kernel as long as nothing
  in Linux writes these registers.
