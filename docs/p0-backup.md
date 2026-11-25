# P0 backup — Astro Slide 5G

Taken 2026-11-25 on Monolith, `~/Build/astro-backup/p0/` (never in git:
contains IMEI/NVRAM/seccfg). Device state at backup: stock Android 11,
locked, slot a.

- Command (run by the user): `mtk rl p0 --skip userdata` → "All Dumped
  partitions success". 58 `.bin` files, 7.2 GiB, incl. `super` (6 GiB),
  `gpt.bin`, `gpt_backup.bin`. Checksums: `p0/SHA256SUMS` (58 lines).
- Not included: `userdata` (by choice: device is to be wiped) and the
  **preloader**, which lives in UFS boot LUs (LU1, LU2; 4 MiB each),
  not in the user LU that `rl` walks.
- UFS: SK hynix `H9HQ15AFAMADAR`, FW `A102`, block 4 KiB, LU0 (user)
  0x1dcb000000 ≈ 119 GiB, LU1/LU2 0x400000 each.
- Preloader (2026-11-25, user ran): `mtk ro 0 4194304 p0/preloader_boot{1,2}.bin --parttype boot{1,2}`
  (`--parttype lu1` is not understood by mtkclient 2.1.4: UFS boot LUs are
  `boot1`/`boot2`, see `mtkclient/Library/DA/storage.py`). Both start
  `COMBO_BOOT`; build path `/media/planet/NEWBIE/x900/alps_r0mp1/…/preloader/platform/mt6873`;
  boot1 and boot2 differ (A/B copies). Added to SHA256SUMS (60 lines).
