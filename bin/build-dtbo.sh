#!/usr/bin/env bash
# Build out/dtbo.img (for the `dtbo_a` partition) from dtbo/astro-noop.dts,
# using the dtc from the kernel build (run bin/build-kernel.sh first), and
# check that it applies to the board DTB the way LK applies it.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
DTC="$ROOT/build/obj/scripts/dtc/dtc"
FDTOVERLAY="$ROOT/build/obj/scripts/dtc/fdtoverlay"
[[ -x "$DTC" ]] || { echo "no $DTC: run bin/build-kernel.sh first" >&2; exit 1; }
"$DTC" -q -I dts -O dtb -o "$OUT/astro-noop.dtbo" "$ROOT/dtbo/astro-noop.dts"
python3 -I "$ROOT/bin/mkdtboimg.py" "$OUT/astro-noop.dtbo" -o "$OUT/dtbo.img"
# Offline check: the overlay must apply to our DTB (needs __symbols__).
if [[ -x "$FDTOVERLAY" ]]; then
	"$FDTOVERLAY" -i "$OUT/mt6873-planet-astro.dtb" -o "$OUT/overlay-check.dtb" "$OUT/astro-noop.dtbo"
	"$DTC" -q -I dtb -O dts "$OUT/overlay-check.dtb" | grep -q 'planet,lk-dtbo = "astro-noop"' \
		&& echo "overlay applies to mt6873-planet-astro.dtb"
fi
sha256sum "$OUT/dtbo.img"
