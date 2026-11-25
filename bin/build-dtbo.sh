#!/usr/bin/env bash
# Build out/dtbo.img (for the `dtbo_a` partition) from dtbo/astro-lk.dts
# (LK board-config overlay; NOOP=1: dtbo/astro-noop.dts instead), using
# the dtc from the kernel build (run bin/build-kernel.sh first).
#
# LK applies dtbo_a twice per boot: onto its own copy of the stock base
# DTB and onto our kernel DTB (docs/session-log.md, display test 1). The
# checks below simulate both: the stock base DTB from the P0 dump
# (backup/boot_a.dtb.0.dtb, gitignored) and our boot DTB
# (bin/build-boot-img.sh repeats that check on the exact DTB it packs).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
DTC="$ROOT/build/obj/scripts/dtc/dtc"
FDTOVERLAY="$ROOT/build/obj/scripts/dtc/fdtoverlay"
[[ -x "$DTC" && -x "$FDTOVERLAY" ]] || { echo "no dtc/fdtoverlay: run bin/build-kernel.sh first" >&2; exit 1; }
NAME=astro-lk; [[ "${NOOP:-}" == 1 ]] && NAME=astro-noop
"$DTC" -q -@ -I dts -O dtb -o "$OUT/astro-lk.dtbo" "$ROOT/dtbo/astro-lk.dts"
"$DTC" -q -I dts -O dtb -o "$OUT/astro-noop.dtbo" "$ROOT/dtbo/astro-noop.dts"
STOCK="$ROOT/backup/boot_a.dtb.0.dtb"
if [[ "$NAME" == astro-lk ]]; then
	if [[ -f "$STOCK" ]]; then
		"$FDTOVERLAY" -i "$STOCK" -o "$OUT/lk-main-check.dtb" "$OUT/astro-lk.dtbo" \
			|| { echo "astro-lk does not apply to the stock base DTB (LK's own pass)" >&2; exit 1; }
		CHECK="$("$DTC" -q -I dtb -O dts "$OUT/lk-main-check.dtb")"
		for want in 'gpio_init_default' '"mediatek,lcd-backlight"' 'lcm_rst_out0_gpio' '"sh8802b,vdo"'; do
			grep -qF "$want" <<<"$CHECK" || { echo "LK pass check: $want missing" >&2; exit 1; }
		done
		echo "astro-lk applies to the stock base DTB (LK's own pass)"
	else
		echo "WARNING: $STOCK missing: LK-side overlay check skipped" >&2
	fi
fi
python3 -I "$ROOT/bin/mkdtboimg.py" "$OUT/$NAME.dtbo" -o "$OUT/dtbo.img"
echo "dtbo.img = $NAME"
sha256sum "$OUT/dtbo.img"
