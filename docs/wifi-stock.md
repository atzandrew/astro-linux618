# Wi-Fi (CONSYS) on the Astro: stock reference (W0) and port (W1), 2026-11-25

Research only, no image. Sources: Planet 4.14 tree (`astro-kernel`),
stock `vendor_a` (lpunpack from the P0 `super.bin` on Monolith, read with
`debugfs`, `~/Build/astro-backup/super-x/`), stock DT
(`backup/boot_a.dtb.0.dts`), P0 `nvdata.bin`.

## Mainline status: none

6.18 has nothing for this chip: no `mt6873`/`mt6853`/`soc2_0`/`connac2x2`/
`mt6635` in `drivers/net/wireless`, `drivers/bluetooth` or the bindings.
mt76 covers PCIe/USB/SDIO CONNAC2 parts (mt7921) and the Filogic WMAC
(mt7986), not this phone CONSYS + WMT/STP design. Port the vendor stack,
as on the Cosmo.

## Hardware and stack

- `CONFIG_MTK_COMBO_CHIP_CONSYS_6873`; vendor Makefile maps it to
  `MTK_COMBO_CHIP=CONNAC2X2`, `WIFI_IP_SET=3` (with 6779/6853), WMT in
  `kernel_modules/connectivity/common` (**not** conninfra; conninfra is
  6885/6893). A-die **MT6635** (FM chip list).
- Same architecture as the Cosmo: `common_main` WMT + STP over **BTIF**,
  platform file `common_main/platform/mt6873.c`. Wi-Fi is **gen4m**
  (not gen3), chip `connac2x2` (renamed `soc2_2x2` in later gen4m),
  HIF **AXI** (`mtk_axi_of_ids`, `hifAxiRemove`).
- Stock modules (vendor `/lib/modules`, not stripped, 4.14.186):
  `wmt_drv.ko`, `wmt_chrdev_wifi.ko`, `wlan_drv_gen4m.ko`, `bt_drv.ko`,
  `gps_drv.ko`, `fmradio_drv.ko`. Built from
  `/media/planet/NEWBIE/x900/alps_r0mp1/vendor/mediatek/kernel_modules/…`
  = MediaTek **alps-mp-r0.mp1** (Android 11). Planet did not publish
  `kernel_modules`.
- `wmt_drv` imports: `mtk_wcn_btif_*`, `mtk_emimpu_*`, `clk_buf_ctrl`,
  `connectivity_export_pmic_ldo_vcn13/vcn18/vcn33_1/vcn33_2_lp`,
  `connectivity_export_pmic_set_register_value`, regulator + pinctrl API.

## Stock DT

| Node | reg | IRQ (SPI) | Clocks |
|---|---|---|---|
| `consys@18002000` `mediatek,mt6873-consys` | 0x18002000, 0x10007000/0x100 (TOPRGU), 0x10001000 (INFRACFG_AO), 0x10006000 (SPM), 0x18007000, 0x180b1000, 0x180a3000, 0x180a5000/0x800, 0x180c1000, 0x18004000, 0x1024c000/0x40, 0x10003000 | 377, 79, 378 (level high) | `conn`, `ccif` |
| `wifi@18000000` `mediatek,wifi` | 0x18000000/0x100000 | 376 | `memory-region` = wifi-reserve-memory |
| `btif@1100c000` `mediatek,btif` | 0x1100c000/0x1000, TX DMA 0x10217d80/0x80, RX DMA 0x10217e00/0x80 | 158, 152, 153 | `btifc`, `apdmac` |
| `consys-reserve-memory` | dynamic, size 0x400000, align 0x1000000, alloc 0x40000000+0x80000000, no-map | | |

dtbo: `consys_default` pinctrl state is empty; GPS LNA pin pinmux 0xa200
(GPIO162) output-low.

## Firmware (stock `vendor/firmware`)

`WIFI_RAM_CODE_soc2_0_3b_1.bin` (769584), `soc2_0_patch_mcu_3b_1_hdr.bin`,
`soc2_0_ram_mcu_3b_1_hdr.bin`, `soc2_0_ram_wifi_3b_1_hdr.bin`,
`soc2_0_ram_bt_3b_1_hdr.bin`, `WMT_SOC.cfg` (`coex_wmt_ant_mode=1`,
`co_clock_flag=1` — differs from the Cosmo's 0, `bt_tssi_from_wifi=3`,
`bt_tssi_target=3815`), `BT_FW.cfg`, MT6635 FM files. Also unused
`soc3_0_*` files. Not redistributable; copy from the device's vendor at
install time like the Cosmo.

Stock load order (`init.wmt_drv.rc`, `init.wlan_drv.rc`): `wmt_drv` on
boot → `wmt_loader` + `wmt_launcher -p /vendor/firmware/` (userspace patch
search) → `vendor.connsys.driver.ready=yes` → `wmt_chrdev_wifi`,
`wlan_drv_gen4m`.

## NVRAM (device-unique, never in an image)

nvdata `/APCFG/APRDEB/WIFI` (2050 bytes), `WIFI_CUSTOM` (6), `BT_Addr`
(440). Note WIFI is 2050 bytes here vs 1026 on the Cosmo (gen4m layout).

## Public sources that make this easier

1. **Our Cosmo port** (`cosmo-linux618/kernel/delta/drivers/misc/
   mediatek-connectivity`): common_main WMT, BTIF, in-kernel `srh_patch`
   answer with `request_firmware`, EMI window, 6.18 API fixes. Reuse
   everything except the platform file and the Wi-Fi core.
2. **Zinwa Q25 Linux** (`github.com/wolf109909/zinwa-q25-linux`, MT6789,
   mainline **7.3.3**): Wi-Fi working through `wmt_drv` + gen4m +
   `wmt_chrdev_wifi` + BTIF + `connadp` — same WMT architecture. Its tree
   (5.10 vendor base) contains `common_main/platform/mt6873.c` +
   `mt6873_dbg.c` and gen4m `chips/soc2_2x2` (our chip), already fixed for
   7.3 APIs. No LICENSE on the repo; the vendor code is GPL / Dual BSD-GPL.
   Docs note genpd special-casing for the CONNSYS domain.
3. **R-era exact-version candidates** (match the stock 4.14 modules and
   firmware): MotorolaMobilityLLC `vendor-mediatek-kernel_modules-
   connectivity-wlan-core-gen4m` branches `android-11-release-*` (have
   `chips/connac2x2`) and `…-connectivity-common` (`android-11-release-rrq`
   has mt6853.c, not mt6873.c); many realme/Xiaomi R trees have
   `common_main/platform/mt6873.c` (GitHub code search).

## Open questions

- Newer gen4m (`soc2_2x2`, S/T era) vs the R-era firmware
  `WIFI_RAM_CODE_soc2_0_3b_1`: host/firmware command compatibility.
  Compare against the stock `wlan_drv_gen4m.ko` (symbols, format strings)
  before choosing a base.
- Regulators: MT6359P VCN13/VCN18/VCN33_1/VCN33_2 and the clock buffer
  (`clk_buf_ctrl`) — map to mainline mt6359-regulator; PMIC writes go
  through rule 5's pre-flash check.
- CONN power domain on mt8192 genpd (`MT8192_POWER_DOMAIN_CONN`) vs the
  stock SPM sequence in `mt6873.c`; Zinwa needed a genpd special case.
- EMI MPU (`mtk_emimpu_*`): no mainline equivalent; stub as on the Cosmo?

## W1 result (2026-11-25): stack builds on 6.18

Base: zinwa-q25-linux's vendor-5.10-on-7.3 tree, back to 6.18, plus the
Cosmo's in-kernel launcher. Tree: `kernel/delta/drivers/misc/
mediatek-connectivity/` (README.astro lists every change). Modules:
`btif_drv`, `connadp`, `wmt_drv`, `wmt_chrdev_wifi`, `wlan_drv_gen4m_6873`;
config `CONFIG_MTK_WCN_CONSYS=m`, `CONFIG_MTK_WCN_GEN4M=m` (modules only).

Base comparison (log format strings of the stock `wlan_drv_gen4m.ko`
found in each source): Motorola R gen4m 92.8 %, zinwa 89.5 %. zinwa vs R
host/firmware headers: RX descriptor changes additive only;
`nic_cmd_event.h` changes are mostly reserved bytes turned into version
fields, DFS radar reporting, tx-power-limit layout behind a compile option,
and the sched-scan SSID array 16 -> 10. zinwa chosen because it already
runs on mainline 7.3 with the same WMT stack; R tree is the fallback if the
firmware disagrees.

Firmware and load addresses (header byte 24 = count/seq, address =
0 + bytes 25..27, the stock launcher rule):

| File | Type | Address |
|---|---|---|
| `soc2_0_patch_mcu_3b_1_hdr.bin` | srh_patch (MCU ROM patch) | 0x0001c000 (gen4m SOC2_2X2_PATCH_START_ADDR) |
| `soc2_0_ram_mcu_3b_1_hdr.bin` | ROM patch WMT | 0xf0000000 |
| `soc2_0_ram_wifi_3b_1_hdr.bin` | ROM patch Wi-Fi | 0xf01d0000 (plat Wi-Fi EMI offset 0x1D0000) |
| `soc2_0_ram_bt_3b_1_hdr.bin` | ROM patch BT | 0xf0110000 |
| `WIFI_RAM_CODE_soc2_0_3b_1.bin` | gen4m RAM code | `%s_%u%s_%u.bin`, IP set 3, flavor b |

zinwa hard-coded its MT6789 names and addresses (Wi-Fi 0x2a, BT 0x17) in
`wmt_ctrl.c`; replaced by `wcn_launcher.c` reading the headers.

PMIC writes (rule 5 input): `mt6873.c` uses the MT6359 MFD regmap
(`pmic` phandle) at 0x188e/0x18ac/0x18ae/0x18b4 (VS2), 0x1be2/0x1bea/0x1bf0
(VCN33_1), 0x1c08/0x1c10/0x1c16 (VCN33_2), 0x1c1c/0x1c24/0x1c2a (VCN13),
0x1c2e/0x1c36/0x1c3c (VCN18), 0x202e (VCN13 VOCAL): all equal to Planet's
MT6359P `registers.h`; nothing near STRUP_CON12 (0xa12). Plus regulator
API on `vcn18`, `vcn13`, `vcn33_1_bt`, `vcn33_1_wifi`, `vcn33_2_wifi`.

## W2 needs (DT + flash, pre-flash check required)

- Nodes: `btif@1100c000` (`mediatek,btif`, stock reg/IRQ, clocks
  `btifc`/`apdmac`), `consys@18002000` (`mediatek,mt6873-consys`, 12 stock
  reg windows, 3 IRQs, `power-domains = <&spm MT8192_POWER_DOMAIN_CONN>`
  (the ≥5.4 path uses pm_runtime), `ccif` clock, `pmic` phandle,
  `vcn*-supply`, `emi-addr`/`emi-size` (module: no RESERVEDMEM_OF_DECLARE),
  pinctrl), `wifi@18000000` (`mediatek,wifi`, IRQ 376, memory-region 6 MiB
  shared-dma-pool). Template: zinwa's `mt8781-zinwa-q25.dts`.
- Reserved memory: consys EMI 4 MiB aligned 16 MiB (stock dynamic) as a
  fixed no-map region we pick, and the Wi-Fi 6 MiB pool; LK adds its own
  mblock carve-outs, so pick addresses clear of them.
- **MT6359P regulators** (`CONFIG_REGULATOR_MT6359` is off today): the
  riskiest part. Regulator late cleanup could switch off rails we do not
  describe (VEMC = UFS VCC, display rails). Needs an audited plan: every
  MT6359P rail always-on at its LK voltage, or only the VCN LDOs
  described, plus a pre-flash check and both escapes re-observed.
- MT8192 genpd CONN domain vs stock `mt6873.c` SPM sequence; zinwa needed a
  genpd special case (domain not powered at attach).
- EMI MPU: stubbed; if the CONN MCU faults on its EMI window, implement
  the TF-A SMC (MTK_SIP_EMIMPU_CONTROL) as stock does.
