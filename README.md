# astro-linux618

Mainline Linux **6.18 LTS** for the Planet Computers **Astro Slide 5G**
(MediaTek MT6873 / Dimensity 800), replacing Android's vendor 4.14
kernel. The goal is the same as for the Cosmo
([cosmo-linux618](https://github.com/atzandrew/cosmo-linux618)): a
fresh Debian trixie install with a Plasma Wayland desktop, built by
[gemini-debian](https://github.com/atzandrew/gemini-debian).

The approach follows the Cosmo and Gemini PDA projects: a pinned upstream
kernel plus a small tree of changed files. The MT6873 is the phone
sibling of the MT8192 that mainline supports for Chromebooks (97 of
mainline `mt8192.dtsi`'s 102 addressed nodes sit at the same addresses
in the vendor MT6873 tree), so the board rides on `mt8192.dtsi` and the
MT8192 drivers. Where the hardware needs specific values, they are taken
from the stock kernel, device tree and Android images.

## Status

**Early bring-up: not for users.** There are no images to download. The
kernel boots to a small rescue initramfs with a framebuffer console and a
USB network shell; there is no root filesystem or desktop yet. Flashing
anything from this repository needs mtkclient, a full backup of the
device first, and the ability to recover it.

### Road to Beta 1

The checks the Cosmo's Beta 1 testers went through
([cosmo docs/beta-testing.md](https://github.com/atzandrew/cosmo-linux618/blob/main/docs/beta-testing.md)),
adapted to the Astro. Ticked = works on the Astro today.

**Start and setup**
- [ ] Setup opens on the first start and creates your account
- [ ] After the restart, the login screen appears and your password works

**Screen and input**
- [ ] The picture is right: no flicker, no wrong colours (today: console
      only, through the bootloader's display path)
- [ ] Touch works across the whole screen
- [x] Every key on the keyboard types the right character (console,
      Planet's US layout including the Fn layer)
- [ ] Esc on the power key (short press), power on a long press
- [ ] The keyboard backlight turns on (today: on/off only, used for boot
      codes)
- [ ] Opening and closing the slide is seen (lock / wake)
- [ ] The volume keys work

**Network**
- [ ] Wi-Fi connects, and Firefox opens a web page
- [ ] Wi-Fi reconnects by itself after a restart
- [ ] Wi-Fi reconnects by itself after sleep
- [ ] Bluetooth finds and pairs a device (mouse, keyboard or headphones)
- [ ] Bluetooth headphones or a speaker play sound
- [ ] A paired Bluetooth device reconnects by itself after sleep

**Sound**
- [ ] The speaker plays sound
- [ ] Headphones play sound

**Sleep and battery**
- [ ] Closing the slide or the power key puts the Astro to sleep; the
      power key or opening the slide wakes it
- [ ] After a night asleep the battery has dropped by only a few percent
- [ ] A wall charger charges it, and the battery percent goes up

**Ports and cards**
- [ ] A USB stick or mouse works in the **left** port
- [ ] A USB stick or mouse works in the **right** port
- [ ] A microSD card shows up in the file manager

**Apps**
- [ ] Firefox, Thunderbird and LibreOffice open
- [ ] Discover installs an app from Flathub
- [ ] A game (KPatience, KSudoku or KBlocks) runs

**Off and on**
- [ ] Shut down from the menu switches the Astro off
- [ ] Restart from the menu comes back to the login screen

### Under the hood

What the checks above need, in the order planned
(`docs/bringup-checklist.md` has every block with its source and notes).

**Working**
- [x] Boot from `boot_a` through the stock bootloader (unlocked, orange
      state), all 8 CPUs
- [x] Both recovery escapes seen to work: watchdog reset and the 10 s
      power-key reset
- [x] USB device mode on the right port: network and shell
- [x] Console on the AMOLED, blanked after 60 s idle (interim: through
      the bootloader's display path, not a display driver)
- [x] UFS storage at full link speed (HS-G3, 2 lanes, ~990 MB/s read);
      read-only for now
- [x] Built-in keyboard (AW9523) with the stock keymap and Planet's Fn
      layer on the console

**To do**
1. [ ] Esc/power key: the first step that lets Linux talk to the PMIC
       (MT6359P), with a fixed keys driver that never touches the reset
       settings
2. [ ] Root filesystem on UFS and Debian from gemini-debian (Fn layer =
       the Cosmo's xkb layout)
3. [ ] Volume keys, slide sensor
4. [ ] Regulator audit, RTC, power off, charger (MT6360)
5. [ ] Battery level, USB-C power delivery, CPU frequency scaling,
       thermal limits
6. [ ] Display driver: mediatek DRM with command-mode DSI and the SH8802B
       panel
7. [ ] Touchscreen (GT9897), left USB-C port, USB host mode, microSD
8. [ ] GPU (panfrost, Mali-G57), sleep
9. [ ] Wi-Fi and Bluetooth (CONSYS, as on the Cosmo), audio

**Not planned for Beta 1:** modem (calls, SMS, mobile data), GPS,
cameras, HDMI out, NFC, fingerprint reader, notification LEDs, vibration.

## Build

Needs gcc for arm64 (native on an arm64 host, otherwise the cross
`aarch64-linux-gnu-gcc`), plus `flex`, `bison`, `bc`, `python3`, the
OpenSSL and libelf headers, a static aarch64 busybox for the initramfs,
and `avbtool` for the boot image's AVB footer (the boot and dtbo packers
are in `bin/`):

- Fedora: `flex bison bc openssl-devel elfutils-libelf-devel busybox
  android-tools`
- Debian/Ubuntu: `flex bison bc libssl-dev libelf-dev busybox-static`,
  plus `avbtool` from the Android platform tools

```sh
bin/build-kernel.sh dtbs   # device tree only (fast check)
bin/build-kernel.sh        # Image.gz, DTB, modules → out/
bin/build-dtbo.sh          # bootloader overlay → out/dtbo.img
bin/build-boot-img.sh      # boot.img (refuses unsafe PMIC/display setups)
```

The first run clones the pinned stable tag into `build/src`.
`docs/flashing.md` has the mtkclient procedure and the way back to stock.

## Source code and licences

The kernel and everything in this repository are GPL-2.0 (`LICENSE`).

- **Kernel:** `kernel/BASE` pins the upstream stable tag;
  `kernel/delta/` holds the changed files whole, at their kernel paths;
  `kernel/config/astro.config` is the config fragment.
- **Rescue initramfs** (inside `boot.img`): `initramfs/` and
  `bin/build-boot-img.sh`, plus busybox copied unchanged from Fedora 44
  aarch64 (busybox 1.37.0-7.fc44, GPL-2.0; source in the Fedora source
  package, `dnf download --source busybox`).
- The console keymap (`kernel/delta/drivers/tty/vt/defkeymap.c_shipped`,
  made by `bin/make-defkeymap.py`) follows the layout in Planet's
  Android keyboard app; no Planet file is included.

## Documentation

- `AGENTS.md`: status, rules and how to work on this repository (read first)
- `docs/bringup-checklist.md`: every hardware block, its state and order
- `docs/hardware-map.md`, `docs/p0-findings.md`: hardware and stock facts
- `docs/flashing.md`: mtkclient procedure and restoring stock
- `docs/session-log.md`: bring-up history and test results
