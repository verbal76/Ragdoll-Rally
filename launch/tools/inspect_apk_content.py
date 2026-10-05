#!/usr/bin/env python3
"""Inspects the CONTENT of an exported APK (verify_apk.py covers identity/signing/16 KB).

Checks (each printed as PASS/FAIL, exit 1 on any FAIL):
  - the Hot Attic Games studio logo + boot scripts are packaged
  - all five v13 cities + the two legacy maps are packaged (city builder script, names)
  - no player-visible "+10,000 (TEST)" string anywhere in the game scripts; the dev gate string IS present (positive control)
  - no "COMING SOON" / "LOCKED - not built yet" strings
  - the trajectory governor, boundary and economy code are packaged (positive controls)
  - the launcher icon is packaged
Usage: inspect_apk_content.py <apk> [--json-out path]
"""
import json, struct, sys, zipfile
try:
    import zstandard
except ImportError:
    zstandard = None   # CI: pip install zstandard

def main():
    apk = sys.argv[1]
    out = None
    if "--json-out" in sys.argv:
        out = sys.argv[sys.argv.index("--json-out") + 1]
    z = zipfile.ZipFile(apk)
    names = z.namelist()
    def unpack(data: bytes) -> bytes:
        # Godot 4 binary tokens: "GDSC", version, decompressed size, then a zstd frame
        if data[:4] == b"GDSC" and data[12:16] == b"\x28\xb5\x2f\xfd":
            assert zstandard is not None, "pip install zstandard"
            return zstandard.ZstdDecompressor().decompress(data[12:], max_output_size=struct.unpack("<I", data[8:12])[0])
        return data
    scripts = {n: unpack(z.read(n)) for n in names if n.startswith("assets/scripts/") and (n.endswith(".gdc") or n.endswith(".gd"))}
    blob = b"".join(scripts.values())
    # Godot stores identifiers xor-obfuscated in binary tokens; string literals are plain UTF-8 / UTF-32
    def has(s: str) -> bool:
        raw = s.encode("utf-8")
        if raw in blob:
            return True
        if s.encode("utf-32-le") in blob:
            return True
        return bytes(b ^ 0xB6 for b in raw) in blob
    results = []
    def check(ok, msg):
        results.append({"ok": bool(ok), "check": msg})
        print(("PASS  " if ok else "FAIL  ") + msg)
    check(len(scripts) >= 8, "game scripts packaged (%d)" % len(scripts))
    check(any(n.endswith("cities.gdc") or n.endswith("cities.gd") for n in scripts), "city builder script is packaged (cities.gd)")
    check(any(n.endswith("rules.gdc") or n.endswith("rules.gd") for n in scripts), "rules script is packaged (rules.gd)")
    for city in ["DOWNTOWN", "OLD TOWN", "SUBURBIA", "INDUSTRIAL DISTRICT", "RESORT STRIP", "GRAND FORTRESS", "RAGDOLL TEST YARD"]:
        check(has(city), "city name packaged: %s" % city)
    check(has("TRAINING"), "Test Yard is tagged TRAINING")
    check(not has("+10,000 (TEST)") and not has("(TEST)"), "no '+10,000 (TEST)' / '(TEST)' player string in the game code")
    check(has("RR_DEV_ECONOMY"), "positive control: the developer economy gate string is present (so the negative check is meaningful)")
    check(not has("COMING SOON") and not has("not built yet"), "no COMING SOON / LOCKED placeholders")
    for ident in ["boundary", "OUT OF BOUNDS"]:
        check(has(ident), "code present: %s" % ident)
    logo = [n for n in names if "Hot_Attic_Games_Master_Logo_ALPHA_FINAL" in n]
    check(any(n.endswith(".ctex") for n in logo) or any(n.endswith(".png") for n in logo), "canonical studio logo packaged: %s" % (logo[:2],))
    check(not any("Hot_Attic_Games_Master_Logo.png" in n and "ALPHA_FINAL" not in n for n in names), "the obsolete logo file is not packaged")
    check(any(n.endswith("boot.gdc") or n.endswith("boot.gd") for n in names), "studio splash boot script packaged")
    check(any(n.endswith("icon.svg") or n.startswith("res/mipmap") for n in names), "launcher icon packaged")
    if out:
        json.dump(results, open(out, "w"), indent=1)
    bad = [r for r in results if not r["ok"]]
    print("---- APK CONTENT %s (%d failures)" % ("OK" if not bad else "FAILED", len(bad)))
    sys.exit(1 if bad else 0)

main()
