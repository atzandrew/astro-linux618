import re,sys
def addrs(p):
    t=open(p,errors='ignore').read()
    out={}
    for m in re.finditer(r'([\w,\-]+)@([0-9a-fA-F]+)\s*\{',t):
        a=int(m.group(2),16)
        if a>=0x100000: out.setdefault(a,m.group(1))
    return out
a=addrs(sys.argv[1]); b=addrs(sys.argv[2])
common=sorted(set(a)&set(b))
print("vendor nodes",len(a),"mainline nodes",len(b),"same addr",len(common))
for x in common: print(hex(x),a[x],'|',b[x])
print("--- mainline-only:")
for x in sorted(set(b)-set(a)): print(hex(x),b[x])
