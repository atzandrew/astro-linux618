#!/bin/sh
# CPU DVFS checks on the Astro (docs/cpufreq-stock.md, C3 onwards; C1 = e71fd7d, C2 = eb94af0). Run as root.
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
	for n in Vproc_big Vproc_little vsram_proc1 vsram_proc2 VSRAM_PROC1 VSRAM_PROC2; do
		r=$(reg $n); [ -n "$r" ] && printf "%s %s  " $n $(cat $r/microvolts)
	done
	echo
}

hw() {
	echo "LL $(hw_khz LL) BL $(hw_khz BL) CCI $(hw_khz CCI) kHz"
	volts
}

# Stock FY table voltages (uV) per kHz (docs/cpufreq-stock.md)
v_little() {
	case $1 in
	500000|650000) echo 600000;; 756000) echo 625000;; 862000) echo 643750;;
	968000) echo 668750;; 1075000) echo 693750;; 1181000) echo 712500;;
	1358000) echo 750000;; 1500000) echo 781250;; 1541000) echo 800000;;
	*) echo 0;;
	esac
}
v_big() {
	case $1 in
	774000) echo 600000;; 841000) echo 618750;; 925000) echo 637500;;
	1008000) echo 656250;; 1091000) echo 675000;; 1175000) echo 700000;;
	1258000) echo 718750;; 1383000) echo 750000;; 1548000) echo 800000;;
	*) echo 0;;
	esac
}
clampc() { v=$1; [ $v -lt $2 ] && v=$2; [ $v -gt $3 ] && v=$3; echo $v; }
v_cci() {
	case $1 in
	500000) echo 600000;; 557000) echo 612500;; 615000) echo 625000;;
	672000) echo 637500;; 730000) echo 650000;; 816000) echo 668750;;
	873000) echo 681250;; 902000) echo 687500;; 960000) echo 700000;;
	1017000) echo 712500;; *) echo 0;;
	esac
}
# CCI kHz each cluster OPP requires (stock normal CCI map, DTS required-opps)
cci_little() {
	case $1 in
	1541000|1500000) echo 730000;; 1358000) echo 672000;; 1181000) echo 615000;;
	1075000) echo 557000;; *) echo 500000;;
	esac
}
cci_big() {
	case $1 in
	1548000) echo 816000;; 1383000) echo 672000;; 1258000|1175000) echo 615000;;
	1091000) echo 557000;; *) echo 500000;;
	esac
}
DF=$(for d in /sys/class/devfreq/*; do [ -e "$d" ] && grep -q cci $d/device/uevent 2>/dev/null && echo $d; done | head -1)
# C3: Vproc_big = table; Vproc_little = max(A55 table, CCI table);
# Vsram = clamp(Vproc + 100 mV, 0.75, 1.0) V; CCI = max of the two
# required OPPs. Empty output = OK. Only valid while nothing moves (steps).
check_pins() {
	f0=$(cat $CF/policy0/cpuinfo_cur_freq); f4=$(cat $CF/policy4/cpuinfo_cur_freq)
	f0=$(( (f0 + 500) / 1000 * 1000 )); f4=$(( (f4 + 500) / 1000 * 1000 ))
	c1=$(cci_little $f0); c2=$(cci_big $f4); wc=$c1; [ $c2 -gt $wc ] && wc=$c2
	ch=$(hw_khz CCI); ch=$(( (ch + 500) / 1000 * 1000 ))
	cd=$(( $(cat $DF/cur_freq) / 1000 ))
	[ $ch = $wc ] && [ $cd = $wc ] || echo "FAIL cci hw $ch devfreq $cd want $wc"
	eb=$(v_big $f4)
	el=$(v_little $f0); ec=$(v_cci $wc); [ $ec -gt $el ] && el=$ec
	b=$(cat $(reg Vproc_big)/microvolts); l=$(cat $(reg Vproc_little)/microvolts)
	s1=$(cat $(reg vsram_proc1)/microvolts); s2=$(cat $(reg vsram_proc2)/microvolts)
	[ $b = $eb ] || echo "FAIL Vproc_big $b want $eb"
	[ $l = $el ] || echo "FAIL Vproc_little $l want $el"
	w=$(clampc $((b + 100000)) 750000 1000000); [ $s1 = $w ] || echo "FAIL vsram_proc1 $s1 want $w"
	w=$(clampc $((l + 100000)) 750000 1000000); [ $s2 = $w ] || echo "FAIL vsram_proc2 $s2 want $w"
}

steps() {
	cci0=$(hw_khz CCI)
	for p in 0 4; do
		echo userspace > $CF/policy$p/scaling_governor || { echo "FAIL governor"; return 1; }
		cat $CF/policy$p/scaling_min_freq > $CF/policy$p/scaling_setspeed
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
				echo "PASS policy$p $f kHz: cur $cur hw $h cci $(hw_khz CCI)  $(volts)"
			else
				echo "FAIL policy$p $f kHz: cur $cur hw $h $v"; fail=1
			fi
		done
		echo $(cat $pol/scaling_min_freq) > $pol/scaling_setspeed
	done
	for p in 0 4; do echo schedutil > $CF/policy$p/scaling_governor; done
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
		echo "$(date +%T) max-temp $t $(hw)"
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
