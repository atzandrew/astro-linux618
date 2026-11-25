#!/usr/bin/env python3
"""Pack an Android boot image, header v2, for the Astro Slide's LK.

Layout and defaults copy the stock boot_a (docs/p0-findings.md, dumped
2026-11-25): page 2048, kernel (Image.gz) at 0x40080000, ramdisk at
0x47c80000, tags and DTB at 0x4bc80000, no second stage, no recovery
dtbo, os_version 0x16000173. The DTB goes in the v2 dtb section wrapped
in an Android DT table (magic 0xd7b7ab1e, one entry, id 0 rev 0, page
size 2048, version 0), exactly as stock; LK picks entry androidboot.dtb_idx=0.

Self-check: bin/mkbootimg.py --verify-stock <stock boot.img> repacks the
stock image from its own parts and must reproduce it byte for byte.
"""
import argparse, hashlib, struct, sys

PAGE = 2048
MAGIC_DT_TABLE = 0xD7B7AB1E
# LK windows (mblock reservations in the LK log): kernel_addr_mb 0x7c00000,
# ramdisk_addr_mb 0x4000000, dtb_kernel_addr_mb 0x80000.
MAX_KERNEL = 0x7C00000
MAX_RAMDISK = 0x4000000
MAX_DTB = 0x80000


def pad(n, page=PAGE):
    return (n + page - 1) // page * page


def dt_table(dtb):
    """One-entry DT table, field for field as the stock dtb section."""
    hdr_size, ent_size, n = 0x20, 0x20, 1
    off = hdr_size + n * ent_size
    total = off + len(dtb)
    hdr = struct.pack(">8I", MAGIC_DT_TABLE, total, hdr_size, ent_size, n,
                      hdr_size, PAGE, 0)
    ent = struct.pack(">8I", len(dtb), off, 0, 0, 0, 0, 0, 0)
    return hdr + ent + dtb


def pack(kernel, ramdisk, dtb_section, cmdline, os_version=0x16000173,
         kernel_addr=0x40080000, ramdisk_addr=0x47C80000,
         tags_addr=0x4BC80000, dtb_addr=0x4BC80000, extra_cmdline=b""):
    if len(cmdline) > 511 or len(extra_cmdline) > 1023:
        sys.exit(f"cmdline {len(cmdline)}/511, extra {len(extra_cmdline)}/1023 bytes")
    sha = hashlib.sha1()
    for blob in (kernel, ramdisk, b"", b"", dtb_section):
        sha.update(blob)
        sha.update(struct.pack("<I", len(blob)))
    hdr = struct.pack("<8s10I16s512s32s1024sIQII Q".replace(" ", ""),
                      b"ANDROID!", len(kernel), kernel_addr, len(ramdisk),
                      ramdisk_addr, 0, 0, tags_addr, PAGE, 2, os_version,
                      b"", cmdline, sha.digest(), extra_cmdline,
                      0, 0, 1660, len(dtb_section), dtb_addr)
    assert len(hdr) == 1660, len(hdr)
    out = bytearray(hdr.ljust(PAGE, b"\0"))
    for blob in (kernel, ramdisk, dtb_section):
        out += blob.ljust(pad(len(blob)), b"\0")
    return bytes(out)


def split_stock(img):
    f = struct.unpack_from("<8s10I16s512s32s1024sIQII Q".replace(" ", ""), img, 0)
    ks, ka, rs, ra, ps, ver, osv = f[1], f[2], f[3], f[4], f[8], f[9], f[10]
    assert f[0] == b"ANDROID!" and ver == 2 and ps == PAGE
    k = img[ps:ps + ks]
    r = img[ps + pad(ks):ps + pad(ks) + rs]
    o = ps + pad(ks) + pad(rs)
    d = img[o:o + f[18]]
    return dict(kernel=k, ramdisk=r, dtb_section=d, cmdline=f[12].rstrip(b"\0"),
                os_version=osv, kernel_addr=ka, ramdisk_addr=ra, tags_addr=f[7],
                dtb_addr=f[19], extra_cmdline=f[14].rstrip(b"\0"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--kernel")
    ap.add_argument("--ramdisk")
    ap.add_argument("--dtb", help="flat DTB; wrapped in a one-entry DT table")
    ap.add_argument("--cmdline", default="")
    ap.add_argument("-o", "--output")
    ap.add_argument("--verify-stock", metavar="BOOT_IMG")
    a = ap.parse_args()

    if a.verify_stock:
        img = open(a.verify_stock, "rb").read()
        parts = split_stock(img)
        new = pack(**parts)
        ok = img[:len(new)] == new
        footer = img.find(b"AVB0", len(new))
        print(f"repack of {a.verify_stock}: {'IDENTICAL' if ok else 'DIFFERENT'} "
              f"({len(new)} bytes used); "
              + (f"stock AVB footer at {footer:#x} (not written by this tool)"
                 if footer >= 0 else "no AVB footer"))
        sys.exit(0 if ok else 1)

    if not (a.kernel and a.ramdisk and a.dtb and a.output):
        ap.error("--kernel, --ramdisk, --dtb and -o are required")
    k = open(a.kernel, "rb").read()
    r = open(a.ramdisk, "rb").read()
    d = open(a.dtb, "rb").read()
    cmd = a.cmdline.encode()
    if b"bootopt=" not in cmd:
        sys.exit("cmdline lacks bootopt=: LK parses it from this field (Gemini lesson)")
    if k[:2] != b"\x1f\x8b":
        sys.exit("kernel is not gzip (stock LK gets Image.gz)")
    if d[:4] != b"\xd0\x0d\xfe\xed":
        sys.exit("--dtb is not a flat DTB")
    if len(r) > MAX_RAMDISK or len(d) > MAX_DTB:
        sys.exit(f"ramdisk {len(r):#x} (max {MAX_RAMDISK:#x}) / dtb {len(d):#x} (max {MAX_DTB:#x})")
    # The window that matters for the kernel is the decompressed Image.
    import gzip, zlib
    unz = len(gzip.decompress(k))
    if unz > MAX_KERNEL:
        sys.exit(f"decompressed kernel {unz:#x} exceeds LK's window {MAX_KERNEL:#x}")
    open(a.output, "wb").write(pack(k, r, dt_table(d), cmd))


if __name__ == "__main__":
    main()
