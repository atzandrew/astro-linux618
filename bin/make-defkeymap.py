#!/usr/bin/env python3
"""Console default keymap for the Astro's built-in keyboard.

Writes kernel/delta/drivers/tty/vt/defkeymap.c_shipped: the base kernel's
table (build/src, pinned v6.18.58) with only the entries below changed, so
the Linux console types what the keycaps say from the first boot. The
Debian rootfs replaces it (console-setup with gemini-debian's xkb "cosmo"
layout, variant us: the same layer 3).

Source of the layout: stock Android, Planet_Keyboard.apk
res/raw/keyboard_layout_english_us_intl_gemini.kcm (system_a, 2026-11-25),
on the Astro matrix (aw9523-keypad keymap in the board DTS):
  - Fn = KEY_LEFTMETA (matrix 4,3) acts as AltGr: altgr map = kcm "fn:"
  - base layer differences from a PC US map: key KEY_APOSTROPHE is
    '\\' / '|', Shift+',' is '/', Shift+'.' is '?', Shift+Backspace is
    forward delete.

    bin/make-defkeymap.py        # regenerate the delta file
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
BASE = ROOT / "build/src/drivers/tty/vt/defkeymap.c_shipped"
OUT = ROOT / "kernel/delta/drivers/tty/vt/defkeymap.c_shipped"

# keysyms (include/uapi/linux/keyboard.h): K(KT_LATIN, c) = 0xf000 | c;
# unicode U+xxxx is stored as xxxx ^ 0xf000; KT_FN Find/Select/Prior/Next/
# Remove = 0xf114/0xf117/0xf118/0xf119/0xf116; KT_SHIFT AltGr = 0xf701.
def lat(c):
    return 0xf000 | ord(c)

ALTGR = 0xf701
FIND, REMOVE, SELECT, PRIOR, NEXT = 0xf114, 0xf116, 0xf117, 0xf118, 0xf119
U_EURO = 0x20ac ^ 0xf000

# Linux keycodes
KC = dict(K1=2, K2=3, K3=4, K4=5, K5=6, K6=7, K7=8, K8=9, K9=10, K0=11,
          BACKSPACE=14, I=23, O=24, P=25, J=36, K=37, L=38, APOSTROPHE=40,
          M=50, COMMA=51, DOT=52, UP=103, LEFT=105, RIGHT=106, DOWN=108,
          LEFTMETA=125)

EDITS = {
    "plain_map": {
        KC["APOSTROPHE"]: lat("\\"),
    },
    "shift_map": {
        KC["APOSTROPHE"]: lat("|"),
        KC["COMMA"]: lat("/"),
        KC["DOT"]: lat("?"),
        KC["BACKSPACE"]: REMOVE,
    },
    # kcm "fn:" entries
    "altgr_map": {
        KC["K1"]: lat("~"), KC["K2"]: lat("`"), KC["K3"]: 0xf0a3,  # £
        KC["K4"]: U_EURO, KC["K5"]: lat("<"), KC["K6"]: lat(">"),
        KC["K7"]: lat("["), KC["K8"]: lat("]"), KC["K9"]: lat("{"),
        KC["K0"]: lat("}"),
        KC["I"]: lat("+"), KC["O"]: lat("-"), KC["P"]: lat("="),
        KC["J"]: lat("_"), KC["K"]: lat(";"), KC["L"]: lat('"'),
        KC["APOSTROPHE"]: lat(":"), KC["M"]: lat("'"),
        KC["UP"]: PRIOR, KC["LEFT"]: FIND, KC["DOWN"]: NEXT,
        KC["RIGHT"]: SELECT,
    },
}
# Fn must act as AltGr in every map it can be pressed or released from.
MAPS = ["plain_map", "shift_map", "altgr_map", "ctrl_map", "shift_ctrl_map",
        "alt_map", "ctrl_alt_map"]
for m in MAPS:
    EDITS.setdefault(m, {})[KC["LEFTMETA"]] = ALTGR


def main():
    s = BASE.read_text()
    for name, edits in EDITS.items():
        m = re.search(r"(" + name + r"\[NR_KEYS\] = \{)(.*?)(\};)", s, re.S)
        if not m:
            sys.exit(f"{name} not found in {BASE}")
        vals = re.findall(r"0x[0-9a-f]{4}", m.group(2))
        if len(vals) != 256:
            sys.exit(f"{name}: {len(vals)} entries, expected 256")
        for kc, v in edits.items():
            vals[kc] = f"0x{v:04x}"
        rows = ["\t" + ",\t".join(vals[i:i + 8]) + "," for i in range(0, 256, 8)]
        s = s[:m.start(2)] + "\n" + "\n".join(rows) + "\n" + s[m.end(2):]
    note = ("/* astro-linux618: entries changed by bin/make-defkeymap.py (Planet\n"
            " * Astro keyboard: Fn = KEY_LEFTMETA as AltGr, US keycap layer). */\n")
    s = s.replace("#include <linux/types.h>", note + "\n#include <linux/types.h>", 1)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(s)
    print(f"wrote {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
