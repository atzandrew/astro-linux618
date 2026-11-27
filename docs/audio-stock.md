# Audio: stock inventory and plan (step 1, 2026-11-26)

How the stock Android image (Planet 4.14.186 BSP `astro-kernel`, stock DTB
`backup/boot_a.dtb.0.dts` + `backup/dtbo_a.0.dts`, stock vendor partition)
drives audio, what mainline 6.18.58 has for each part, and the plan.
Research only: no flash, no writes to the device. Every read this session
was read-only (`dd` from `super`, pinctrl and pwrap debugfs, single
registers).

Receipts (gitignored, `backup/vendor-audio/`): `audio_device.xml`,
`AudioParamOptions.xml`, `MicInfo_AudioParam.xml`,
`HpImpedance_AudioParam.xml`, `PlaybackVolAna_AudioParam.xml`,
`audio_policy_configuration.xml`, copied from `vendor_a` in `super`
(sdc55, LP metadata: `vendor_a` = 1075968 sectors at sector 3325952, ext4,
image sha256 `28bdfe41…`). The LP table also has `vendor_a-cow` (virtual
A/B snapshot), so the base image may not hold the very latest OTA files.
Audio config is unlikely to differ; noted anyway.

Template: cosmo-linux618 `docs/audio-stock.md`, session log "Audio
A1/A2/A3" (2026-10-31) and "headphone jack detection J1" (2026-11-24).

## Parts

| Part | Stock | Mainline 6.18 |
|---|---|---|
| AFE | `mediatek,mt6873-sound` @ 0x11210000, SPI 202 level-high | `mt8192.dtsi` `afe` (same base, same IRQ), `snd-soc-mt8192-afe` (built, loads, probe fails: no AUDIO domain) |
| Codec | MT6359P analog, vendor `sound/soc/codecs/mt6359.c` (`mediatek,mt6359-sound`) | `sound/soc/codecs/mt6359.c` (MFD cell `mt6359-sound`, already created on our kernel, no driver bound) |
| Speaker amp | analog amp after the MT6359 HP buffer, enable = **GPIO30** level (no pulses) | `simple-amplifier.c` (`simple-audio-amplifier`, `enable-gpios`) |
| `speaker_amp@34` (i2c6) | generic `mtk-sp-spk-amp.c` probe; no smart-PA driver built → `MTK_SPK_NOT_SMARTPA` = dummy codec | nothing to do (not a real device) |
| Machine driver | vendor `mt6873-mt6359.c`, card `mt6873mt6359` | `mt8192-mt6359-rt1015-rt5682.c` (Chromebook; needs an MT6359-only variant) |
| Headset detect | vendor `accdet/mt6359/accdet.c`, PMIC EINT0, EINT IRQ | `sound/soc/codecs/mt6359-accdet.c` (MFD cell `mt6359-accdet` already created) |

## Speaker amplifier (the open question from 2026-11-25: answered)

- Stock machine driver (`sound/soc/mediatek/mt6873/mt6873-mt6359.c:114`)
  has one DAPM widget `Ext_Speaker_Amp` (`SND_SOC_DAPM_SPK`) whose event
  calls the Aeon GPIO helper: POST_PMU → `aeon_gpio_set("aeon_spk_en1")`,
  PRE_PMD → `aeon_gpio_set("aeon_spk_en0")`, each only when
  `IsAeonHdmi == 0` (set by the LT8912B HDMI panel driver).
- `aeon_gpio.dtsi`: `aeon_spk_en0` = GPIO30 GPIO mode output-low,
  `aeon_spk_en1` = GPIO30 output-high (slew-rate 1). One plain level, no
  pulse train (unlike the Cosmo's AW8738 mode-3 pulses). No other code in
  the vendor tree drives GPIO30 (grep for `aeon_spk_en`).
- Routes: `Ext_Speaker_Amp` ← `LINEOUT L`, `Headphone L Ext Spk Amp`,
  `Headphone R Ext Spk Amp`. Which one carries signal is chosen by the
  HAL's mixer path (next section).
- The physical amp part is not named anywhere in the BSP, DT or vendor
  configs: it is an analog, GPIO-enabled amp (the board needs nothing
  else). `MTK_AUDIO_NUMBER_OF_SPEAKER = 2` and both HP channels are
  routed to it, so a stereo amp (or two amps on one enable).
- `speaker_amp@34` on i2c6: probed by `mtk-sp-spk-amp.c`, which tries
  RT5509 / MT6660 / TFA98xx probes; none is built in
  `k6873v1_64_defconfig`, so stock always runs `MTK_SPK_NOT_SMARTPA`
  (dummy codec). Not a device to describe in mainline.
- Live state on our kernel (2026-11-26, pinctrl debugfs): GPIO30 mode 0,
  output, low (amp off), so LK leaves it off.
- Mainline equivalent: `simple-audio-amplifier` with `enable-gpios =
  <&pio 30 GPIO_ACTIVE_HIGH>`: it drives the pin high on POST_PMU and low
  on PRE_PMD, which is the stock sequence. The HDMI condition is not
  needed until HDMI exists.

## Codec paths (stock HAL, `audio_device.xml` + `AudioParamOptions.xml`)

Card name in the HAL config: `mt6873mt6359`.

| Function | Stock option | Stock mixer path |
|---|---|---|
| Speaker | `MTK_AUDIO_SPEAKER_PATH = int_hp_buf`, `SPK_PATH_HP = yes` | HP buffer (see below) + `Ext_Speaker_Amp Switch` 1 |
| Headphones | | `DAC In Mux` Normal Path, `HPL/HPR Mux` = Audio Playback |
| Earpiece | `RCV_PATH_INT = yes` (codec receiver driver, no amp) | `RCV Mux` = Voice Playback |
| Main mic (bottom) | `MTK_AUDIO_NUMBER_OF_MIC = 2`, `MTK_DUAL_MIC_SUPPORT` | `PGA_L_Mux` AIN0, `ADC_L_Mux` Left Preamplifier, `MISO0/1_MUX` UL1_CH1 |
| Second mic (back) | | `PGA_R_Mux` AIN3, `ADC_R_Mux` Right Preamplifier, UL1_CH2 |
| Headset mic | | `PGA_L_Mux` AIN1, `ADC_L_Mux` Left Preamplifier, UL1_CH1 |

- Speaker with `SPK_PATH_HP`: the HAL turns on `headphone_output` (HP mux
  Audio Playback) plus `ext_speaker_output`. That is the measured stock
  state on the Cosmo (same MTK HAL family, session log A2: HP mux
  value 2 = "Audio Playback", amps on); here it is inferred, to be
  confirmed by listening in A1. `speaker_output` (LOL) exists in the XML
  but is the LO path, not this board's (the Cosmo's LO attempt was
  silent).
- Mainline names: one `HP Mux` (vendor HAL writes `HPL Mux`/`HPR Mux`),
  options "Open", "LoudSPK Playback", "Audio Playback", "Test Mode",
  "HP Impedance"; `Headphone L/R Ext Spk Amp` outputs hang off `HP Mux`
  in every non-open mode. Start with "Audio Playback" (stock); not
  "LoudSPK Playback" (= `HP_MUX_HPSPK`, the Cosmo's silent try).
- Capture mux names in mainline match the vendor XML (`PGA_L_Mux`,
  `PGA_R_Mux`, `ADC_L_Mux`, `ADC_R_Mux`, `MISO0_MUX`…). Inputs AIN0-AIN3.
- Mic type (ACC / DCC / DMIC) is not in the DT: the HAL reads it from
  NVRAM / a property (`mPhoneMicMode getprop`, `mHeadsetMicMode`). Main
  and sub mics are analog (`MicInfo` lists AMIC entries
  SPH1642HT5H, -41 dBV; DMIC entries are the generic template). Mainline
  `mediatek,mic-type-0/1/2` default to Idle; A3 starts with ACC (1) and
  checks the recorded level against DCC.
- Volumes (`PlaybackVolAna`): left for the UCM step.

## MT6359P vs mainline `mt6359.c`

- The vendor codec has exactly one MT6359P conditional
  (`CONFIG_MTK_PMIC_CHIP_MT6359P`, `mt6359.c:6497`): the HP-impedance
  efuse offset. Mainline has no HP impedance code, so nothing to port.
- Probe-time writes of mainline `mt6359_codec_init_reg` (every register
  it touches outside DAPM, all MT6359P addresses = mainline `mt6359.h`):
  DCXO_CW12 0x7a8 (RG_XO_AUDIO_EN_M on, then off again), AUDENC_ANA_CON23
  (clock source = internal DCXO), AUDDEC_ANA_CON0/6/7 (short-circuit
  protect disable bits), SMT_CON1 0x32 (|= 0x3ff0), DRV_CON2/3/4
  0x3c-0x40 (0x8888 / 0x8888 / 0x88 = the 4 mA default), GPIO_MODE2/3/4
  CLR 0xdc/0xe2/0xe8 and GPIO_DIR0/1 0x88/0x8e (audio pads to GPIO
  input), ZCD_CON0 0x0. Vendor `mt6359_codec_init_reg` does the same set,
  plus AUDENC_ANA_CON19 (HP EINT threshold, mainline sets it in ACCDET),
  and leaves DRV_CON at reset default (its `gpio_driving_set` is
  `#if 0`; mainline writes the default value). None of these is in the
  STRUP block (0xa12) or a regulator/buck register.
- MTKAIF calibration at card init (mainline `mt8192_mt6359_init`) writes
  the codec's MTKAIF phase registers and toggles DCXO_CW12 RG_XO_AUDIO
  as vendor `mt6873_mt6359_mtkaif_calibration` does.
- Supplies: mainline `mt6359.c` takes no regulator. Stock VAUD18 is a
  fixed 1.8 V LDO left on; read 2026-11-26: LDO_VAUD18_CON0 (0x1c9a) =
  0x0001, MON (0x1c9e) = 0x0003 (enabled). 0xa12 = 0x21e0 at the same
  time.

## AFE, AUDIO power domain and the audiosys reset

- AFE probe on #26: `deferred probe timeout`, -110: the AUDIO domain was
  deleted from `spm` in W2 (`/delete-node/
  power-domain@MT8192_POWER_DOMAIN_AUDIO`), as on the Cosmo before A1.
- Mainline MT8192 AUDIO domain = vendor `spm_mtcmos_ctrl_audio`
  (`clk-mt6873-pg.c:2833`): PWR_CON 0x354, status bit 21 in PWR_STATUS
  0x16c / 0x170, SRAM_PDN bit 8 / ack bit 12, bus protect INFRA
  PROTECTEN_2 bit 4 (SET 0x714, CLR 0x718, STA1 0x724). Same order (power
  on → clk/iso/rst → SRAM → release protect). No domain-supply.
- **Watchdog-block write:** mainline `mt8192-afe-pcm` probe calls
  `reset_control_reset()` on `resets = <&watchdog 17>` (TOPRGU
  SWSYSRST 0x18: read-modify-write, set bit 17 with key 0x88000000, then
  clear). Vendor `mtk_wdt.h:125` names bit 17 `MTK_WDT_SWSYS_RST_AUDIO_RST`
  (0x00020000), so it is the audio reset on the MT6873 too. Stock AFE
  never pulses it. It does not touch MODE/LENGTH/RESTART (the watchdog
  path), but it is a TOPRGU register: listed in the A1 pre-flash check.
- AFE clocks: `clk-mt8192-aud` is bound to `11210000.syscon` already;
  APLL1/2 from apmixedsys (our delta file), topckgen muxes as mainline.
- MTKAIF pins (stock `pinctrl` states on the AFE): clk_mosi GPIO214/215,
  dat_mosi GPIO216/217, dat_miso GPIO218/219, ch34 mosi GPIO196, ch34
  miso GPIO199; `_on` = mode 1 (schmitt, no bias), `_off` = mode 0
  (input, pull-down; GPIO219 off = no bias). Live state: all eight are
  in mode 1 already (LK). Mainline `mt8192-afe-gpio.c` uses the same state
  names on the sound node.

## Headset detection (ACCDET)

- Stock config: `CONFIG_MTK_ACCDET`, `CONFIG_ACCDET_EINT_IRQ`,
  `CONFIG_ACCDET_SUPPORT_EINT0` (PMIC-internal EINT0, the Cosmo's
  arrangement); no HW mode define.
- Stock dtbo fragment@12 (accdet node): `accdet-mic-vol` 8,
  `accdet-mic-mode` 2, `accdet-plugout-debounce` 1, `eint_use_ext_res` 0,
  `headset-mode-setting` (15 values) `<0x500 0x500 1 0x1f0 0x800 0x800
  0x20 0x44 4 1 5 3 3 5 0xe>`, three-key `<0 0x50 0xdc 0x190>`,
  three-key-CDD `<0 0x79 0xc0 0x258>`, four-key `<0 0x3a 0x79 0xc0 0x190>`.
- Mainline `mt6359-accdet.c` reads `accdet` under the PMIC node; its
  defaults already equal stock (mic-vol 8, mic-mode 2, plugout-debounce 1,
  PMIC EINT IRQ, EINT0, eint-use-ext-res 0); `mediatek,pwm-deb-setting`
  takes the 15 `headset-mode-setting` values. No binding YAML in 6.18
  (driver-only); keys via `mediatek,three-key-thr` /`four-key-thr`.
- Mainline MT6359 top-status enum already has AUD at bit 7 (vendor
  `upmu_hw.h`: XPP 6, AUD 7, MISC 8), so the Cosmo's MT6358 IRQ bug does
  not repeat here.
- No stock register dump exists (no Android to run): the reference is the
  vendor driver's sequence and these DT values.
- The mainline mt8192 machine driver never calls
  `mt6359_accdet_enable_jack_detect()` (the mt8188 one does, from
  `soc_card_data->accdet`): the MT6359-only variant adds that.
- No extra headphone/switch GPIOs on this board (no Cosmo-style
  headphone_cs/en; grep of both DTs and the vendor codec/ACCDET).

## What the PMIC sees (rule 5)

Codec and ACCDET write MT6359P registers over pwrap. Every register
they name, resolved from the 6.18.58 sources (2026-11-26):
- codec outside the audio block: exactly 0x32 SMT_CON1, 0x3c/0x3e/0x40
  DRV_CON2-4, 0x88/0x8e GPIO_DIR0/1, 0xda/0xdc/0xe0/0xe2/0xe6/0xe8
  GPIO_MODE2-4 SET/CLR, 0x7a8 DCXO_CW12; everything else in
  0x2300-0x26ff (AUD_TOP, AFE, AFUNC, AUDDEC/AUDENC/ZCD, NCP);
- ACCDET: 0x2320 AUD_TOP_RST_CON0, 0x2334 AUD_TOP_INT_STATUS0, 0x24e2
  AFE_NCP_CFG2, 0x2528-0x2532 AUDENC_ANA_CON16/18-21, 0x268a-0x26bc
  ACCDET_CON1-26; its IRQs through the MFD irq chip (AUD group mask
  0x2328 AUD_TOP_INT_CON0 and the ACCDET bits).
None is 0xa12 (STRUP_CON12), the keys block, a buck/LDO enable or
voltage, or the RTC. `bin/build-boot-img.sh` today
refuses any PMIC child other than adc/keys/regulators/pwrc and any spm
domain other than CONN/MFG/DISP: each step below extends it to exactly the
audited shape (like W2 and cpufreq did) and pins the audited sources by
sha256.

## Plan

Each stage: its own pre-flash check (written, audited, user yes), user
flashes on livingwall, 0xa12 read afterwards (expect 0x21e0), sync after
rootfs writes. Tests that need the user's ears or hands are asked first.

- **A1 speaker** (kernel + DT + modules):
  - DT: AUDIO domain back in `spm`; `afe` enabled; PMIC child
    `audio-codec` (properties only: mic types); `dmic-codec` node (the
    mainline Primary Codec link includes it; no GPIO); speaker amp
    `simple-audio-amplifier` on GPIO30; sound node with the new
    compatible, `mediatek,platform = <&afe>`, MTKAIF pinctrl states as
    stock, `audio-routing` (Speakers ← "Headphone L/R Ext Spk Amp" via
    the amp), the amp as an aux device.
  - Kernel delta (upstreamable): `mt8192-mt6359-rt1015-rt5682.c` gets an
    MT6359-only card variant (`mediatek,mt8192-mt6359`-style compatible,
    codec-agnostic widgets Speakers / Headphones / Earpiece / Headset Mic
    / Built-in Mics with pin switches, routes from DT);
    `mtk-soundcard-driver.c` parses the generic `audio-aux-devs`; binding
    YAML updated with both.
  - Config: `SND_SOC_MT6359=m`, the machine driver `=m`
    (`SIMPLE_AMPLIFIER`, `DMIC` already `=m`).
  - Pass: card registers; HP mux "Audio Playback" + amp gives a quiet
    tone from the speaker (user listens, asked first); GPIO30 high while
    playing, low after; 0xa12 0x21e0.
- **A2 headphones + earpiece**: DAPM routes for Headphones and Earpiece,
  same image if A1 shows no surprise.
- **A3 mics**: AIN0 / AIN3 / AIN1 routes, mic type (ACC first, compare
  DCC), PGA levels against stock defaults.
- **A4 jack detection**: `SND_SOC_MT6359_ACCDET=m`, PMIC child `accdet`
  with the stock values, machine driver hooks the jack; plug/unplug,
  headset mic bias, suspend behaviour (Cosmo hj2/hj3 checks).
- **A5 UCM** in gemini-debian (Astro overlay): HiFi verb with Speaker /
  Headphones (JackControl) / Mic devices, so PipeWire picks the paths.
- **Later, separate**: Bluetooth A2DP via PipeWire.

## Open

- Amp part name (not needed for the driver; would only matter for a
  vendor-specific compatible). A look at the board would answer it.
- Mic type per mic (A3), HP mux mode for the speaker (A1 listening).
- HDMI interaction (`IsAeonHdmi`): only once LT8912B exists.

## A1 pre-flash check (2026-11-26): speaker

Image `boot-a1.img` sha256
`f5d4af51384123511478bc89511cd51202253a5a760fe55b89250414fb732c93`
(on livingwall `~/Build/astro-backup/boot-a1.img`, sha256 checked there).
Image.gz `f6375358…`, DTB `c422d256…`. Release `6.18.58-astro` (uname
will show #28). Config vs #26 (`out/k26/k26.config`): only
`SND_SOC_MT6359=m` and `SND_SOC_MT8192_MT6359_RT1015_RT5682=m` added;
no built-in change. Rootfs: this build's full module tree installed at
`/lib/modules/6.18.58-astro` (root-owned, depmod, sync), #26's tree kept
as `.k26`; `alsa-utils` installed by apt (add to gemini-debian later);
test tone `/var/tmp/tone440-m30.wav` (440 Hz, -30 dBFS, 2 s, fades).

Changes:
- DT: AUDIO power domain back in `spm` (no child, no supply); PMIC child
  `audio-codec` (properties only: dmic-mode 0, mic types ACC/DCC/ACC);
  root `dmic-codec`; `audio-amplifier` = `simple-audio-amplifier`,
  `enable-gpios` GPIO30 active high, pin GPIO mode output-low;
  `sound` = `mediatek,mt8192-mt6359`, model "Astro Slide", MTKAIF pinctrl
  states as stock, `aux-devs` = the amp, routing: amp INL/INR ← Headphone
  L/R Ext Spk Amp, Speakers ← amp OUTL/OUTR, Headphone Jack ← Headphone
  L/R, Earpiece ← Receiver, AIN0/AIN3/AIN1 ← Built-in Mic / Built-in Mic 2
  / Headset Mic.
- Kernel delta: `sound/soc/mediatek/mt8192/mt8192-mt6359-rt1015-rt5682.c`
  (new MT6359-only card variant; links the DT leaves without a codec are
  ignored), `sound/soc/mediatek/common/mtk-soundcard-driver.c` (generic
  `aux-devs`), binding YAML (compatible, routing names, `aux-devs`).
- Guard (`bin/build-boot-img.sh`): spm = exactly AUDIO, CONN, MFG0-6, DISP
  with AUDIO bare; `audio-codec` exactly the properties above; codec only
  `=m` with `mt6359.c`/`mt6359.h` (unmodified v6.18.58) and the machine
  driver pinned by sha256; the AFE's `resets` must be TOPRGU bit 17;
  ACCDET driver and node still refused. Negative tests (mutated DTB):
  mic-type change, resets bit 18 and an added accdet node are each
  refused.

What runs at boot that did not before:
- scpsys powers AUDIO on (vendor-equal sequence).
- AFE probe: TOPRGU SWSYSRST bit 17 set/clear (key 0x88000000, RMW;
  vendor names it the audio reset; not MODE/LENGTH/RESTART), audiosys
  clocks and APLL1/2, then runtime suspend.
- Codec probe (card bind): the register set in "What the PMIC sees"
  (pads 0x32-0x40, PMIC GPIO mode/dir 0x88-0xe8, DCXO_CW12 0x7a8 audio
  clock bit on then off, audio block). MTKAIF calibration at card init:
  codec MTKAIF phase registers + DCXO_CW12, AFE monitor registers.
- Amp probe drives GPIO30 low (already low). HP/LO/RCV muxes default
  Open: nothing audible at boot.

Risk flags: MT6359P register writes over pwrap (audio block, audio pad
config, DCXO audio clock enable); one TOPRGU register (SWSYSRST, audio
bit only); a new power domain; new modules only (no built-in change).
No STRUP/keys/regulator/RTC/charger write, no watchdog MODE/timer change,
no panel/display, no voltage change.

Escapes: power-key reset (STRUP_CON12, untouched: 0xa12 read after) and
watchdog (mtk_wdt timer path unchanged; init/systemd still own it).

Checks after the flash (mine, over SSH; nothing needs hands or ears):
1. 0xa12 single-register read = 0x21e0.
2. uname #28; `dmesg`: AFE probe OK, mt6359-sound bound, card
   "Astro Slide" registered, no oops; `aplay -l`; mtkaif calibration
   result line; GPIO30 output-low; `/proc/asound` DAPM idle.
3. Then, **after asking you "ready?"**: HP Mux "Audio Playback",
   DAC In Mux "Normal Path", Headset Volume low, Speakers switch on, the
   -30 dBFS tone twice. You listen: tone from the speaker(s), and whether
   both sides play. GPIO30 high during playback, low within seconds
   after.
Pass: 1-3 as stated. Fail: no boot / hang (escapes), 0xa12 changed, no
card, card but silence, GPIO30 not following playback, any oops.

### A1 result, first boot (2026-11-26): card PASS, playback FAIL (fix found)

- Boots boot-a1.img (uname **#29**, not #28 as predicted; build 17:00:22).
  0xa12 = 0x21e0. Card 0 "Astro Slide" (`mt8192_mt6359`), PCMs
  Playback_1..9, HDMI, captures; mt6359-sound and simple-amplifier bound
  (both use a dummy regulator: no vaud18 / VCC in the DT; VAUD18 is on
  from boot). No oops. GPIO30 output-low at idle.
- Mixer set silently (ADDA_DL_CH1/2 ← DL1_CH1/2, DAC In Mux Normal Path,
  HP Mux Audio Playback, Headset Volume -10 dB, Speakers on): GPIO30
  stayed low with no stream.
- Tone (user listening): `aplay -D hw:0,0` → EIO, `mtk_afe_pcm_pointer
  hw_ptr err`, GPIO30 never went high. /dev/mem read during the stream:
  AFE_DAC_CON0 0x11 (AFE + DL1 on), `aud_afe` enable count 1, but
  AUDIO_TOP_CON0 = 0xb0fd403c with bit 2 (AFE clock gate) still set.
- Cause = the Cosmo A1 bug (mt8183, cosmo-linux618 3a1806c), same code in
  mt8192-afe-pcm.c: the audsys clock gates are written through the AFE's
  syscon regmap, and runtime resume enables the clocks before leaving
  cache-only (suspend gates them after entering it), so the gate writes
  are dropped. Fix (delta `sound/soc/mediatek/mt8192/mt8192-afe-pcm.c`):
  leave cache-only before enabling the clocks, gate them before entering
  it. Module only; per the Cosmo lesson the AFE module is never reloaded
  in place (shared regmap keeps the old module's callbacks): install,
  sync, reboot.

### A1 result after the AFE fix (2026-11-26): speaker PASS

- Same boot-a1.img (#29); only `snd-soc-mt8192-afe.ko` replaced
  (sha256 893512c6…, the A1 build's module kept as
  /var/tmp/snd-soc-mt8192-afe.ko.a1), depmod, sync, reboot.
  0xa12 = 0x21e0, card up, no oops.
- At boot GPIO30 went high briefly while WirePlumber probed the PCM: the
  mixer path from the A1 test had been saved by alsa-utils at shutdown
  (`/var/lib/alsa/asound.state`) and restored. Low again once the PCM
  closed. After the test HP Mux was set back to Open and stored.
- Tone (-30 dBFS, HP Mux Audio Playback, Headset Volume -10 dB, Speakers
  on), `aplay -D hw:0,0` x2: exit 0, no hw_ptr error; GPIO30 high during
  each tone, low ~4 s after. User: both played fine (left/right not
  checked yet).
- So the stock speaker path is confirmed: MT6359 HP buffer ("Audio
  Playback", not LoudSPK) into the GPIO30 amp.
- L/R check (user listening, 2026-11-26): left-channel-only tone from the
  left speaker, right-only from the right, as the user held the device
  (two speakers, stereo, not swapped). HP Mux back to Open, stored.
- Earpiece (A2 part, same image, 2026-11-26): Speakers off, HP Mux Open,
  RCV Mux "Voice Playback", Handset Volume -10 dB, Earpiece on; tone x2:
  aplay exit 0, GPIO30 stayed low; user: heard from the earpiece only.
  Stock RCV_PATH_INT path confirmed (receiver driver, left DAC, no amp).
- Open: gain staging (UCM), pops; headphones (A2) when wired headphones
  are at hand.

### Music test (user, 2026-11-26) and the volume bug (A1c)

- User, PipeWire default sink ("Built-in Audio Stereo", ACP
  stereo-fallback, `hw:0`): loudness peaks at 50 % and falls again above
  it; at the peak it is more than the speakers handle; tone quality poor
  next to the Cosmo/Gemini.
- Cause of the fold-over: mainline mt6359.c "Headset/Lineout/Handset
  Volume" are upside-down. Register code 0 = +8 dB, 0x12 = -10 dB
  (DL_GAIN_8DB .. DL_GAIN_N_10DB), but the controls are not inverted and
  carry playback_tlv (-10 dB at 0). Read on the device: control 0 →
  ZCD_CON2 0x0000 (+8 dB); control 18 → 0x0912 (-10 dB, = the Cosmo's
  stock -10 dB value). PipeWire uses Headset Volume as hardware volume:
  software attenuation up to ~50 % with the control at "0" (really
  +8 dB), then raises the control, which lowers the real gain. So all A1
  tones and the music test ran at +8 dB. Mainline also leaves
  ana_gain[] zeroed (= +8 dB) until userspace writes; vendor sets HP to
  code 8 (0 dB) at init.
- Fix (delta `sound/soc/codecs/mt6359.c`, upstreamable): invert flag on
  the three DL gain controls + the matching inversion in
  mt6359_get_playback_volsw(); HP ana_gain = DL_GAIN_0DB at init. Same
  registers (ZCD_CON1/2/3), only the codes change. Module only (Image and
  DTB byte-identical to boot-a1.img). Guard sha updated.
- Stock tuning (vendor_a `/etc/audio_param`): PlaybackVolAna SPK
  `speaker_pga` 10 (= code 10 = -2 dB on the HP buffer; HSSPK headset 12,
  HS 9). PlaybackACF "Speaker": 2nd-order 300 Hz high-pass only.
  PlaybackDRC "Music": 8-band BesLoudness, crossovers 300/500/1k/2k/4k/
  8k/16k Hz, thresholds -50/-40/-30/-20/0 dB with +12/+12/+12/+12/0 dB
  (quiet-signal boost), band gains -10 dB (<300 Hz), -3 dB (300-500 Hz),
  limiter off. This processing (HAL, MTK proprietary) is what the Linux
  path lacks; candidate: a PipeWire filter-chain in gemini-debian (UCM
  step), not a kernel matter.
- A1c result (2026-11-26, module installed, reboot): 0xa12 0x21e0, card
  up, no oops. Mapping now right: Headset Volume 8 (-2 dB) → ZCD_CON2
  0x050a during a stream (code 10 both channels; = stock speaker_pga 10
  and the Cosmo's stock speaker value). PipeWire ACP slider → control:
  ≤40 % software only (hw -10 dB), 60 % → 5 (-5 dB), 80 % → 13 (+3 dB),
  100 % → 18 (+8 dB): monotonic. Stock speaker gain ≈ 70 %; the UCM step
  should cap the speaker at -2 dB. Note: alsa-utils restores the last
  stored mixer state at boot (the pre-fix value 18 came back as +8 dB);
  the UCM step owns these values afterwards.
- Music re-test after A1c (user): no fold-over; still thin; clipping
  audible just above ~70 % (= -2 dB HP gain, the stock speaker_pga), so
  the stock gain is also the clean maximum. Next: UCM speaker volume cap
  at -2 dB and a filter-chain with the stock speaker processing (300 Hz
  HPF, low-band cut, loudness DRC); the HPF also removes the bass energy
  that clips first.

## A5 (part): UCM + stock speaker filter (2026-11-26, gemini-debian 3b46829)

- UCM `ucm2/conf.d/mt8192_mt6359/Astro Slide.conf` →
  `ucm2/MediaTek/mt8192/astro-slide/HiFi.conf`: verb = ADDA_DL ← DL1,
  DAC In Mux Normal Path; Speaker = Headset Volume 8 (-2 dB, stock
  speaker_pga 10) + HP Mux Audio Playback + Speakers on, volume in
  software (no hw volume element: the drive stays at -2 dB at every slider
  position, checked); Earpiece (profile "HiFi (Earpiece)") = Handset
  Volume 18 (+8 dB, stock receiver_pga 0) + RCV Mux Voice Playback.
  Headphones and mics are not listed until A4/A3.
- Stock speaker processing as found in vendor_a: Aurisys runs
  mtk_bessound on playback; the speaker ACF is a 2nd-order 300 Hz
  high-pass only. `MTK_BESLOUDNESS_SUPPORT = no`, so the 8-band "Music"
  DRC profile is most likely an unused template (not reproduced).
  Reproduced: PipeWire filter-chain smart filter
  (`filter-chain.conf.d/astro-speaker.conf`), bq_highpass 300 Hz
  Q 0.7071 per channel, target = the UCM Speaker sink only.
- User (music): cleaner, no clipping at 100 %. Still thin (as stock:
  the HPF removes bass); an opt-in taste EQ is possible later, not stock.

## Speaker EQ (2026-11-26, gemini-debian default)

- Measurement (tools/audio-eq): Blue USB mic on livingwall, sweeps from
  the Astro, 3 positions (centre, 10 cm left, 10 cm right) x both/L/R/
  filtered; rec peaks -14..-21 dBFS, noise ~-67 dBFS (traffic outside).
  Mic gain at maximum clipped (0 dBFS) on the first level check: capture
  11 of 22.
- Speaker average (6 single-speaker takes, 1/3 oct, 0 dB = 1-3 kHz):
  -12.7 dB at 500 Hz, -7.9 at 630, -3.2 at 800 (drivers roll off below
  ~700 Hz), flat ±2 dB 1-2 kHz, rising to +7.0 at 4 kHz and +9.0 at 5 kHz
  (spread 0.5-1.6 dB: the drivers, not the room), +5.2 at 6.3 kHz, -11 at
  10 kHz. 700 Hz-3 kHz dips move with position (L/R interference): not
  equalised. Filtered vs raw: identical above 300 Hz (filter verified).
- A/B by the user with music: A stock (HPF only), B HPF + -7 dB at
  4.8 kHz ("different, losing something"), C = B + 3 dB at 650 Hz Q 1.0
  and -3 dB overall: "way better" than A and B. C is the gemini-debian
  default (user decision); the stock-only filter is kept, not loaded.
  avg + C: within about ±2 dB of the midband from 800 Hz to 6.3 kHz.
