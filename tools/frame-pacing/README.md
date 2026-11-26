# frame-pacing (Astro)

Ported from cosmo-linux618 tools/frame-pacing (its README explains each
tool). Needs the tracing kernel (`KLOCAL=-tr1 KFRAG=kernel/config/trace.config
bin/build-kernel.sh`), `trace-cmd`, `sysstat`, `python3-evdev`, `linux-perf`.

Astro differences: GPU devfreq is `13000000.gpu`; one vblank event per
refresh (`VPF=1`, the default; the Cosmo needs `VPF=2`); the panel is a
DSI command-mode panel, so check the vblank rate in `ftanalyze.py` before
trusting sequence gaps and use the wall-clock intervals in `fttimeline.py`.

New: `ftkey.py COUNT PERIOD_S [KEY]` taps Meta (start menu) COUNT times.

    sudo FT_ROOT=1 ./astro-frametrace drag1 'python3 ftmouse.py 8 6'
    sudo FT_ROOT=1 ./astro-frametrace menu1 'python3 ftkey.py 6 2.5'
    python3 ftanalyze.py /var/tmp/ft/drag1.txt
