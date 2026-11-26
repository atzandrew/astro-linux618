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

## Mesa 26.1.6 and KWin on GLES (2026-11-26, same tr1 kernel)

- Mesa 26.1.6 from trixie-backports (as the Cosmo; gemini-debian d977ca8).
  KWin still desktop GL 3.1 core: pointer motion 0 GL errors (25.0.7:
  ~5000 / 2 s), but full repaints still flood (~35000 lines in 3 min).
- `KWIN_COMPOSE=O2ES` (user env file, test): KWin on OpenGL ES 3.1. **0 GL
  errors** in pointer motion and in the menu run; journald quiet. Drag
  unchanged: 15.87 ms median, input -> flip median 8 ms.
- Start menu still alternates 16 / 31 ms. KWin GPU per menu frame ~15-19
  ms with blur+contrast (3045 jobs in 13 s, KWin queue wait median 13 ms
  behind plasmashell's QSGRenderThread jobs); ~10-11 ms without them (467
  jobs, queue wait 0.12 ms). First open of the session: plasmashell 677-902
  ms of GPU (first-use shader compiles), first frame 100-210 ms after the
  toggle; later opens 45-136 ms.
- Direct scanout of client buffers fails: `mtk_gem_prime_import_sg_table:
  sg_table is not contiguous` / `swiotlb buffer is full` (no display IOMMU),
  so KWin always composites.

## AFBC off, rootfs defaults, and where the menu's GPU time goes

- `PAN_MESA_DEBUG=noafbc` (as the Cosmo): plasmashell's QSGRenderThread
  2536 GPU jobs / 188 ms queue wait -> 164 / 0.26 ms in a 6-toggle menu run.
  KWin unchanged. Now the default with KWIN_COMPOSE=O2ES in gemini-debian
  `overlay-astro/etc/xdg/plasma-workspace/env/astro.sh` and the SDDM
  greeter's CompositorCommand (c1d1ac4).
- The menu frame cost is **one KWin GPU job of 13-25 ms per frame** (the
  main pass; ~50 small jobs around it), also with the GPU pinned at 748 MHz
  (devfreq had only 11 changes in that run).
- `tools/frame-pacing/gpufill.c` (offscreen EGL/GLES, 748 MHz, 1080x2340):
  | test | panfrost texture | GBM scanout surface (mediatek-drm, kmsro) |
  |---|---|---|
  | clear | 0.20 ms (AFBC) / 0.57 ms (noafbc) | 0.57 ms |
  | 1 textured quad | 0.85 / 0.89 ms | 0.89 ms |
  | 1 quad rotated 90 | 0.86 / 0.89 ms | 0.88 ms |
  | 4 blended layers rotated 90 | 2.22 / 2.13 ms | 2.14 ms |
  So the GPU, the scanout buffers, the rotation and AFBC are not it: KWin's
  main pass costs 6-10x the raw work of a 4-layer composite. Next: what
  KWin's passes do (shader variants, number and size of render passes,
  load/store of full-size offscreen targets for blur/contrast).

## Kernel #26 (uname #27, boot-k26.img fed48c13…) result

- Boot: 0xa12 0x21e0, DVFS modules at boot, early flip on, KWin GLES +
  noafbc from /etc/xdg/plasma-workspace/env/astro.sh, kscreen 1080x2340@63.
- Checks with the 12.5 mV/us ramp: steps 32/32 PASS, vfcheck 2 x 40000
  samples 0 LOW, stress 120 s at 2.0 GHz 0 md5 mismatches (runs as C4).
  Transitions 0.46-0.86 ms (5 mV/us: 0.47-1.0 ms).
- Miss: `clock-latency-ns` was on the OPP table node; opp-v2-base.yaml
  defines it per OPP node, so transition_latency stayed 0 (rate limit 1000
  us). Fixed per OPP in boot-k26b.img (DTB only, fcc90910…).

## GPU-side: what makes KWin's pass expensive (gpufill, 748 MHz, GBM scanout target)

| test (1080x2340, rotated 90, noafbc) | ms/frame |
|---|---|
| 4 blended layers, native textures | 2.23 |
| 4 layers sampling linear dmabuf EGLImages (client buffers) | 2.40 |
| 4 layers + 20 scissored partial passes into a full-size offscreen target | 2.92 |
| 4 layers with an sRGB linearise -> 3x3 matrix -> re-encode shader (highp pow) | **9.99** |

- dmabuf imports and partial passes are cheap (panfrost limits fragment
  work to the scissor). A per-pixel colour transform costs 4x and matches
  KWin's ~10-11 ms base per full-screen frame.
- Display side offers what KWin would need to avoid shader work: CRTC
  CTM, GAMMA_LUT (+size); backlight 14010000.dsi.0 (raw, DBV 114/1023)
  under the DSI panel. KWin: Color profile source sRGB, brightness 37 %,
  "dimming to 30%", Color power preference "prefer accuracy",
  allowSdrSoftwareBrightness false.
- Next: confirm KWin's fragment shaders (panfrost `PAN_MESA_DEBUG=shaders`
  in one debug login) and whether brightness/dimming or colour management
  puts the transform in every pixel; then the GPU-side fix (CRTC colour
  offload or the shader path).
