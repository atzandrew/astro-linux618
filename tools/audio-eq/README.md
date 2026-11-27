# audio-eq: speaker response measurement (2026-11-26)

- `sweep.py gen OUT.wav [--ch both|L|R]`: 48 kHz exponential sweep
  50 Hz-20 kHz, 6 s, -12 dBFS.
- `sweep.py ir REC.wav OUT.npz`: deconvolve a recording (Farina), gate
  1 ms / 5 ms around the direct sound, response in OUT.npz, full IR as
  OUT-ir.wav (REW: File > Import impulse response).
- `sweep.py plot A.npz ... OUT.txt`: 1/6-octave table, 0 dB = 1-3 kHz.
- `fit.py OUT.txt A.npz ...`: power average + a biquad EQ (RBJ) applied.

Setup used: sweep played on the Astro with `aplay -D hw:0,0` (raw, no
filter) or `pw-play` (through the filter), recorded at the same time on
livingwall from the Blue USB mic (`arecord -D hw:2,0`, capture gain 11),
both over SSH. Mic ~30 cm, centred, capsule at speaker height; 3
positions. numpy only. Self-test (sweep against itself): flat within
1 dB from 110 Hz.
