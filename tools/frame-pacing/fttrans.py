# fttrans.py: time CPU frequency changes (userspace governor, 200 alternating
# scaling_setspeed writes per pair). Run as root.
import time
CF="/sys/devices/system/cpu/cpufreq/policy%d/"
def w(p,f,v): open(CF%p+f,"w").write(str(v))
for p,pairs in ((0,[(500000,2000000),(1358000,1500000)]),(4,[(774000,2000000),(1383000,1548000)])):
    g=open(CF%p+"scaling_governor").read().strip()
    w(p,"scaling_governor","userspace")
    for a,b in pairs:
        w(p,"scaling_setspeed",a); time.sleep(0.05)
        t=time.monotonic()
        for i in range(100):
            w(p,"scaling_setspeed",b); w(p,"scaling_setspeed",a)
        d=(time.monotonic()-t)/200*1e6
        print(f"policy{p} {a//1000}<->{b//1000} MHz: {d:.0f} us per change")
    w(p,"scaling_governor",g)
