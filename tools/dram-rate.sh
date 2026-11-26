#!/bin/sh
# DRAM data rate from DDRPHY registers, read only (vendor drivers/memory/
# mediatek/dramc.c fmeter_v1 with the stock DT mt6873-dramc properties).
# DDRPHY_AO ch0 0x10238000, DDRPHY_NAO ch0 0x10236000. Run as root.
R() { busybox devmem $1 32; }
f() { echo $(( ( $(R $1) & $2 ) >> $3 )); }   # addr mask shift
NAO=0x10236000; AO=0x10238000
shu=$(f $((NAO + 0x50c)) 0x30000 16)
pll=$(f $((NAO + 0x50c)) 0x100 8)
o=$((0x700 * shu))
# per-PLL register pairs: pll 0 first, pll 1 second (stock DT)
if [ $pll = 0 ]; then S=0x704 P=0x708; else S=0x724 P=0x728; fi
sdm=$(f $((AO + S + o)) 0xffff0000 16)
pre=$(f $((AO + P + o)) 0xc0000 18)
pos=$(f $((AO + P + o)) 0x7 0)
ck4=$(f $((AO + 0x874 + o)) 0x4 2)
md=$(f $((AO + 0x744 + o)) 0x100 8)
cl2=$(f $((AO + 0x8b4 + o)) 0x2 1)
fbk=$(f $((AO + 0x70c + o)) 0x40 6)
dqs=$(f $((AO + 0x870 + o)) 0x100000 20)
dq=$(f $((AO + 0x870 + o)) 0x200000 21)
vco=$(( ((52 >> pre) * (sdm >> 8)) >> pos >> ck4 >> md >> cl2 << fbk ))
[ $dqs = 1 ] || [ $dq = 1 ] && vco=$((vco >> 2))
case $vco in 4264) r=4266;; 3718) r=3733;; 3068) r=3200;; 2366) r=2400;;
1859) r=1866;; 1534) r=1600;; 1144) r=1200;; 754) r=800;; 396) r=400;; *) r="$vco (undecoded)";; esac
echo "shuffle $shu pll $pll sdmpcw 0x$(printf %x $sdm) prediv $pre posdiv $pos ckdiv4 $ck4 pll_md $md cldiv2 $cl2 fbksel $fbk dqsopen $dqs dqopen $dq"
echo "DRAM data rate: $r Mbps"
