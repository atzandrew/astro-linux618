# ftkey.py COUNT PERIOD_S [KEY]: tap KEY (default Meta = start menu) COUNT
# times, PERIOD_S apart (open, close, open ...). Logs tap times to
# /var/tmp/ft/events.txt. Run as root (uinput).
import sys,time
from evdev import UInput, ecodes as e
n=int(sys.argv[1]); per=float(sys.argv[2])
key=getattr(e,sys.argv[3]) if len(sys.argv)>3 else e.KEY_LEFTMETA
# a full key range, so libinput classes the device as a keyboard
ui=UInput({e.EV_KEY:list(range(e.KEY_ESC, e.KEY_MICMUTE + 1))},name='ft-key'); time.sleep(1.0)
log=open('/var/tmp/ft/events.txt','w')
for i in range(n):
    t=time.monotonic()
    ui.write(e.EV_KEY,key,1); ui.syn(); time.sleep(0.05)
    ui.write(e.EV_KEY,key,0); ui.syn(); log.write('%.6f\n'%t); log.flush()
    time.sleep(max(0,t+per-time.monotonic()))
time.sleep(0.5); ui.close(); log.close()
