# ftpark.py X Y: move the pointer to the top-left corner, then to about (X, Y)
# logical px in small steps (slow moves, little pointer acceleration).
import sys,time
from evdev import UInput, ecodes as e
x=int(sys.argv[1]); y=int(sys.argv[2])
ui=UInput({e.EV_KEY:[e.BTN_LEFT],e.EV_REL:[e.REL_X,e.REL_Y]},name="ft-park"); time.sleep(1.0)
for i in range(60):
    ui.write(e.EV_REL,e.REL_X,-100); ui.write(e.EV_REL,e.REL_Y,-100); ui.syn(); time.sleep(0.008)
time.sleep(0.2)
n=max(x,y)
for i in range(n):
    if i<x: ui.write(e.EV_REL,e.REL_X,1)
    if i<y: ui.write(e.EV_REL,e.REL_Y,1)
    ui.syn(); time.sleep(0.004)
time.sleep(0.3); ui.close()
