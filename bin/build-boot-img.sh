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
CMDLINE="bootopt=64S3,32N2,64N2 log_buf_len=4M console=tty0 clk_ignore_unused pd_ignore_unused regulator_ignore_unused cpuidle.off=1 fbcon=font:TER16x32 consoleblank=0 loglevel=7 panic=10 oops=panic ramoops.mem_address=0x4d010000 ramoops.mem_size=0xe0000 ramoops.record_size=0x1000 ramoops.console_size=0x40000 ramoops.pmsg_size=0x10000 g_ether.dev_addr=42:00:15:21:01:01 g_ether.host_addr=42:00:15:21:01:00"

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
# this PMIC. Until that is understood nothing may reach the PMIC: refuse a
# DTB with an enabled pwrap, any mt6359 node, a keys node or a long-press
# property, and a kernel built with the pwrap or PMIC keys driver.
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
grep -q 'panel' <<<"$REAL_DSI" && refuse "LK overlay landed on the real DSI node"
grep -q 'status = "disabled"' <<<"$REAL_DSI" || refuse "real DSI node not disabled after the LK overlay"
grep -q 'lcm_rst_out' <<<"$(awk '/^\t\tpinctrl@10005000 \{/{f=1} f{print} f&&/^\t\t};$/{exit}' <<<"$OV")" \
	&& refuse "LK overlay landed on the real pinctrl node"
echo "LK overlay applies to the boot DTB and lands in /lk-sink only"
PWRAP_NODE="$(awk '/compatible = "mediatek,mt6873-pwrap"/{f=1} f{print} f&&/^\t*};$/{exit}' <<<"$DTS_TEXT")"
grep -q 'status = "disabled"' <<<"$PWRAP_NODE" || refuse "pwrap node not disabled"
grep -qE '"mediatek,mt6359[^"]*"' <<<"$DTS_TEXT" && refuse "mt6359 node in DTB"
grep -qE 'mediatek,mt63[0-9]+-keys' <<<"$DTS_TEXT" && refuse "PMIC keys node in DTB"
grep -q 'long-press-mode' <<<"$DTS_TEXT" && refuse "long-press-mode in DTB"
KCONF="$ROOT/build/obj/.config"
grep -qE '^CONFIG_(MTK_PMIC_WRAP|KEYBOARD_MTK_PMIC)=' "$KCONF" && refuse "pwrap/PMIC keys driver in kernel config"
# Panel rule (AGENTS.md rule 3): no display driver in this kernel.
grep -qE '^CONFIG_DRM_MEDIATEK=' "$KCONF" && refuse "DRM_MEDIATEK in kernel config (panel rule)"
# LK applies the dtbo overlay: the base DTB needs __symbols__.
grep -q '__symbols__' <<<"$DTS_TEXT" || refuse "DTB built without -@ (LK overlay would fail)"

RD="$(mktemp -d)"
trap 'rm -rf "$RD"' EXIT
mkdir -p "$RD"/{bin,dev,proc,sys,tmp}
cp "$BUSYBOX" "$RD/bin/busybox"
cp "$ROOT/initramfs/init" "$RD/init"
cp "$ROOT/initramfs/astro-disp" "$RD/bin/astro-disp"
chmod 755 "$RD/init" "$RD/bin/busybox" "$RD/bin/astro-disp"
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
