import re
t = open("/tmp/kwin-shaders.txt").read().split("\nshader: ")
n = 0
for blk in t:
    if not blk.startswith("MESA_SHADER_FRAGMENT"):
        continue
    n += 1
    nir = blk.split("\nimpl main")[0]
    unis = sorted(set(re.findall(r"decl_var uniform.*? (\w+)(?: \(|$)", nir, re.M)))
    pw = blk.count("fpow"); ex = blk.count("FEXP.f32"); lg = blk.count("FLOGD.f32")
    print("FS%d: fpow %d FEXP %d FLOGD %d | %s" % (n, pw, ex, lg, ", ".join(unis)[:260]))
