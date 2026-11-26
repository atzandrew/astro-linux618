# Plasma frame pacing on the Astro (2026-11-26)

User report after CPU DVFS C4: "smoother but not as buttery as I'd expect";
start menu slower than on the Cosmo. Method and tools from cosmo-linux618
tools/frame-pacing, ported to `tools/frame-pacing/` (README there).

## Setup

- Test kernel `6.18.58-astro-tr1` (`boot-tr1.img` `f6433c43…`): kernel #25 +
  `kernel/config/trace.config` (FTRACE, default tracers, no function tracer),
  own module tree. `uinput` added as a module for the feeders
  (`CONFIG_INPUT_UINPUT=m` now in astro.config; built externally for tr1).
- Device packages: trace-cmd, sysstat, python3-evdev, linux-perf.
- Feeders: `ftpark.py` (pointer onto Konsole), `ftmouse.py` (Meta-drag),
  `ftmenu.sh` (launcher via `org.kde.PlasmaShell.activateLauncherMenu`;
  a uinput Meta tap does not open it on the Astro, Fn = KEY_LEFTMETA).
  `ftwin.py`: per-event window of frames, CPU and GPU time.
- Note: D-Bus toggles are not user activity; powerdevil dimmed the screen
  in one run (backlighthelper). Nudge the pointer before long runs.

## Findings

1. **Display capped at 32.7 Hz (fixed in test).** Window drag: every flip
   30.6 ms apart. Command mode sent the page-flip event at frame done
   (end of the DSI transfer, 15.86 ms for 1080x2340x24 at 4 x 1050 Mbps);
   KWin then waited ~14.7 ms for its next refresh slot before committing,
   so render and transfer never overlapped. Fix: `mtk_crtc.c`
   `cmd_early_flip` (default on): event at trigger, vblank count still at
   frame done (event-less commits wait on it; counting at the trigger made
   `drm_atomic_helper_wait_for_vblanks` time out). Same-session A/B:
   | drag 8 s | early flip off | on |
   |---|---|---|
   | interval median / p90 | 30.60 / 30.83 ms | 15.87 / 16.10 ms |
   | frames | 275 | 515 |
   | input -> next flip median | 15.1 ms | 8.0 ms |
   15.87 ms = the panel's TE (62.9 Hz, modetest G-S2); KWin's mode says
   61 Hz: the panel mode clock should give 62.9 Hz.
2. **CPU frequency churn.** schedutil rate_limit_us 1000: 2323 A55 and 2364
   CCI changes in 9.5 s of dragging; sugov:0 + sugov:4 ~46 % of a core,
   ~1.5 ms CPU per change (SPMI + pwrap voltage tracking, 5 mV/us software
   ramp wait, PLL relock, CCI follows). rate_limit_us 4000: 960 / 1462
   changes, sugov ~28 %, KWin CPU per frame 2.81 -> 1.12 ms, p90 interval
   15.90 ms, max input->flip 30 -> 21 ms. Stock pays none of this (MCUPM).
3. **KWin GL errors on the rotated output.** KWin 6.3.6 runs desktop GL 3.1
   core (Mali-G57 Panfrost, Mesa 25.0.7). ~2000-3000/s
   `GL_INVALID_OPERATION in glVertexAttribPointer(no array object bound)` /
   `glDrawElements` (+ one `glEnable(GL_POINT_SPRITE)`) whenever the
   rotated output repaints; unchanged with blur/contrast/shakecursor/zoom
   unloaded, **none with the output in native portrait**. journald spends 80-136 ms
   CPU per second logging them during animations. Next: KWin on GLES
   (`KWIN_COMPOSE=O2ES`), needs a relogin.
4. **Start menu: full-screen composites ~15-20 ms of GPU each** at 748 MHz
   (blur off, also in portrait), so frames alternate 16/30 ms (8-13 frames
   per toggle). Window drags repaint only damage (KWin GPU job median 0.18
   ms). GPU devfreq (simple_ondemand, 50 ms) swings 461 <-> 748 MHz;
   pinning 748 MHz did not change the menu intervals. Mainline OVL has no
   AFBC for mt8192 (only mt8195): all buffers linear.
