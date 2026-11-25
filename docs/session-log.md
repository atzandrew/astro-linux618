# Session log

## 2026-11-25 — day 0: survey

- Vendor source at `~/Build/astro-kernel`: 4.14.186 MTK BSP, single commit
  `a79860700`. Astro board identified as `k6873v1_64_defconfig` +
  `mt6873.dts` + Aeon `aeon_gpio.dtsi` (grep for `aeon` across the tree).
- MT6873 vs mainline MT8192: 97/102 node addresses equal, pin tables equal
  bar GPIO220–227 (receipts in `docs/hardware-map.md`).
- Repo scaffolded from cosmo-linux618 layout; base pinned to v6.18.58.
- Flashing host Monolith (192.168.0.235): answers ping, but no SSH (port 22
  refused). Device not yet reached; nothing read or written on it.

## 2026-11-25 — Monolith reached; read-only adb survey

- SSH `atzero@192.168.0.235` (EndeavourOS x86_64) works; adb, fastboot,
  mtkclient-git 2.1.4.1.r72 installed. Astro on USB `0e8d:201c`, adb
  authorised (`Astro_Slide_5G_Transformer`).
- Non-root getprop/by-name survey → `docs/p0-findings.md`. Headline: locked
  + green, A/B on slot a, boot + vendor_boot + dtbo, UFS, Android 11.
- Nothing written to the device.

## 2026-11-25 — P0 backup (read-only)

- `mtk printgpt` after `adb reboot`: preloader caught, device unprotected
  (SBC/SLA/DAA off) — `docs/p0-findings.md`.
- `mtk rl p0 --skip userdata` → `~/Build/astro-backup/p0` on Monolith
  (backup stays off git). Needed a hand power-key reset to leave DA mode
  first.
- Backup done (user ran it): 58 partitions, 7.2 GiB, SHA256SUMS written —
  `docs/p0-backup.md`. Preloader LUs still to read.
- Research: no official Planet Linux/Debian release for the Astro found
  (promised Debian/KDE, Kali, Sailfish; Planet's wiki covers Gemini and
  Cosmo only). No reference Linux kernel to borrow from.
- Boot chain decoded from dumps → `docs/p0-findings.md`: boot v2 +
  DTB section, `bootopt=` cmdline, vendor_boot empty, dtbo panel list.
  Panel SH8802B **command mode**; LK FB 0x7dd80000 pitch 4352 BGRA8888.
  First-boot display plan needs a decision (cmd mode ≠ Cosmo).

## 2026-11-25 — bootloader unlocked (stage A)

- User ran `mtk da seccfg unlock` on Monolith: "Detected V4 Lockstate",
  "SecCfgV4 - hwtype found: V4", "Successfully wrote seccfg."
  (`~/Build/astro-backup/unlock.log`). Pre-unlock seccfg: `p0/seccfg.bin`.
- After a power-key reset: LK orange-state warning, then stock Android
  booted. **No userdata wipe** (the wipe belongs to `fastboot flashing
  unlock`; mtkclient rewrites seccfg directly — same as the Cosmo).
- adb: `ro.boot.verifiedbootstate=orange`, `ro.boot.flash.locked=0`,
  `ro.boot.vbmeta.device_state=unlocked`.
- A/B: misc+0x800 bootloader_control decoded (slot a active, successful)
  — `docs/p0-findings.md`.
