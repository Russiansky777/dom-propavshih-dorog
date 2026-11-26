#!/usr/bin/env python3
"""Check the macOS build (Director 26.11: «Сделай версию для мак») before it goes out: the zip Godot writes for the
preset «macOS» must hold one .app with

  * Contents/Info.plist — bundle id, executable name, minimum macOS;
  * Contents/MacOS/<executable> — a universal Mach-O (x86_64 and arm64), executable bits kept in the zip;
  * Contents/Resources/<name>.pck — the game's pack, with GodotSteam named in it (tools/pck_list.py --need-steam);
  * Contents/Frameworks/libgodotsteam.macos.template_release.universal.dylib and libsteam_api.dylib — Steam;
  * Contents/_CodeSignature/CodeResources — the ad-hoc signature (without one an Apple Silicon Mac refuses to start it).

  python3 tools/check_mac_zip.py <DomPropavshihDorog_mac.zip>
  python3 tools/check_mac_zip.py --self-check     # zips built here: a good one passes, each broken one is caught
"""
import io
import os
import plistlib
import struct
import subprocess
import sys
import tempfile
import zipfile

FAT_MAGIC = 0xCAFEBABE
CPU_X86_64 = 0x01000007
CPU_ARM64 = 0x0100000C
STEAM_LIBS = ("libgodotsteam.macos.template_release.universal.dylib", "libsteam_api.dylib")
HERE = os.path.dirname(os.path.abspath(__file__))


def archs(head: bytes) -> list:
    """CPU types of a fat (universal) Mach-O from its first bytes; [] when it is not a fat binary."""
    if len(head) < 8 or struct.unpack(">I", head[:4])[0] != FAT_MAGIC:
        return []
    n = struct.unpack(">I", head[4:8])[0]
    out = []
    for i in range(n):
        off = 8 + 20 * i
        if off + 4 > len(head):
            break
        out.append(struct.unpack(">I", head[off:off + 4])[0])
    return out


def problems(path: str, pck_check=True) -> list:
    out = []
    with zipfile.ZipFile(path) as z:
        names = z.namelist()
        apps = sorted({n.split("/")[0] for n in names if n.split("/")[0].endswith(".app")})
        if len(apps) != 1:
            return ["в zip не одно .app, а %d: %s" % (len(apps), apps[:5])]
        app = apps[0]
        c = app + "/Contents/"
        if c + "Info.plist" not in names:
            return ["нет %sInfo.plist" % c]
        info = plistlib.loads(z.read(c + "Info.plist"))
        exe = info.get("CFBundleExecutable", "")
        bid = info.get("CFBundleIdentifier", "")
        print("[mac] %s: CFBundleIdentifier %s, CFBundleExecutable %s, LSMinimumSystemVersion %s" % (
            app, bid, exe, info.get("LSMinimumSystemVersion", info.get("LSMinimumSystemVersionByArchitecture", "?"))))
        if not bid or bid.startswith("com.example"):
            out.append("пустой или чужой CFBundleIdentifier: %r" % bid)
        binp = c + "MacOS/" + exe
        if not exe or binp not in names:
            out.append("нет исполняемого файла %s" % binp)
        else:
            zi = z.getinfo(binp)
            mode = (zi.external_attr >> 16) & 0o777
            if not mode & 0o111:
                out.append("у %s в zip нет права на запуск (режим %o)" % (binp, mode))
            with z.open(binp) as f:
                head = f.read(4096)
            a = archs(head)
            if CPU_X86_64 not in a or CPU_ARM64 not in a:
                out.append("%s не universal: архитектуры %s" % (binp, [hex(x) for x in a] or "не fat Mach-O"))
        pcks = [n for n in names if n.startswith(c + "Resources/") and n.endswith(".pck")]
        if len(pcks) != 1:
            out.append("в Contents/Resources не один .pck: %s" % pcks)
        elif pck_check:
            with tempfile.TemporaryDirectory() as td:
                tmp = os.path.join(td, "game.pck")
                with z.open(pcks[0]) as src, open(tmp, "wb") as dst:
                    while True:
                        b = src.read(1 << 20)
                        if not b:
                            break
                        dst.write(b)
                r = subprocess.run([sys.executable, "-I", os.path.join(HERE, "pck_list.py"), tmp, "--need-steam"],
                                   capture_output=True, text=True)
                tail = (r.stdout.strip().splitlines() or [""])[-1]
                print("[mac] %s: %s" % (pcks[0], tail))
                if r.returncode != 0:
                    out.append("pck_list --need-steam: %s %s" % (r.stdout[-400:], r.stderr[-400:]))
        for lib in STEAM_LIBS:
            if c + "Frameworks/" + lib not in names:
                out.append("нет Contents/Frameworks/%s (Steam)" % lib)
        if c + "_CodeSignature/CodeResources" not in names:
            out.append("нет подписи (Contents/_CodeSignature/CodeResources)")
    return out


def _fake(path, drop=(), thin=False, mode=0o755, bid="com.yahorzavatski.dompropavshihdorog"):
    app = "Dom propavshih dorog.app/Contents/"
    files = {
        app + "Info.plist": plistlib.dumps({"CFBundleExecutable": "Dom propavshih dorog", "CFBundleIdentifier": bid}),
        app + "MacOS/Dom propavshih dorog": (struct.pack(">II", 0xFEEDFACF, 0) if thin else
                                             struct.pack(">II", FAT_MAGIC, 2) + struct.pack(">IIIII", CPU_X86_64, 3, 4096, 10, 12)
                                             + struct.pack(">IIIII", CPU_ARM64, 0, 16384, 10, 14)),
        app + "Resources/Dom propavshih dorog.pck": b"not checked here",
        app + "Frameworks/" + STEAM_LIBS[0]: b"x",
        app + "Frameworks/" + STEAM_LIBS[1]: b"x",
        app + "_CodeSignature/CodeResources": b"x",
    }
    with zipfile.ZipFile(path, "w") as z:
        for n, data in files.items():
            if any(n.endswith(d) for d in drop):
                continue
            zi = zipfile.ZipInfo(n)
            zi.external_attr = ((mode if "/MacOS/" in n else 0o644) | 0o100000) << 16
            z.writestr(zi, data)


def self_check() -> int:
    bad = 0
    with tempfile.TemporaryDirectory() as td:
        cases = [("good", {}, True), ("no steam lib", {"drop": (STEAM_LIBS[1],)}, False),
                 ("no signature", {"drop": ("CodeResources",)}, False), ("arm64 missing", {"thin": True}, False),
                 ("not executable", {"mode": 0o644}, False), ("example bundle id", {"bid": "com.example.game"}, False)]
        for name, kw, ok in cases:
            p = os.path.join(td, name.replace(" ", "_") + ".zip")
            _fake(p, **kw)
            pr = problems(p, pck_check=False)
            if (not pr) != ok:
                bad += 1
                print("self-check FAIL: %s → %s" % (name, pr or "passed"))
    print("check_mac_zip: self-check %s" % ("OK" if not bad else "FAILED"))
    return 1 if bad else 0


def main(argv) -> int:
    if len(argv) > 1 and argv[1] == "--self-check":
        return self_check()
    if len(argv) != 2:
        print(__doc__)
        return 2
    if self_check() != 0:
        return 1
    pr = problems(argv[1])
    for p in pr:
        print("[mac] ОШИБКА: " + p)
    print("[mac] %s: %s" % (argv[1], "OK" if not pr else "%d ошибок" % len(pr)))
    return 1 if pr else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
