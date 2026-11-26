#!/bin/sh
# CPU DVFS checks on the Astro (docs/cpufreq-stock.md, C1 onwards). Run as root.
#   c-test.sh hw            PLL/mux readback of the three CPU clocks + rails
#   c-test.sh steps         every OPP of both policies (userspace), readback
#   c-test.sh stress SECS [min]  8 md5 workers at max (or min) OPP, temps
# Readback is register-level (busybox devmem, read only): ARMPLL CON1 pcw
# and post divider, MCUSYS mux (bits 10:9 must be 1 = ARMPLL) and CKDIV1
# (bits 21:17 must be 8 = /1). Fail lines start with FAIL.
set -u
CF=/sys/devices/system/cpu/cpufreq
DM="busybox devmem"
fail=0

# kHz for LL / BL / CCI from the registers; "?" if the mux is not on ARMPLL
hw_khz() {
	case $1 in
	LL) con1=0x1000c20c; mux=0x0c53a2a0;;
	BL) con1=0x1000c21c; mux=0x0c53a2a4;;
	CCI) con1=0x1000c25c; mux=0x0c53a2e0;;
	esac
	c=$($DM $con1 32); m=$($DM $mux 32)
	sel=$(( (m >> 9) & 3 )); ck=$(( (m >> 17) & 31 ))
	if [ $sel != 1 ] || [ $ck != 8 ]; then echo "?mux=$m"; return; fi
	pcw=$(( c & 0x3fffff )); pd=$(( (c >> 24) & 7 ))
	# kHz = pcw * 26000 / 2^14 / 2^pd
	echo $(( pcw * 26000 / 16384 / (1 << pd) ))
}

reg() { for r in /sys/class/regulator/regulator.*; do [ "$(cat $r/name)" = $1 ] && echo $r; done; }
volts() {
	for n in Vproc_big Vproc_little VSRAM_PROC1 VSRAM_PROC2; do
		r=$(reg $n); [ -n "$r" ] && printf "%s %s  " $n $(cat $r/microvolts)
	done
	echo
}

hw() {
	echo "LL $(hw_khz LL) BL $(hw_khz BL) CCI $(hw_khz CCI) kHz"
	volts
}

# C1: rails pinned; fail if they moved
V_BIG0=600000; V_LIT0=718750
check_pins() {
	b=$(cat $(reg Vproc_big)/microvolts); l=$(cat $(reg Vproc_little)/microvolts)
	[ $b = $V_BIG0 ] || echo "FAIL Vproc_big $b want $V_BIG0"
	[ $l = $V_LIT0 ] || echo "FAIL Vproc_little $l want $V_LIT0"
}

steps() {
	cci0=$(hw_khz CCI)
	for p in 0 4; do
		echo userspace > $CF/policy$p/scaling_governor || { echo "FAIL governor"; return 1; }
	done
	for p in 0 4; do
		pol=$CF/policy$p
		[ $p = 0 ] && name=LL || name=BL
		for f in $(cat $pol/scaling_available_frequencies); do
			echo $f > $pol/scaling_setspeed
			sleep 0.3
			cur=$(cat $pol/cpuinfo_cur_freq)
			h=$(hw_khz $name)
			v=$(check_pins)
			ok=1
			case $h in *[!0-9]*|'') ok=0; d=x;; *) d=$(( h > f ? h - f : f - h ));; esac
			[ $ok = 1 ] && [ $d -le $((f / 1000)) ] && [ -z "$v" ] || ok=0
			# cpuinfo_cur_freq = clk rate, may be 1 kHz under the OPP
			[ $ok = 1 ] && [ $(( cur > f ? cur - f : f - cur )) -le 1 ] || ok=0
			if [ $ok = 1 ]; then
				echo "PASS policy$p $f kHz: cur $cur hw $h  $(volts)"
			else
				echo "FAIL policy$p $f kHz: cur $cur hw $h $v"; fail=1
			fi
		done
		echo $(cat $pol/scaling_min_freq) > $pol/scaling_setspeed
	done
	for p in 0 4; do echo schedutil > $CF/policy$p/scaling_governor; done
	c=$(hw_khz CCI); [ "$c" = "$cci0" ] || { echo "FAIL CCI moved $cci0 -> $c"; fail=1; }
	hw
	[ $fail = 0 ] && echo "steps PASS" || echo "steps FAIL"
}

stress() {
	secs=$1
	want=$(head -c 16M /dev/zero | md5sum | cut -d' ' -f1)
	for p in 0 4; do
		if [ "${2:-max}" = min ]; then
			echo userspace > $CF/policy$p/scaling_governor
			cat $CF/policy$p/scaling_min_freq > $CF/policy$p/scaling_setspeed
		else
			echo performance > $CF/policy$p/scaling_governor
		fi
	done
	echo "start $(date +%T): policy0 $(cat $CF/policy0/scaling_cur_freq) policy4 $(cat $CF/policy4/scaling_cur_freq)"
	end=$(( $(date +%s) + secs ))
	for c in 0 1 2 3 4 5 6 7; do
		taskset -c $c sh -c "n=0; while [ \$(date +%s) -lt $end ]; do s=\$(head -c 16M /dev/zero | md5sum | cut -d' ' -f1); [ \"\$s\" = $want ] || echo \"FAIL cpu$c md5 \$s\"; n=\$((n+1)); done; echo \"cpu$c runs \$n\"" &
	done
	while [ $(date +%s) -lt $end ]; do
		sleep 10
		t=$(for z in /sys/class/thermal/thermal_zone*; do cat $z/temp; done | sort -n | tail -1)
		echo "$(date +%T) max-temp $t $(hw) $(check_pins)"
	done
	wait
	for p in 0 4; do echo schedutil > $CF/policy$p/scaling_governor; done
	hw
}

case ${1:-} in
hw) hw ;;
steps) steps ;;
stress) stress ${2:-300} ${3:-max} ;;
*) echo "usage: $0 hw | steps | stress SECS [min]"; exit 2 ;;
esac
