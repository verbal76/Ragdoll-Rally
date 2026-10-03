#!/usr/bin/env python3
"""Verify an APK ARTIFACT (not the config): identity, SDK levels, ABI/native-lib inventory,
16 KB page-size compatibility (ELF p_align + stored-.so zip alignment), signature, hash, size.
Exit code 1 if any requested expectation or the 16 KB check fails.
"""
import argparse, hashlib, json, os, re, struct, subprocess, sys, zipfile

def sh(cmd):
    return subprocess.run(cmd, capture_output=True, text=True).stdout

def find_tool(name):
    home = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT") or ""
    cands = sorted([os.path.join(home, "build-tools", v, name) for v in os.listdir(os.path.join(home, "build-tools"))]) if home and os.path.isdir(os.path.join(home, "build-tools")) else []
    cands = [c for c in cands if os.path.exists(c)]
    return cands[-1] if cands else None

def elf_loads(data):
    if data[:4] != b"\x7fELF" or data[4] != 2:       # 64-bit only (arm64-v8a / x86_64)
        return None
    phoff, = struct.unpack_from("<Q", data, 0x20)
    phentsize, phnum = struct.unpack_from("<HH", data, 0x36)
    loads = []
    for i in range(phnum):
        off = phoff + i * phentsize
        p_type, = struct.unpack_from("<I", data, off)
        if p_type == 1:
            p_align, = struct.unpack_from("<Q", data, off + 48)
            loads.append(p_align)
    return loads

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("apk")
    ap.add_argument("--package"); ap.add_argument("--version-name"); ap.add_argument("--version-code", type=int)
    ap.add_argument("--min-sdk", type=int); ap.add_argument("--target-sdk", type=int)
    ap.add_argument("--cert-sha256"); ap.add_argument("--json-out")
    a = ap.parse_args()
    ok = True
    rep = {"file": os.path.basename(a.apk), "size": os.path.getsize(a.apk), "sha256": hashlib.sha256(open(a.apk, "rb").read()).hexdigest()}
    aapt = find_tool("aapt")
    if aapt:
        b = sh([aapt, "dump", "badging", a.apk])
        g = lambda pat: (re.search(pat, b) or [None, None])[1]
        rep.update(package=g(r"package: name='([^']+)'"), version_name=g(r"versionName='([^']*)'"), version_code=int(g(r"versionCode='(\d+)'") or 0),
                   min_sdk=int(g(r"\nsdkVersion:'(\d+)'") or 0), target_sdk=int(g(r"targetSdkVersion:'(\d+)'") or 0),
                   permissions=sorted(set(re.findall(r"uses-permission: name='([^']+)'", b))),
                   native_code=g(r"native-code: ([^\n]+)"))
    elif True:
        try:
            from pyaxmlparser import APK   # local fallback when aapt is not installed
            x = APK(a.apk)
            rep.update(package=x.package, version_name=x.version_name, version_code=int(x.version_code or 0),
                       min_sdk=int(x.get_min_sdk_version() or 0), target_sdk=int(x.get_target_sdk_version() or 0),
                       permissions=sorted(x.get_permissions()), native_code=None)
        except Exception as e:
            rep["badging_error"] = str(e)
    z = zipfile.ZipFile(a.apk)
    libs = []
    for zi in z.infolist():
        if zi.filename.startswith("lib/") and zi.filename.endswith(".so"):
            data = z.read(zi)
            loads = elf_loads(data)
            with open(a.apk, "rb") as f:
                f.seek(zi.header_offset)
                hdr = f.read(30)
            nlen, elen = struct.unpack_from("<HH", hdr, 26)
            data_off = zi.header_offset + 30 + nlen + elen
            libs.append({"name": zi.filename, "size": zi.file_size, "stored": zi.compress_type == 0, "elf_load_aligns": loads,
                         "elf_16k": bool(loads) and all(x >= 16384 for x in loads), "zip_data_offset_mod_16k": data_off % 16384})
    rep["native_libs"] = libs
    rep["abis"] = sorted({l["name"].split("/")[1] for l in libs})
    elf_ok = all(l["elf_16k"] for l in libs)
    zip_ok = all(l["stored"] and l["zip_data_offset_mod_16k"] == 0 for l in libs)
    za = find_tool("zipalign")
    if za:
        r = subprocess.run([za, "-c", "-P", "16", "4", a.apk], capture_output=True, text=True)
        rep["zipalign_P16_ok"] = (r.returncode == 0)
    rep["page16k"] = {"elf_ok": elf_ok, "zip_ok": zip_ok, "compliant": elf_ok and zip_ok and rep.get("zipalign_P16_ok", True)}
    sg = find_tool("apksigner")
    if sg:
        o = sh([sg, "verify", "--print-certs", a.apk])
        m = re.search(r"certificate SHA-256 digest: ([0-9a-f]+)", o)
        rep["cert_sha256"] = m.group(1) if m else None
        rep["signature_verified"] = "DOES NOT VERIFY" not in o and bool(m)
    for key, want in [("package", a.package), ("version_name", a.version_name), ("version_code", a.version_code), ("min_sdk", a.min_sdk), ("target_sdk", a.target_sdk)]:
        if want is not None and rep.get(key) != want:
            print("MISMATCH %s: expected %r got %r" % (key, want, rep.get(key))); ok = False
    if a.cert_sha256 and rep.get("cert_sha256") and rep["cert_sha256"].lower() != a.cert_sha256.lower().replace(":", ""):
        print("MISMATCH signing certificate"); ok = False
    if not rep["page16k"]["compliant"]:
        print("16 KB CHECK FAILED"); ok = False
    print(json.dumps(rep, indent=2))
    if a.json_out:
        json.dump(rep, open(a.json_out, "w"), indent=2)
    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
