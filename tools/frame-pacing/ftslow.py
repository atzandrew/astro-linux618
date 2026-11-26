# ftslow.py SECONDS PERIOD_MS: pointer motion events every PERIOD_MS (slow frames)
import sys,time
from evdev import UInput, ecodes as e
secs=float(sys.argv[1]); per=float(sys.argv[2])/1000
ui=UInput({e.EV_KEY:[e.BTN_LEFT],e.EV_REL:[e.REL_X,e.REL_Y]},name="ft-slow"); time.sleep(1.0)
t0=time.monotonic(); n=0; d=4
while time.monotonic()-t0<secs:
    if n%20==0 and n: d=-d
    ui.write(e.EV_REL,e.REL_X,d); ui.syn(); n+=1
    time.sleep(max(0,t0+n*per-time.monotonic()))
ui.close()
