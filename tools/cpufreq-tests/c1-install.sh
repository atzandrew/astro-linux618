#!/bin/sh
# cpufreq C1: install kernel #24 modules, keep #23's, blacklist mediatek-cpufreq.
set -eu
M=/lib/modules/6.18.58-astro
[ -d $M.k23 ] && { echo "$M.k23 exists already, stopping"; exit 1; }
mv $M $M.k23
cp -a /home/atzero/mod-k24 $M
chown -R root:root $M
depmod 6.18.58-astro
echo "blacklist mediatek-cpufreq" > /etc/modprobe.d/astro-cpufreq.conf
install -m 755 /home/atzero/c-test.sh /usr/local/sbin/astro-c-test
sync
ls -la /etc/modprobe.d/astro-cpufreq.conf; cat /etc/modprobe.d/astro-cpufreq.conf
ls $M/kernel/drivers/cpufreq/mediatek-cpufreq.ko
echo "installed; synced"
