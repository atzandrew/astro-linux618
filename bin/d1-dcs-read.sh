#!/bin/sh
# d1-dcs-read.sh — display Stage 1 (docs/display-stock.md): read the SH8802B
# ID and power mode through the DSI path LK left programmed.
#
# Runs ON THE ASTRO as root (Debian: sudo sh d1-dcs-read.sh). Caller stops
# astro-console first and restarts it afterwards.
#
# Panel traffic: only LK's own read packets, byte for byte (expdb LK log):
#   CMDQ0 0x00013700  set maximum return packet size = 1 (short, type 0x37)
#   CMDQ1 0x000A0604  DCS read 0x0A (power mode)        , BTA
#         0x00DA1404  generic read 0xDA (ID1)            , BTA
#         0x00DB1404  generic read 0xDB (ID2)            , BTA
#         0x00DC1404  generic read 0xDC (ID3)            , BTA
# plus one black frame before and one after (the write_memory_start packet
# LK queues itself, CMDQ0 0x002C3909, via /bin/astro-disp).
# DSI host registers written: INTSTA (+0x0c, clear), CMDQ0/1 (+0x200/+0x204),
# CMDQ_SIZE (+0x60), DSI_START (+0x00), RACK (+0x84). All restored.
set -u
DSI=0x14010000
r() { busybox devmem $1 32; }
w() { busybox devmem $1 32 $2; }
hex() { printf '0x%08x' $1; }

fail() {
	echo "FAIL: $*"
	w $((DSI+0x200)) $CQ0; w $((DSI+0x204)) $CQ1; w $((DSI+0x60)) $CQS
	/bin/astro-disp black || /bin/astro-disp reset-hold
	exit 1
}

wait_idle() { # DSI_BUSY = INTSTA bit 31
	n=0
	while [ $(( $(r $((DSI+0x0c))) & 0x80000000 )) -ne 0 ]; do
		[ $n -ge 200 ] && return 1
		busybox usleep 1000; n=$((n+1))
	done
	return 0
}

[ "$(r $((DSI+0x14)))" = 0x00000000 ] || { echo "MODE_CTRL not command mode: stop"; exit 1; }
CQ0=$(r $((DSI+0x200))); CQ1=$(r $((DSI+0x204))); CQS=$(r $((DSI+0x60)))
echo "before: CMDQ0 $CQ0 CMDQ1 $CQ1 SIZE $CQS"
[ "$CQ0" = 0x002C3909 ] || { echo "CMDQ0 is not LK's frame packet: stop"; exit 1; }

/bin/astro-disp black || { /bin/astro-disp reset-hold; echo "black frame failed: stop"; exit 1; }

read_one() { # $1 = CMDQ1 read packet, $2 = name
	wait_idle || fail "DSI busy before $2"
	w $((DSI+0x0c)) 0
	w $((DSI+0x200)) 0x00013700
	w $((DSI+0x204)) $1
	w $((DSI+0x60)) 2
	w $((DSI+0x00)) 0
	w $((DSI+0x00)) 1
	n=0
	while [ $(( $(r $((DSI+0x0c))) & 1 )) -eq 0 ]; do   # LPRX_RD_RDY
		[ $n -ge 100 ] && fail "no read response for $2 (INTSTA $(r $((DSI+0x0c))))"
		busybox usleep 1000; n=$((n+1))
	done
	rx=$(r $((DSI+0x74)))
	w $((DSI+0x0c)) 0
	w $((DSI+0x84)) 1                                  # RACK
	wait_idle || fail "DSI busy after $2"
	echo "$2: RX_DATA0 $rx -> type $(hex $(( rx & 0xff ))) value $(hex $(( (rx >> 8) & 0xff ))) (${n} ms)"
}

read_one 0x000A0604 "DCS 0x0A"
read_one 0x00DA1404 "ID 0xDA"
read_one 0x00DB1404 "ID 0xDB"
read_one 0x00DC1404 "ID 0xDC"

w $((DSI+0x200)) $CQ0; w $((DSI+0x204)) $CQ1; w $((DSI+0x60)) $CQS
echo "after:  CMDQ0 $(r $((DSI+0x200))) CMDQ1 $(r $((DSI+0x204))) SIZE $(r $((DSI+0x60)))"
/bin/astro-disp black || { /bin/astro-disp reset-hold; echo "final black frame failed: reset held"; exit 1; }
echo "done"
