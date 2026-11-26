# Flashing the Astro Slide (bring-up)

All device commands run **on Monolith** (192.168.0.235), by the user
(mtk runs are never started by the agent: it hands over the command).
The Astro is on Monolith's USB by its **right-hand** USB-C port.

## mtkclient behaviour on this unit (observed 2026-11-25)

- `adb reboot` with `mtk …` waiting catches the preloader window; so does
  a ~10 s power-key hold (that resets the board from any state seen so
  far, including mtk DA mode).
- After one mtk command the board stays in DA mode (`0e8d:2000`); the next
  mtk command cannot handshake until a ~10 s power-key hold. **Do not use
  `mtk reset`** (on the Cosmo it powered the board off).
- UFS boot LUs are `--parttype boot1` / `boot2` (not `lu1`).

## Stage A — unlock (once)

Locked + green LK refuses unsigned images ("Verified boot is enabled.
Please download %s image with corret signature or disable verified boot",
lk_a strings). Unlock writes `seccfg` (backed up in
`~/Build/astro-backup/p0/seccfg.bin`):

```bash
mtk da seccfg unlock
```

Then reset (power ~10 s) and let **stock Android** boot. Expected: an
orange-state warning from LK, then Android (it may wipe userdata). This
proves the unlock alone, before any image of ours is involved.

Relock path (stock only): `mtk da seccfg lock`.

## Stage B — escape tests (images from `out/`)

Copy to Monolith: `scp out/dtbo.img out/boot-wdtest.img out/boot.img atzero@192.168.0.235:Build/astro-backup/`

1. **Watchdog escape** — `dtbo_a` = no-op overlay, `boot_a` = wdtest image:
   ```bash
   mtk w dtbo_a,boot_a dtbo.img,boot-wdtest.img
   ```
   Power-key reset to leave DA mode. Expected, slider open (keyboard
   light): heartbeat, then **solid on** (init reached, watchdog not fed),
   then a **reset by itself** within ~31-62 s; this repeats every boot.
   On Monolith the preloader (`0e8d:2000`) re-appears each cycle
   (`watch -n1 'lsusb | grep 0e8d'`). The loop is left by catching a
   preloader window with the next mtk command.
2. **Normal image + power-key escape** — `boot_a` = boot.img:
   ```bash
   mtk w boot_a boot.img
   ```
   Expected: heartbeat, then **fast blink** (init feeding the watchdog);
   **no** self-reset for > 2 min. Then hold power ~10 s: the board must
   reset.

These were the one-time escape proofs for the first boots. Later images
are not re-tested (AGENTS.md rule 5, user 2026-11-25).

## Restore stock Android

The no-op `dtbo` breaks the stock kernel's overlay, so restore **both**:

```bash
cd ~/Build/astro-backup
mtk w boot_a,dtbo_a p0/boot_a.bin,p0/dtbo_a.bin
```

Any other partition: `mtk w <name> p0/<name>.bin`, one at a time
(userdata was not backed up). Not yet checked: what `mtk wl p0` does with
`gpt.bin`/`gpt_backup.bin`/`preloader_*.bin` in that folder, and the
exact preloader write command — read mtkclient's source before using
either. Nothing in this procedure writes the GPT or the preloaders.
