#!/usr/bin/env bash
# Pack out/boot.img (for the `boot_a` partition): out/Image.gz +
# out/mt6873-planet-astro.dtb (bin/build-kernel.sh) + a busybox initramfs
# from initramfs/ + the boot cmdline below, as an Android boot header v2
# image laid out like stock (bin/mkbootimg.py).
#
#   bin/build-boot-img.sh
#   EXTRA_CMDLINE=astro.wdtest=1 OUTNAME=boot-wdtest.img bin/build-boot-img.sh
#
# BUSYBOX=/path/to/static/busybox overrides the host's /usr/bin/busybox
# (must be a static aarch64 binary).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
BUSYBOX="${BUSYBOX:-/usr/bin/busybox}"
DTB="$OUT/mt6873-planet-astro.dtb"
DTC="$ROOT/build/obj/scripts/dtc/dtc"
# boot_a is 0x2800000 bytes (GPT, docs/p0-findings.md). The image is padded
# to the full partition (by the AVB footer, below), so no stale stock data
# is left behind it.
BOOT_PART_SIZE=$((0x2800000))

# Header cmdline. LK puts its own arguments around it:
#  - bootopt= is parsed by LK itself and must stay (Gemini lesson; stock
#    Astro value).
#  - console=tty0 again so the framebuffer is the preferred console.
#  - *_ignore_unused: keep LK's display clocks, power and rails on.
#  - cma=256M: mediatek-drm runs without the IOMMU (display Stage 3), so
#    every buffer is physically contiguous from CMA (default 32 MiB: ~3
#    framebuffers of 1080x2340).
#  - fbcon=rotate:1: the panel is portrait (1080x2340); with the slider
#    open the console is upright at rotate 1 (user, 2026-11-25) and fills
#    146x33 with TER16x32.
#  - cpuidle.off=1: mainline MT8192 idle states are unproven on the vendor
#    ATF; WFI only until a CPU idle test.
#  - panic=10 + oops=panic: an oops becomes a panic. PSCI reboot is not
#    trusted (vendor ATF); the hardware watchdog, fed only while healthy,
#    is what resets the board (AGENTS.md rule 5).
#  - ramoops.*: the vendor pstore region LK reserves (mblock "pstore",
#    0x4d010000 +0xe0000, map:0), Cosmo layout. Whether it survives a
#    watchdog reset (LK sets ddr_rsv = yes) is still to be tested.
#  - g_ether.*: fixed, locally administered MACs for the USB bring-up
#    network (init: Astro 10.15.21.1, host .2 by DHCP).
CMDLINE="bootopt=64S3,32N2,64N2 log_buf_len=4M console=tty0 clk_ignore_unused pd_ignore_unused regulator_ignore_unused cpuidle.off=1 cma=256M fbcon=rotate:1 fbcon=font:TER16x32 consoleblank=0 loglevel=7 panic=10 oops=panic ramoops.mem_address=0x4d010000 ramoops.mem_size=0xe0000 ramoops.record_size=0x1000 ramoops.console_size=0x40000 ramoops.pmsg_size=0x10000 g_ether.dev_addr=42:00:15:21:01:01 g_ether.host_addr=42:00:15:21:01:00"

# EXTRA_CMDLINE is appended (astro.wdtest=1, astro.dispdump=1); OUTNAME
# names the image (default boot.img).
CMDLINE="$CMDLINE${EXTRA_CMDLINE:+ $EXTRA_CMDLINE}"
OUTNAME="${OUTNAME:-boot.img}"

file -L "$BUSYBOX" | grep -q "aarch64.*statically linked" \
	|| { echo "$BUSYBOX is not a static aarch64 binary" >&2; exit 1; }
[[ -f "$OUT/Image.gz" && -f "$DTB" ]] || { echo "run bin/build-kernel.sh first" >&2; exit 1; }

# AGENTS.md rule 5: never pack an image that can strand the device.
# On the MT6359P the power-key reset lives in STRUP_CON12 (0xa12); mainline
# mtk-pmic-keys does read-modify-write on 0x14c, a different register on
# this PMIC (docs/pmic-plan.md). Allowed shape (step 2, image B): pwrap
# enabled only with our delta (real INT_FLG/INT_CLR, no WDT_SRC write),
# one child "mediatek,mt6359" whose only child is "keys"
# (mediatek,mt6359-keys, only a "power" key, long-press mode 1 = stock,
# 8 s), the keys driver only with our MT6359P delta, and no other MT6359
# function driver in the kernel.
# Step 3 image A adds "adc" (mediatek,mt6359-auxadc, shunt 5 mOhm, nothing
# else) and the AUXADC driver, pinned by sha256 to the audited source
# (docs/pmic-plan.md step 3: reset 0xf90 under key 0xfb4, requests
# 0x1108/0x110a, IMP0 0x1208; no STRUP). Any change re-opens the audit.
AUXADC_SHA=1468d6538002322c80f5847d45e656a728d64036522787d892d524c495342675
# Wi-Fi W2 (docs/wifi-stock.md "W2 pre-flash check"): the MT6359 regulator
# driver (module only) with exactly the five CONSYS rails described, and
# SCPSYS power domains with the spm node reduced to CONN (KEEP_DEFAULT_OFF).
# Both sources pinned as audited (unmodified v6.18.58).
REG6359_SHA=86b9d129c5664aa280fdd7837c7c5bdad96b49096a764bb368b5e1bf97821841
PMDOM_SHA=c09a53aa35cf898ea8f8d05bf3a2676656a36819491496531dc7e15bfe28961a
PMDOM8192_SHA=776ce01e0eac0f24a9eb3257b7f13d55af0839410adac69417f6510a0dfe3e6b
# GPU G-S1: audited SPMI / MT6315 sources (unmodified v6.18.58).
MT6315_SHA=3c3cfcbf91795a7ecb08fe3f00c9c1ba69d987315f5ce1c6704f97fa733a611a
PMIF_SHA=8ddb83ad364c2d530f049e974c87f818abb22cac29cd20aa9b05131f22a1201d
# GPU G-S2: audited panfrost core-mask delta.
PANFROST_GPU_SHA=861feb65c26bfefd4ad196e1e8ad4854ae342cd453bb58e401ae658368a50e20
# Display Stage 3: audited SH8802B panel driver (stock init/off/brightness only).
PANEL_SHA=b75532375556ced0e99dc121d7908c234fbec9454be2ea7f14d9991946556980
refuse() { echo "REFUSING ($1): AGENTS.md rule 5" >&2; exit 1; }

# LK applies dtbo_a to this DTB too (display test 1): dtbo/astro-lk.dts
# targets odm, pio, mtkfb, dispsys_config, dsi0, gpio. pio and dsi0 are
# mainline labels of the real pinctrl and DSI nodes, so their __symbols__
# entries are pointed at the inert /lk-sink stand-ins instead (Linux does
# not read __symbols__; only overlay appliers do).
BOOT_DTB="$OUT/mt6873-planet-astro.boot.dtb"
"$DTC" -q -I dtb -O dts "$DTB" \
	| sed -e 's|^\t\tpio = "/soc/pinctrl@10005000";|\t\tpio = "/lk-sink/pio";|' \
	      -e 's|^\t\tdsi0 = "/soc/dsi@14010000";|\t\tdsi0 = "/lk-sink/dsi0";|' \
	| "$DTC" -q -I dts -O dtb -o "$BOOT_DTB"
DTS_TEXT="$("$DTC" -q -I dtb -O dts "$BOOT_DTB")"
SYMS="$(awk '/__symbols__ \{/,/^\t\};/' <<<"$DTS_TEXT")"
for s in odm pio mtkfb dispsys_config dsi0 gpio; do
	grep -qE "^\s+$s = \"/lk-sink/" <<<"$SYMS" || refuse "__symbols__ $s does not point into /lk-sink"
done
# The LK overlay must apply to the boot DTB and land only in /lk-sink.
LKDTBO="$OUT/astro-lk.dtbo"
[[ -f "$LKDTBO" ]] || { echo "run bin/build-dtbo.sh first" >&2; exit 1; }
"$ROOT/build/obj/scripts/dtc/fdtoverlay" -i "$BOOT_DTB" -o "$OUT/boot-overlay-check.dtb" "$LKDTBO" \
	|| refuse "dtbo/astro-lk overlay does not apply to the boot DTB (LK would stop)"
OV="$("$DTC" -q -I dtb -O dts "$OUT/boot-overlay-check.dtb")"
REAL_DSI="$(awk '/^\t\tdsi@14010000 \{/{f=1} f{print} f&&/^\t\t};$/{exit}' <<<"$OV")"
BOOT_DSI="$(awk '/^\t\tdsi@14010000 \{/{f=1} f{print} f&&/^\t\t};$/{exit}' <<<"$DTS_TEXT")"
[[ "$REAL_DSI" == "$BOOT_DSI" ]] || refuse "LK overlay changed the real DSI node"
grep -qE 'panel[123]@0|sh8802b,vdo|vt,' <<<"$REAL_DSI" && refuse "stock panel nodes in the real DSI node"
# Display Stage 3: the real DSI node is either disabled, or enabled with
# exactly one child, our SH8802B panel (docs/display-stock.md).
if ! grep -q 'status = "disabled"' <<<"$REAL_DSI"; then
	[[ "$(grep -cP '^\t\t\t[a-z][^ ]* \{$' <<<"$REAL_DSI")" == 2 ]] \
		&& grep -qP '^\t\t\tpanel@0 \{$' <<<"$REAL_DSI" \
		&& grep -q 'compatible = "shenghe,sh8802b";' <<<"$REAL_DSI" \
		|| refuse "real DSI enabled with something other than panel@0 shenghe,sh8802b"
fi
grep -q 'lcm_rst_out' <<<"$(awk '/^\t\tpinctrl@10005000 \{/{f=1} f{print} f&&/^\t\t};$/{exit}' <<<"$OV")" \
	&& refuse "LK overlay landed on the real pinctrl node"
echo "LK overlay applies to the boot DTB and lands in /lk-sink only"
KCONF="$ROOT/build/obj/.config"
# The pwrap node (tabs: soc child at depth 2, its children at depth 3+).
PWRAP_NODE="$(awk '/^\t\tpwrap@10026000 \{/{f=1} f{print} f&&/^\t\t};$/{exit}' <<<"$DTS_TEXT")"
[[ -n "$PWRAP_NODE" ]] || refuse "pwrap node not found"
if grep -q 'status = "disabled"' <<<"$PWRAP_NODE"; then
	grep -qE '"mediatek,mt6359[^"]*"' <<<"$DTS_TEXT" && refuse "mt6359 node with pwrap disabled"
	grep -qE '^CONFIG_MTK_PMIC_WRAP=' "$KCONF" && refuse "pwrap driver without a pwrap node"
else
	PW_SRC="$ROOT/build/src/drivers/soc/mediatek/mtk-pmic-wrap.c"
	grep -q 'wdt_src = 0: the SoC has no WDT_SRC_EN register' "$PW_SRC" \
		&& grep -qE '\[PWRAP_INT_FLG\] =\s+0x450' "$PW_SRC" \
		|| refuse "pwrap enabled without the mt6873 pwrap delta"
	# Exactly one child, the PMIC, and nothing below it.
	[[ "$(grep -cP '^\t\t\t[a-z][^ ]* \{$' <<<"$PWRAP_NODE")" == 1 ]] || refuse "pwrap has other than one child"
	grep -qP '^\t\t\tpmic \{$' <<<"$PWRAP_NODE" || refuse "pwrap child is not pmic"
	grep -q 'compatible = "mediatek,mt6359";' <<<"$PWRAP_NODE" || refuse "pwrap child is not mediatek,mt6359"
	# PMIC children: none, "keys", "adc", or both.
	KIDS="$(grep -P '^\t\t\t\t[a-z][^ ]* \{$' <<<"$PWRAP_NODE" | tr -d '\t' | sort | tr '\n' ' ')"
	case "$KIDS" in
	""|"keys { "|"adc { "|"adc { keys { "|"adc { keys { regulators { "|"keys { regulators { "|"regulators { "|"adc { regulators { ") ;;
	*) refuse "mt6359 node has children other than adc/keys/regulators: $KIDS" ;;
	esac
	if [[ "$KIDS" == *"regulators {"* ]]; then
		REGS_NODE="$(awk '/^\t\t\t\tregulators \{$/{f=1} f{print} f&&/^\t\t\t\t};$/{exit}' <<<"$PWRAP_NODE")"
		grep -q 'compatible = "mediatek,mt6359-regulator";' <<<"$REGS_NODE" || refuse "regulators is not mediatek,mt6359-regulator"
		[[ "$(grep -P '^\t\t\t\t\t[a-z][^ ]* \{$' <<<"$REGS_NODE" | tr -d '\t' | sort | tr '\n' ' ')" \
			== "ldo_vcn13 { ldo_vcn18 { ldo_vcn33_1_bt { ldo_vcn33_1_wifi { ldo_vcn33_2_wifi { " ]] \
			|| refuse "regulators node describes rails other than the five CONSYS LDOs"
		grep -qE 'regulator-(always-on|boot-on)|regulator-initial|regulator-pull-down|regulator-allowed-modes|regulator-over-current|regulator-active-discharge|regulator-ramp' <<<"$REGS_NODE" \
			&& refuse "regulators node sets something beyond name/min/max"
		# every property line in a rail: name, min, max, phandle - nothing else
		[[ -z "$(grep -P '^\t\t\t\t\t\t' <<<"$REGS_NODE" | grep -vE 'regulator-name = |regulator-(min|max)-microvolt = |phandle = ')" ]] \
			|| refuse "a CONSYS rail node has properties beyond name/min/max"
		chk_rail() { # node name min max
			local n
			n="$(awk -v r="$1" '$0 ~ "^\t\t\t\t\t"r" \\{$"{f=1} f{print} f&&/^\t\t\t\t\t};$/{exit}' <<<"$REGS_NODE")"
			grep -q "regulator-min-microvolt = <$2>;" <<<"$n" && grep -q "regulator-max-microvolt = <$3>;" <<<"$n" \
				|| refuse "$1 voltage range is not the audited one"
		}
		chk_rail ldo_vcn18 0x1b7740 0x1b7740        # 1.8 V (fixed LDO)
		chk_rail ldo_vcn13 0x13d620 0x13d620        # 1.3 V = LK's VOSEL 4
		chk_rail ldo_vcn33_1_bt 0x325aa0 0x3567e0   # 3.3-3.5 V (LK: 3.5)
		chk_rail ldo_vcn33_1_wifi 0x325aa0 0x3567e0
		chk_rail ldo_vcn33_2_wifi 0x325aa0 0x3567e0
	fi
	if [[ "$KIDS" == *"adc {"* ]]; then
		ADC_NODE="$(awk '/^\t\t\t\tadc \{$/{f=1} f{print} f&&/^\t\t\t\t};$/{exit}' <<<"$PWRAP_NODE")"
		[[ "$(grep -cP '^\t\t\t\t\t' <<<"$ADC_NODE")" == 4 ]] \
			&& grep -q 'compatible = "mediatek,mt6359-auxadc";' <<<"$ADC_NODE" \
			&& grep -q '#io-channel-cells = <0x01>;' <<<"$ADC_NODE" \
			&& grep -q 'shunt-resistor-micro-ohms = <0x1388>;' <<<"$ADC_NODE" \
			&& grep -qP '^\t\t\t\t\tphandle = ' <<<"$ADC_NODE" \
			|| refuse "adc node is not exactly the step 3A auxadc"
	fi
	if [[ "$KIDS" == *"keys {"* ]]; then
		KEYS_NODE="$(awk '/^\t\t\t\tkeys \{$/{f=1} f{print} f&&/^\t\t\t\t};$/{exit}' <<<"$PWRAP_NODE")"
		grep -q 'compatible = "mediatek,mt6359-keys";' <<<"$KEYS_NODE" || refuse "keys is not mediatek,mt6359-keys"
		[[ "$(grep -P '^\t\t\t\t\t[a-z][^ ]* \{$' <<<"$KEYS_NODE" | tr -d '\t')" == "power {" ]] \
			|| refuse "keys node has keys other than power"
		grep -q 'mediatek,long-press-mode = <0x01>;' <<<"$KEYS_NODE" || refuse "long-press-mode is not 1 (stock one-key reset)"
		grep -q 'power-off-time-sec = <0x08>;' <<<"$KEYS_NODE" || refuse "power-off-time-sec is not 8 (stock)"
	fi
fi
if grep -qE 'mediatek,mt63[0-9]+-keys|long-press-mode' <<<"$DTS_TEXT"; then
	[[ -n "${KEYS_NODE:-}" ]] || refuse "PMIC keys/long-press outside the checked keys node"
	[[ "$(grep -cE 'mediatek,mt63[0-9]+-keys' <<<"$DTS_TEXT")" == 1 ]] || refuse "more than one PMIC keys node"
fi
if grep -qE '^CONFIG_KEYBOARD_MTK_PMIC=' "$KCONF"; then
	KEYS_SRC="$ROOT/build/src/drivers/input/keyboard/mtk-pmic-keys.c"
	grep -q 'define MT6359P_STRUP_CON12		0xa12' "$KEYS_SRC" \
		&& grep -q 'mtk_pmic_regs = &mt6359p_regs;' "$KEYS_SRC" \
		|| refuse "PMIC keys driver without the MT6359P delta"
fi
if grep -qE '^CONFIG_MEDIATEK_MT6359_AUXADC=' "$KCONF"; then
	[[ -n "${ADC_NODE:-}" ]] || refuse "AUXADC driver without the checked adc node"
	[[ "$(sha256sum < "$ROOT/build/src/drivers/iio/adc/mt6359-auxadc.c" | cut -d' ' -f1)" == "$AUXADC_SHA" ]] \
		|| refuse "mt6359-auxadc.c is not the audited step 3A source"
fi
grep -qE 'mediatek,mt63[0-9]+-auxadc' <<<"$DTS_TEXT" && [[ -z "${ADC_NODE:-}" ]] \
	&& refuse "PMIC auxadc outside the checked adc node"
if grep -qE '^CONFIG_REGULATOR_MT6359=' "$KCONF"; then
	grep -qE '^CONFIG_REGULATOR_MT6359=m$' "$KCONF" || refuse "REGULATOR_MT6359 built in (module only)"
	[[ -n "${REGS_NODE:-}" ]] || refuse "MT6359 regulator driver without the checked regulators node"
	[[ "$(sha256sum < "$ROOT/build/src/drivers/regulator/mt6359-regulator.c" | cut -d' ' -f1)" == "$REG6359_SHA" ]] \
		|| refuse "mt6359-regulator.c is not the audited W2 source"
fi
grep -q 'compatible = "mediatek,mt6359-regulator";' <<<"$DTS_TEXT" && [[ -z "${REGS_NODE:-}" ]] \
	&& refuse "MT6359 regulators outside the checked node"
# SCPSYS power domains (Wi-Fi W2): CONN (KEEP_DEFAULT_OFF). Display Stage 2
# (docs/display-stock.md): + DISP (MT8192_POWER_DOMAIN_DISP = 9), already
# on from LK, with no child domain (each child would be powered on at
# probe). Nothing else may be listed.
SPM_NODE="$(awk '/^\t\t\tpower-controller \{$/{f=1} f{print} f&&/^\t\t\t};$/{exit}' <<<"$DTS_TEXT")"
if grep -qE '^CONFIG_MTK_SCPSYS_PM_DOMAINS=y' "$KCONF"; then
	[[ -n "$SPM_NODE" ]] || refuse "SCPSYS power domains on but no spm node"
	# GPU G-S2 (docs/gpu-stock.md): + MFG0 (2) with MFG1 (3) and MFG2-6
	# (4-8) under it, no domain-supply (rails stay as LK left them).
	TOP="$(grep -oP '^\t\t\t\t\K[a-z][^ ]*(?= \{$)' <<<"$SPM_NODE" | sort | tr '\n' ' ')"
	[[ "$TOP" == "power-domain@1 power-domain@2 power-domain@9 " ]] \
		|| refuse "spm top-level domains are not CONN (1), MFG0 (2), DISP (9): $TOP"
	ALL="$(grep -oP 'power-domain@\K[0-9a-f]+(?= \{$)' <<<"$SPM_NODE" | sort | tr '\n' ' ')"
	[[ "$ALL" == "1 2 3 4 5 6 7 8 9 " ]] || refuse "spm domains are not exactly CONN, MFG0-6, DISP: $ALL"
	DISP_NODE="$(awk '/^\t\t\t\tpower-domain@9 \{$/{f=1} f{print} f&&/^\t\t\t\t};$/{exit}' <<<"$SPM_NODE")"
	grep -q 'power-domain@[0-9a-f]* {' <<<"$(tail -n +2 <<<"$DISP_NODE")" && refuse "DISP has child domains"
	grep -q 'domain-supply' <<<"$SPM_NODE" && refuse "a power domain has a domain-supply (rail control)"
	[[ "$(sha256sum < "$ROOT/build/src/drivers/pmdomain/mediatek/mtk-pm-domains.c" | cut -d' ' -f1)" == "$PMDOM_SHA" ]] \
		&& [[ "$(sha256sum < "$ROOT/build/src/drivers/pmdomain/mediatek/mt8192-pm-domains.h" | cut -d' ' -f1)" == "$PMDOM8192_SHA" ]] \
		|| refuse "mtk-pm-domains / mt8192 table is not the audited W2 source"
	awk '/\[MT8192_POWER_DOMAIN_CONN\]/{f=1;next} f&&/\[MT8192_POWER_DOMAIN_/{exit} f' \
		"$ROOT/build/src/drivers/pmdomain/mediatek/mt8192-pm-domains.h" \
		| grep -q 'MTK_SCPD_KEEP_DEFAULT_OFF' || refuse "CONN domain is not KEEP_DEFAULT_OFF"
fi
for c in RTC_DRV_MT6397 SND_SOC_MT6359 \
	 SND_SOC_MT6359_ACCDET; do
	grep -qE "^CONFIG_$c=" "$KCONF" && refuse "CONFIG_$c set (MT6359 function driver)"
done
# GPU G-S1 (docs/gpu-stock.md): SPMI + MT6315 for reading only. The MT6315s
# carry the CPU and GPU rails: sources pinned (unmodified mainline, audited:
# probe only reads, shutdown = the stock driver's power-off-sequence bit),
# and every MT6315 node must be bare (compatible + reg): no regulator
# constraint the core could apply.
SPMI_NODE="$(awk '/^\t\tspmi@10027000 \{$/{f=1} f{print} f&&/^\t\t};$/{exit}' <<<"$DTS_TEXT")"
if grep -qE '^CONFIG_(SPMI_MTK_PMIF|REGULATOR_MT6315)=' "$KCONF"; then
	[[ "$(sha256sum < "$ROOT/build/src/drivers/regulator/mt6315-regulator.c" | cut -d' ' -f1)" == "$MT6315_SHA" ]] \
		&& [[ "$(sha256sum < "$ROOT/build/src/drivers/spmi/spmi-mtk-pmif.c" | cut -d' ' -f1)" == "$PMIF_SHA" ]] \
		|| refuse "mt6315-regulator / spmi-mtk-pmif is not the audited source"
	[[ -n "$SPMI_NODE" ]] || refuse "SPMI driver without the spmi node"
	grep -q 'compatible = "mediatek,mt6873-spmi";' <<<"$SPMI_NODE" || refuse "spmi node is not mediatek,mt6873-spmi"
	KIDS="$(grep -oP '^\t\t\t\K[a-z][^ ]*(?= \{$)' <<<"$SPMI_NODE" | sort | tr '\n' ' ')"
	[[ "$KIDS" == "pmic@3 pmic@6 pmic@7 " ]] || refuse "spmi children are not exactly pmic@3/6/7: $KIDS"
	grep -qP '^\t\t\t\t[a-z#][^=]* \{$' <<<"$SPMI_NODE" && refuse "an MT6315 node has child nodes (regulators?)"
	grep -qE 'regulator-|always-on|boot-on' <<<"$SPMI_NODE" && refuse "regulator constraints under spmi"
	[[ "$(grep -c 'compatible = "mediatek,mt6315-regulator";' <<<"$SPMI_NODE")" == 3 ]] || refuse "MT6315 nodes are not the 3 regulator PMICs"
fi
# GPU G-S2: panfrost only as a module, pinned core-mask delta, and a GPU
# node that cannot touch a rail or a rate (no OPP table, no mali-supply),
# with the stock MT6873 4-core mask.
GPU_NODE="$(awk '/^\t\tgpu@13000000 \{$/{f=1} f{print} f&&/^\t\t};$/{exit}' <<<"$DTS_TEXT")"
grep -qE '^CONFIG_DRM_PANFROST=y' "$KCONF" && refuse "DRM_PANFROST built in (module only)"
if grep -qE '^CONFIG_DRM_PANFROST=m' "$KCONF"; then
	[[ "$(sha256sum < "$ROOT/build/src/drivers/gpu/drm/panfrost/panfrost_gpu.c" | cut -d' ' -f1)" == "$PANFROST_GPU_SHA" ]] \
		|| refuse "panfrost_gpu.c is not the audited core-mask delta"
	grep -qE 'operating-points|mali-supply|sram-supply' <<<"$GPU_NODE" && refuse "GPU node can change rails or rates"
	grep -q 'mediatek,shader-core-mask = <0x00 0x50005>;' <<<"$GPU_NODE" || refuse "GPU node without the stock 4-core mask"
fi
# Panel rule (AGENTS.md rule 3), Display Stage 3: mediatek-drm and the
# SH8802B panel only as modules (blacklisted on the rootfs), and the panel
# driver pinned to the audited source (stock tables only; any change
# re-opens the check in docs/display-stock.md).
grep -qE '^CONFIG_DRM_MEDIATEK=y' "$KCONF" && refuse "DRM_MEDIATEK built in (module only)"
if grep -qE '^CONFIG_DRM_MEDIATEK=m' "$KCONF"; then
	grep -qE '^CONFIG_DRM_PANEL_SHENGHE_SH8802B=m$' "$KCONF" || refuse "SH8802B panel not a module"
	[[ "$(sha256sum < "$ROOT/build/src/drivers/gpu/drm/panel/panel-shenghe-sh8802b.c" | cut -d' ' -f1)" == "$PANEL_SHA" ]] \
		|| refuse "panel-shenghe-sh8802b.c is not the audited source"
fi
# LK applies the dtbo overlay: the base DTB needs __symbols__.
grep -q '__symbols__' <<<"$DTS_TEXT" || refuse "DTB built without -@ (LK overlay would fail)"

RD="$(mktemp -d)"
trap 'rm -rf "$RD"' EXIT
mkdir -p "$RD"/{bin,dev,proc,sys,tmp}
cp "$BUSYBOX" "$RD/bin/busybox"
cp "$ROOT/initramfs/init" "$RD/init"
cp "$ROOT/initramfs/astro-disp" "$RD/bin/astro-disp"
cp "$ROOT/initramfs/astro-console" "$RD/bin/astro-console"
chmod 755 "$RD/init" "$RD/bin/busybox" "$RD/bin/astro-disp" "$RD/bin/astro-console"
( cd "$RD" && find . | LC_ALL=C sort | cpio -o -H newc --owner=0:0 --quiet ) \
	| gzip -9n > "$OUT/initramfs.cpio.gz"

python3 -I "$ROOT/bin/mkbootimg.py" --kernel "$OUT/Image.gz" \
	--ramdisk "$OUT/initramfs.cpio.gz" --dtb "$BOOT_DTB" --cmdline "$CMDLINE" \
	-o "$OUT/$OUTNAME"
SIZE=$(stat -c %s "$OUT/$OUTNAME")
(( SIZE <= BOOT_PART_SIZE )) || { echo "$OUTNAME is $SIZE bytes, boot_a holds $BOOT_PART_SIZE" >&2; exit 1; }

# AVB hash footer (try1 finding, docs/session-log.md 2026-11-25): on this
# LK, AVB is what loads boot_a. Without a footer libavb stops at "invalid
# vbmeta header", never loads the image, and LK asserts at
# boot_info.c:554 (g_boot_info.hdr_loaded). vbmeta_a chains "boot" to
# Planet's key; unlocked (orange) LK tolerates a rejected key or a wrong
# digest but not missing metadata. So: a well-formed footer as stock
# (SHA256_RSA2048, partition "boot", rollback index 0), signed with a
# local dev key. The footer also pads the image to the full partition.
AVBKEY="$ROOT/build/avb/astro-dev-rsa2048.pem"
if [[ ! -f "$AVBKEY" ]]; then
	mkdir -p "$(dirname "$AVBKEY")"
	openssl genrsa -out "$AVBKEY" 2048 2>/dev/null
fi
avbtool add_hash_footer --image "$OUT/$OUTNAME" --partition_name boot \
	--partition_size "$BOOT_PART_SIZE" --algorithm SHA256_RSA2048 \
	--key "$AVBKEY" --rollback_index 0
avbtool info_image --image "$OUT/$OUTNAME" | grep -qE "Partition Name: +boot" \
	|| { echo "AVB footer missing after add_hash_footer" >&2; exit 1; }

echo "busybox: $("$BUSYBOX" | head -1)"
echo "cmdline: $CMDLINE"
echo "$OUTNAME: $SIZE bytes used, AVB footer, padded to $(stat -c %s "$OUT/$OUTNAME")"
sha256sum "$OUT/initramfs.cpio.gz" "$OUT/$OUTNAME"
