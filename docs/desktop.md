# Desktop (Plasma 6 Wayland on panfrost), 2026-11-25

User decisions (2026-11-25): Plasma after G-S3; no mouse for now
(keyboard only; touchscreen is a later stage). Burn-in rule R5 applies to
the desktop: idle screen-off, compositor DPMS, kernel idle-off backstop.

## P1 plan

1. Panel orientation from the DT (`rotation = <90>`, metadata only) so
   KWin starts in landscape without per-user config; fbcon keeps its
   cmdline `rotate:1` (it takes precedence over the panel hint; the
   mediatek planes only rotate 0/180, so no hardware rotation stacks).
2. `apt-get install plasma-desktop konsole` (with recommends, ~1180
   packages, 822 MiB), service starts blocked by a temporary
   `/usr/sbin/policy-rc.d` during the install; SDDM disabled afterwards.
3. panfrost and lvts_thermal load at boot (blacklists removed).
4. Powerdevil for `atzero`: dim 30 s, screen off 60 s idle (stock off
   path); dark theme, panel auto-hide suggested; the kernel idle-off guard
   (600 s) stays as backstop.
5. First start by hand: log in on tty1, `startplasma-wayland`.

## P1 pre-flash check (2026-11-25) — approved ("approved")

1. **Image**: `boot-p1.img` sha256
   `8a58efbc36109382fd0e327d41ffc98221ea5f84ad867fa8b7039ea7ed35d322`
   (Monolith `~/Build/astro-backup/`), kernel #22 unchanged (`Image.gz`
   `b053088b…`), DTB `191e8366…` (G-S3 DT + `rotation = <90>` on the
   panel). Writes `boot_a`.
2. **Modules** (installed with the old ones kept as `.p0`, synced, right
   before the flash): `panel-shenghe-sh8802b.ko` `7e2a70b1…` (source
   `94de3f0a…`, pinned), `mediatek-drm.ko` `c660d9e4…`.
3. **Changes**: panel driver: `get_orientation` returning the DT value,
   read at probe (an invalid value fails probe → console fallback); no
   command, table, timing or power change. `mtk_dsi`: after creating the
   connector, `drm_connector_set_orientation_from_panel` (a read-only
   connector property). DT: the one property.
4. **Rootfs changes in the same step**: remove `blacklist panfrost` and
   `blacklist lvts_thermal` (both load at boot: vgpu → 0.5625 V at
   358 MHz, LVTS stock sequence — both tested), disable SDDM, remove
   policy-rc.d, Powerdevil config for `atzero`. All synced.
5. **Test**: boot → console as now (fbcon upright, rotate:1); read the
   connector's `panel orientation` = "Right Side Up"; panfrost + devfreq +
   17 thermal zones up at boot; 0xa12. Then you: log in on tty1,
   `startplasma-wayland`; check landscape, keyboard, idle dim 30 s / off
   60 s and wake; log out → console.
6. **R-rules**: no panel register/sequence change; panel traffic as now
   (frames, stock on/off); rails as G-S3. Burn-in: Plasma idle-off 60 s,
   kernel guard 600 s.

## P1 result (2026-11-25) — passed

- `boot-p1.img` `8a58efbc…` flashed (kernel #22); panel and mediatek-drm
  modules `7e2a70b1…` / `c660d9e4…` installed (`.p0` kept). Console as
  before; connector `panel orientation` = Right Side Up (3); panfrost,
  devfreq (358 MHz, vgpu 0.5625 V) and 17 LVTS zones up at boot; 0xa12
  0x21e0.
- Plasma 6.3.6 installed (rc 0; no SDDM came with it; rootfs 5.8 GB).
  `startplasma-wayland` from tty1: **landscape** (KWin applies the panel
  orientation: primary plane rotation set by KWin), keyboard works,
  KWin and plasmashell render on **panfrost** (fdinfo `drm-driver:
  panfrost`, max 748 MHz). **Dim at 30 s, off at 60 s, key wakes,
  logout returns to the console** (user).
- Log noise only: powerdevil cannot open `/dev/i2c-1` (DDC probe), no
  ModemManager/evolution.
- gemini-debian (`astro-display` branch): `packages/astro-plasma.list`
  (with Recommends), `IMAGE_SIZE=8G`, `/etc/xdg/powerdevilrc` and
  `kdeglobals` (dark) in overlay-astro.

Next candidates: touchscreen driver (no pointer yet), a login manager
(SDDM Wayland or autologin), vgpu idle-off (sync_state blockers).

## P2 pre-flash check (2026-11-25) — awaiting approval

Touchscreen, power-off, SDDM. User decisions: touch option a (mainline
Berlin core without the vendor Berlin-A reset writes), SDDM option a (X11
greeter, Xorg screen-off after 1 min).

1. **Image**: `boot-tp1.img` sha256
   `4984784ac17ac7fbb0712a19844036a609886ee7d6a6a28cbcf520e65d4cb668`
   (Monolith `~/Build/astro-backup/`), kernel **#23** (`Image.gz`
   `17c3edeb…`, DTB `0471915b…`). Writes `boot_a`. Module tree #23
   installed with #22's kept as `.k22`, synced, right before the flash.
2. **Changes vs #22**:
   - Power-off (`docs/poweroff.md`): `mt6359-poweroff.c` (built in,
     pinned) + an mt6397-core MFD cell (pinned); DT `pwrc` under the
     MT6359 with `mediatek,toprgu = <&watchdog>`. Writes **only at
     power-off**: MT6359P `PPCCTL0` bit 0 = 0, then (still powered) TOPRGU
     `NONRST_REG2` bit 13 clear, `WDT_MODE`, `SWRST`.
   - Touch (`docs/touch-stock.md`): goodix_berlin_i2c + `gt9897` (pinned,
     module, loads at boot); DT `&i2c0` okay 400 kHz, `touchscreen@5d`,
     touch pins, `avdd-supply = <&mt6360_ldo2>`. At probe: **VTP enabled
     at its current 1.8 V** (no voltage write), 15 ms, reset GPIO20
     released, then the driver reads version/IC info and handles events.
   - Guard: pwrc exactly compatible + toprgu = watchdog, driver built in,
     sources pinned; Goodix I2C module only, pinned (three negative tests
     refused).
3. **SDDM (rootfs)**: `sddm` + `sddm-theme-breeze` (installed, service
   starts blocked during the install), `/etc/sddm.conf.d/astro.conf`:
   X11 greeter, Breeze theme, Xsetup rotates the X screen to landscape;
   `/etc/X11/xorg.conf.d/10-astro-dpms.conf`: blank/standby/suspend/off
   after 1 min (DPMS off = the panel's stock off). policy-rc.d removed.
4. **Test**: boot → SDDM greeter in landscape; 0xa12; touch probe log
   (version, IC info), events with `evtest`/libinput while you touch;
   greeter blanks at 1 min, key wakes; log in (Plasma Wayland), touch in
   Plasma; then `poweroff` with USB unplugged → stays off; power key →
   boots. Optional: `poweroff` on USB → LK decides (expect charging mode
   or a boot).
5. **R-rules**: no panel or rail change except VTP on at its own voltage
   (stock behaviour); PMIC write only at power-off (the stock one);
   burn-in: greeter off after 1 min, Plasma as P1, kernel guard 600 s.
6. **Escapes**: 0xa12 unchanged (no write to STRUP); a bad power-off at
   worst leaves the board on or reboots; power-key 8 s hold reset stays.

### P2 findings and fix image (2026-11-26)

- SDDM first boot: X started before mediatek-drm and auto-added fbdev →
  udev symlink `/dev/dri/astro-panel`, Xorg Device/Screen/ServerLayout on
  it (modesetting, AutoAddGPU off), SDDM after astro-display.service.
- "Keyboard not working" in the greeter: the keys reached the kernel
  (evtest: 197 key events); the greeter's drawing did not reach the
  command-mode panel with glamor (`Failed to make import prime FD as
  pixmap`), only the hardware cursor moved. Fix: `AccelMethod none` +
  `ShadowFB on` (software, DIRTYFB per damage) — typing shows. Also
  `InputMethod=` (no Qt virtual keyboard), as the Cosmo.
- Touch: see `docs/touch-stock.md` T1 findings: VTP 2.6 V, inverted-x.
- **`boot-tp2.img`** sha256
  `1d6b16556fd11f803b2309032d626800be7751ef9f77ccb3b0ace0d3c4a2ee9f`
  (Monolith): kernel #23 unchanged (`Image.gz` `17c3edeb…`), DTB
  `af029c9b…` = tp1 + MT6360 LDO2 fixed 2.6 V (core sets it at probe while
  off) + `touchscreen-inverted-x`. Modules unchanged (core = mainline,
  `8bc3a87c…`). Guard: vtp exactly 2.6 V, Goodix core unmodified mainline
  (negative test refused).

### P2 greeter on KWin (2026-11-26)

The X11 greeter (software rendering, ShadowFB) was too slow (user: SDDM
animations very slow). SDDM now runs `kwin_wayland --drm` as on the Cosmo
(gemini-debian `cbf149c`): KWin renders on panfrost, takes the rotation from
the greeter's kwinoutputconfig.json (= the Plasma session's, Rotated270,
scale 2) and maps touch itself. Burn-in: KWin starts
`/usr/libexec/astro-greeter-idle` (swayidle on ext-idle-notify-v1 →
`kscreen-doctor --dpms off` at 60 s, on at input). Result (user, after a
reboot): greeter smooth, touch correct, panel blanked within 70 s and woke
on input; login to Plasma fine. Also this boot: `androidboot.bootreason=
PowerKey` after last night's power-off (power-key boot from off works).
Plasma touch (user, same day): corners and drag correct with
inverted-x. Still open: power-off with USB
plugged in, text rendering (user: rougher after mediatek-drm loads).
