#!/bin/sh
# vfrun.sh big|little : schedutil, bursty load on the cluster under test, sampler pinned to the other
CF=/sys/devices/system/cpu/cpufreq
reg() { for r in /sys/class/regulator/regulator.*; do [ "$(cat $r/name)" = $1 ] && echo $r; done; }
B=$(reg Vproc_big); L=$(reg Vproc_little)
for p in 0 4; do echo schedutil > $CF/policy$p/scaling_governor; done
if [ $1 = big ]; then LOAD=4-7; SAMP=0; else LOAD=0-3; SAMP=4; fi
( end=$(( $(date +%s) + 12 )); i=1; while [ $(date +%s) -lt $end ]; do
	for c in $(seq 0 $(( i % 4 ))); do taskset -c $LOAD sh -c "head -c $(( (i % 7 + 1) * 3000000 )) /dev/zero | md5sum >/dev/null" & done; wait
	sleep 0.$(( i % 5 )); i=$((i+1)); done ) &
taskset -c $SAMP /usr/local/sbin/vfcheck 40000 200 $B $L
r=$?
wait
for p in 0 4; do echo userspace > $CF/policy$p/scaling_governor; cat $CF/policy$p/scaling_min_freq > $CF/policy$p/scaling_setspeed; done
exit $r
