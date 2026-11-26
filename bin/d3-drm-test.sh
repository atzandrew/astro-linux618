#!/bin/sh
# d3-drm-test.sh — display Stage 3 (docs/display-stock.md): mediatek-drm takes
# over the SH8802B the way stock Android does at boot (no panel init), shows
# the console for LIT seconds at brightness 0x200, then switches the panel
# off with the stock off sequence (DPMS off -> 28, 50 ms, 10, 150 ms, reset).
#
# Runs ON THE ASTRO as root under Debian (kernel with the Stage 3 modules):
#   sudo PATH=/usr/libexec/astro-bb:$PATH sh d3-drm-test.sh [LIT]
# The panel stays off afterwards (allow_init=0); a reboot brings LK's
# console back.
set -u
LIT=${1:-20}
DSI=0x14010000
MUTEX=0x14001000
PHY=0x11e50000
r() { busybox devmem $1 32; }
w() { busybox devmem $1 32 $2; }
log() { echo "[d3 $(date +%T)] $*"; }

regs() {
	for a in $((DSI+0x14)) $((DSI+0x18)) $((DSI+0x1c)) $((DSI+0x60)) $((DSI+0x90)) \
		 $((DSI+0x110)) $((DSI+0x114)) $((DSI+0x118)) $((DSI+0x11c)) $((DSI+0x190)) \
		 $((DSI+0x200)) $((MUTEX+0x2c)) $((MUTEX+0x30)) $((PHY+0x0c)) $((PHY+0x2c)) \
		 $((PHY+0x30)) 0x10005110 0x10005120 0x100053a0 0x100053b0; do
		printf '  0x%08x = %s\n' $a $(r $a)
	done
}

# Path registers: only while the display clocks run (not after the off).
path_regs() {
	for a in 0x14000f04 0x14000f18 0x14000f1c 0x14000f2c 0x14000f3c 0x14000f40 \
		 0x14005024 0x1400502c 0x14006024 0x1400602c 0x14001020; do
		printf '  0x%08x = %s\n' $a $(r $a)
	done
}

# Last-resort off through whatever DSI state is live: the stock off
# sequence as DCS short writes (LK's own table: 28, 50 ms, 10, 150 ms),
# then GPIO42 low. Used only if the driver did not come up.
dcs_off() {
	for p in 0x00280500:50000 0x00100500:150000; do
		n=0
		while [ $(( $(r $((DSI+0x0c))) & 0x80000000 )) -ne 0 ]; do
			[ $n -ge 100 ] && return 1
			busybox usleep 1000; n=$((n+1))
		done
		w $((DSI+0x0c)) 0
		w $((DSI+0x200)) ${p%%:*}
		w $((DSI+0x60)) 1
		w $((DSI+0x00)) 0
		w $((DSI+0x00)) 1
		n=0
		while [ $(( $(r $((DSI+0x0c))) & 2 )) -eq 0 ]; do
			[ $n -ge 100 ] && return 1
			busybox usleep 1000; n=$((n+1))
		done
		busybox usleep ${p##*:}
	done
	w 0x10005110 $(( $(r 0x10005110) & ~(1<<10) ))
	return 0
}

fallback() {
	log "FALLBACK: $*"
	if dcs_off; then
		log "panel off (DCS 28/10, reset held)"
	elif /bin/astro-disp black; then
		log "DCS off failed; black frame sent (pixels off), reset NOT asserted"
	else
		/bin/astro-disp reset-hold
		log "DCS off and black frame failed: reset held (last resort)"
	fi
	exit 1
}

log "kernel $(uname -v)"
lsmod | grep -qE '^mediatek_drm' && { log "mediatek-drm already loaded: stop"; exit 1; }

log "stopping astro-console (its stop hook sends a black frame)"
systemctl stop astro-console
log "before (LK state):"; regs; path_regs

log "loading phy-mtk-mipi-dsi-drv, panel-shenghe-sh8802b, mediatek-drm"
/usr/bin/dmesg -C
modprobe phy-mtk-mipi-dsi-drv || fallback "phy module"
modprobe panel-shenghe-sh8802b || fallback "panel module"
modprobe mediatek-drm || fallback "mediatek-drm module"

n=0
until dmesg | grep -q 'sh8802b.*power mode'; do
	[ $n -ge 100 ] && { dmesg | tail -40; fallback "no panel enable within 10 s"; }
	busybox usleep 100000; n=$((n+1))
done
dmesg | grep -iE 'mediatek|mtk|dsi|sh8802b|drm|fb|panel|mipi' | tail -40
log "after takeover:"; regs; path_regs
log "console should be visible now at brightness $(cat /sys/class/backlight/*/brightness 2>/dev/null); lit for ${LIT} s"
sleep "$LIT"

fb=$(grep -l -i mediatek /sys/class/graphics/fb*/name 2>/dev/null | head -1)
[ -n "$fb" ] || fallback "no mediatek fbdev"
log "DPMS off via ${fb%/name}/blank"
echo 4 > "${fb%/name}/blank"
sleep 1
dmesg | tail -15
log "after off: GPIO42 $(r 0x10005110) bias $(r 0x10005120) PLL_CON1 $(r 0x11e50030)"
if [ $(( $(r 0x10005110) & (1<<10) )) -ne 0 ]; then
	fallback "GPIO42 still high after DPMS off"
fi
log "done: panel off (stock off sequence), reset held by the driver"
