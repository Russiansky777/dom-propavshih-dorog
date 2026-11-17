#!/usr/bin/env python3
"""List the files of a Godot 4 pack — a .pck or a pack embedded in an exported .exe — and check what Steam needs
(review 17.11): GodotSteam loads only if the pack carries res://.godot/extension_list.cfg naming
res://addons/godotsteam/godotsteam.gdextension, and the .gdextension itself. Without them the exe runs, quietly,
without Steam — no overlay, no achievements — and nothing on screen says so.

  python3 tools/pck_list.py <file.pck|file.exe>                 # the list
  python3 tools/pck_list.py <file> --need-steam                 # exit 1 if the Steam files are missing
  python3 tools/pck_list.py --self-check                        # a pack built here, with and without them

Format (core/io/file_access_pack.cpp, pack format 2 and 3): "GDPC", version, major, minor, patch, flags, file_base
(u64), [v3: dir_offset (u64)], 16 reserved u32, then (v3: at dir_offset) the file count and per file: path length,
path, offset (u64), size (u64), md5 (16), flags (u32). An embedded pack ends the exe with its size (u64) and "GDPC".
"""
import io
import struct
import sys

MAGIC = 0x43504447  # "GDPC"
PACK_DIR_ENCRYPTED = 1
PACK_REL_FILEBASE = 2


def _u32(f):
    return struct.unpack("<I", f.read(4))[0]


def _u64(f):
    return struct.unpack("<Q", f.read(8))[0]


def open_pack(f):
    """Seek to the pack header; return its start position."""
    f.seek(0)
    if _u32(f) == MAGIC:
        return 0
    f.seek(-4, io.SEEK_END)
    if _u32(f) != MAGIC:
        raise ValueError("no Godot pack here (no GDPC at the start or at the end)")
    f.seek(-12, io.SEEK_END)
    size = _u64(f)
    f.seek(-12 - size, io.SEEK_END)
    start = f.tell()
    if _u32(f) != MAGIC:
        raise ValueError("an embedded pack's header is not where its size says")
    return start


def read_dir(f):
    start = open_pack(f)
    f.seek(start + 4)
    version = _u32(f)
    major, minor, _patch = _u32(f), _u32(f), _u32(f)
    flags = _u32(f)
    file_base = _u64(f)
    dir_offset = _u64(f) if version >= 3 else 0
    if flags & PACK_DIR_ENCRYPTED:
        raise ValueError("the pack's directory is encrypted")
    if version >= 3:
        f.seek(start + dir_offset)
    else:
        f.read(16 * 4)
    count = _u32(f)
    if count > 1_000_000:
        raise ValueError("implausible file count %d (pack format %d)" % (count, version))
    files = {}
    for _ in range(count):
        n = _u32(f)
        path = f.read(n).split(b"\0")[0].decode("utf-8")
        ofs, size = _u64(f), _u64(f)
        f.read(16)
        _flags = _u32(f)
        base = file_base + (start if flags & PACK_REL_FILEBASE else 0)
        files[path if path.startswith("res://") else "res://" + path] = (base + ofs, size)
    return {"version": version, "engine": "%d.%d" % (major, minor), "files": files}


def read_file(f, entry):
    f.seek(entry[0])
    return f.read(entry[1])


def steam_problems(path):
    out = []
    with open(path, "rb") as f:
        d = read_dir(f)
        files = d["files"]
        el = files.get("res://.godot/extension_list.cfg")
        if el is None:
            out.append("нет res://.godot/extension_list.cfg — движок не загрузит ни одного расширения")
        else:
            text = read_file(f, el).decode("utf-8", "replace")
            if "res://addons/godotsteam/godotsteam.gdextension" not in text:
                out.append("extension_list.cfg не называет godotsteam.gdextension: %r" % text[:200])
        if "res://addons/godotsteam/godotsteam.gdextension" not in files:
            out.append("нет res://addons/godotsteam/godotsteam.gdextension")
    return out, d


def self_check():
    """Two packs written here in the same format: with the Steam files — no problems; without — both caught."""
    import os
    import tempfile
    bad = []

    def write(files):
        body = b""
        entries = []
        for p, data in files.items():
            entries.append((p, len(body), len(data)))
            body += data
        hdr = struct.pack("<IIIIII", MAGIC, 2, 4, 7, 2, PACK_REL_FILEBASE)
        dir_bytes = struct.pack("<I", len(entries))
        for p, ofs, size in entries:
            pb = p.encode()
            dir_bytes += struct.pack("<I", len(pb)) + pb + struct.pack("<QQ", ofs, size) + b"\0" * 16 + struct.pack("<I", 0)
        file_base = len(hdr) + 8 + 64 + len(dir_bytes)
        pack = hdr + struct.pack("<Q", file_base) + b"\0" * 64 + dir_bytes + body
        exe = b"MZ fake exe" + pack + struct.pack("<Q", len(pack)) + struct.pack("<I", MAGIC)
        fd, path = tempfile.mkstemp(suffix=".exe")
        os.write(fd, exe)
        os.close(fd)
        return path

    good = write({"res://.godot/extension_list.cfg": b"res://addons/godotsteam/godotsteam.gdextension\n",
                  "res://addons/godotsteam/godotsteam.gdextension": b"[configuration]\n", "res://project.binary": b"x"})
    none = write({"res://project.binary": b"x"})
    try:
        p, _ = steam_problems(good)
        if p:
            bad.append("самопроверка: пакет со Steam признан плохим: %s" % p)
        p, _ = steam_problems(none)
        if len(p) < 2:
            bad.append("самопроверка: пакет без Steam не пойман: %s" % p)
    finally:
        os.remove(good)
        os.remove(none)
    return bad


def main():
    if "--self-check" in sys.argv:
        bad = self_check()
        for b in bad:
            print("[pck] " + b)
        print("[pck] pck_list --self-check: %s" % ("OK" if not bad else "FAIL"))
        return 1 if bad else 0
    path = sys.argv[1]
    if "--need-steam" in sys.argv:
        problems, d = steam_problems(path)
        for p in problems:
            print("[pck] %s: %s" % (path, p))
        print("[pck] %s: пакет формата %d (Godot %s), файлов %d; Steam: %s" % (
            path, d["version"], d["engine"], len(d["files"]), "OK" if not problems else "НЕТ"))
        return 1 if problems else 0
    with open(path, "rb") as f:
        d = read_dir(f)
    for p, (ofs, size) in sorted(d["files"].items()):
        print("%10d  %s" % (size, p))
    print("[pck] формат %d, Godot %s, файлов %d" % (d["version"], d["engine"], len(d["files"])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
