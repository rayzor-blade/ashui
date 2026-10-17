"""Drops the name section of a wasm module, which holds function names for debugging.

    python3 strip_names.py in.wasm out.wasm

Only that section goes: a side module's dylink.0 must stay, which wasm-strip would remove.
"""
import sys
d=open(sys.argv[1],'rb').read()
def uleb(i):
    r=0;s=0
    while True:
        b=d[i];i+=1;r|=(b&0x7f)<<s;s+=7
        if not b&0x80:return r,i
out=bytearray(d[:8]);i=8;dropped=0
while i<len(d):
    start=i;sid=d[i];i+=1;size,j=uleb(i);end=j+size
    if sid==0:
        l,k=uleb(j)
        if d[k:k+l]==b'name':
            dropped+=end-start;i=end;continue
    out+=d[start:end];i=end
open(sys.argv[2],'wb').write(out)
print(f'{sys.argv[1]}: {len(d):,} -> {len(out):,} (dropped {dropped:,})')
