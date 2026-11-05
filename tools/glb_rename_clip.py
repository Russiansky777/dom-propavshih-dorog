#!/usr/bin/env python3
"""Имя клипа в GLB без Blender (у движений Meshy Text to Motion клип всегда «retarget_clip» — при сборке нескольких
в один файл имена столкнулись бы): переписывает JSON-блок GLB.
  python3 -I tools/glb_rename_clip.py <in.glb> <out.glb> <новое имя> [старое имя]"""
import json
import struct
import sys

src, dst, new = sys.argv[1:4]
old = sys.argv[4] if len(sys.argv) > 4 else None
b = open(src, "rb").read()
magic, ver, _ = struct.unpack("<4sII", b[:12])
jl, jt = struct.unpack("<II", b[12:20])
j = json.loads(b[20:20 + jl])
rest = b[20 + jl:]
n = 0
for a in j.get("animations", []):
    if old is None or a.get("name") == old:
        a["name"] = new
        n += 1
if n != 1:
    sys.exit(f"переименовано {n} клипов (нужен ровно один): {[a.get('name') for a in j.get('animations', [])]}")
js = json.dumps(j, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
js += b" " * ((4 - len(js) % 4) % 4)
out = struct.pack("<II", len(js), jt) + js + rest
open(dst, "wb").write(struct.pack("<4sII", magic, ver, 12 + len(out)) + out)
print(f"{dst}: клип → {new}")
