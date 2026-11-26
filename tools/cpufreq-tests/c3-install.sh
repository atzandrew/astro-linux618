#!/bin/sh
# cpufreq C3: install kernel #25 modules (keep #24's), blacklist the CCI module too.
set -eu
M=/lib/modules/6.18.58-astro
[ -d $M.k24 ] && { echo "$M.k24 exists already, stopping"; exit 1; }
mv $M $M.k24
cp -a /home/atzero/mod-k25 $M
chown -R root:root $M
depmod 6.18.58-astro
printf 'blacklist mediatek-cpufreq\nblacklist mtk-cci-devfreq\n' > /etc/modprobe.d/astro-cpufreq.conf
install -m 755 /home/atzero/c-test.sh /usr/local/sbin/astro-c-test
install -m 755 /home/atzero/vfcheck /usr/local/sbin/vfcheck
sed -i 's,/home/atzero/vfcheck,/usr/local/sbin/vfcheck,' /home/atzero/vfrun.sh
sync
cat /etc/modprobe.d/astro-cpufreq.conf
ls $M/kernel/drivers/devfreq/mtk-cci-devfreq.ko $M/kernel/drivers/cpufreq/mediatek-cpufreq.ko
echo "installed; synced"
