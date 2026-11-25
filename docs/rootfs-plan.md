# Debian root filesystem on userdata (CLI first)

User decisions (2026-11-25): Debian on `userdata` (sdc56, ≈112 GiB; Android
user data is erased, every other partition untouched), command-line image
first (no Linux display driver yet), internet through Monolith (NAT).

## Pieces

- **Rootfs**: gemini-debian `DEVICE=astro` (devices/astro.env,
  overlay-astro/, packages/astro-*.list): Debian 13 trixie minbase +
  base.list + busybox/console-setup + CLI tools; modules from this repo's
  out/modroot (6.18.58-astro); 4 GiB image, grown to the partition on
  first boot (gemini-growfs). Login: the build-time user with the password
  asked by the build, Hydra's SSH key; host keys made on the device.
- **Handoff** (`initramfs/init` `try_root`, after the USB rescue network is
  up): find `userdata` by GPT name; all UFS read-only first, then
  `blockdev --setrw` on exactly userdata and its disk (sdc); mount ext4 rw;
  require /sbin/init + /etc/os-release; tripwire file
  `/var/lib/astro-boot/state` (no `cache` partition on the Astro): TRY →
  next boot RSC + rescue, else TRY + handoff; `astro-boot-ok.service` (after
  multi-user.target, no SSH/network dependency) writes OK. Before
  `switch_root`: rescue helpers killed, black frame, watchdog fd closed
  without the magic character (keeps running; no WATCHDOG_NOWAYOUT needed),
  systemd takes it (`RuntimeWatchdogSec=30s`, `RebootWatchdogSec=30s`).
  `astro.noroot` stays in rescue.
- **Console**: `astro-console.service` runs the same `astro-console` /
  `astro-disp` scripts (copied from initramfs/ at rootfs build), busybox
  applets first on PATH; `ExecStopPost=astro-disp black`, Restart=always
  (the rescue init's console_check, as a unit). Keyboard: console-setup
  from the Cosmo xkb layout `cosmo(us)` (= kernel defkeymap), TER16x32.
- **Network**: usb0 static 10.15.21.1/24, gateway + DNS 10.15.21.2.
  Monolith: NetworkManager profile `astro-usb` for the Astro's gadget MAC
  42:00:15:21:01:00, `ipv4.method shared` at 10.15.21.2/24 (NAT + DNS via
  firewalld's nm-shared zone). Works for the rescue initramfs too (it hands
  Monolith .2 by DHCP; the shared profile sets the same address).
- Masked: hibernate, hybrid-sleep, suspend-then-hibernate, suspend
  (untested here). No UPower yet (power-off untested on the Astro). No
  `parted` (the GPT holds the bootloaders).

## Pre-flash check (image root1)

- `boot-root1.img` `0f0fda93…f0a4`: kernel and DTB = bat3b (Image.gz
  `c8240682…`, DTB `04cf898c…`); only the init changed (handoff above).
- Storage writes: `userdata` (sdc56) only — the image flash, then the
  ext4 at run time. Every other sd* stays read-only; sdc (the disk) is
  writable while Debian runs (needed for sdc56 writes).
- Escapes to observe with Debian running: power-key hold; watchdog under
  systemd (`sudo kill -SEGV 1`: systemd freezes, stops feeding → reset
  ≤ 30 s, next boot → rescue by the tripwire, the boot after → Debian);
  tripwire itself (that same sequence). Rescue path without a Debian
  userdata: unchanged (mount fails → stays).
- Order: flash `userdata` first (Android's userdata could otherwise be
  mounted read-write by the handoff check), then `boot_a`.

## root2 fix (2026-11-25)

root1 left every sdc partition writable when UFS came up late (session
log). root2: read-only pass over /sys/class/block (mknod for lagging
nodes), 1 s settle, and a gate: the handoff is refused unless every sd
device except userdata and its disk reads back `ro` = 1.
`boot-root2.img` `2739e141…153c`.
