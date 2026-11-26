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
