#!/usr/bin/env python3
"""Negative + positive tests for the coordinated build/release rules (tools/coordinated.py). No network, no Godot."""
import json, os, subprocess, sys, tempfile, unittest

sys.path.insert(0, os.path.dirname(__file__))
import coordinated as C

def g(cwd, *a):
    return subprocess.run(["git", "-C", cwd, *a], capture_output=True, text=True, check=True).stdout.strip()

class Repo(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        d = cls.d = cls.tmp.name
        g(d, "init", "-q", "-b", "main")
        g(d, "config", "user.email", "t@t"); g(d, "config", "user.name", "t")
        for i in range(2):
            open(os.path.join(d, "f"), "w").write(str(i)); g(d, "add", "."); g(d, "commit", "-qm", "c%d" % i)
        cls.good = g(d, "rev-parse", "HEAD")
        g(d, "checkout", "-q", "-b", "side")
        open(os.path.join(d, "s"), "w").write("x"); g(d, "add", "."); g(d, "commit", "-qm", "side")
        cls.side = g(d, "rev-parse", "HEAD")
        g(d, "checkout", "-q", "main")
        g(d, "tag", "v18", cls.good)
        g(d, "tag", "build-20", cls.good)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def v(self, platform="all", sha=None, build="21", dest="github_releases"):
        return C.validate_request(platform, sha if sha is not None else self.good, build, dest, "main", cwd=self.d)

    def test_valid_request(self):
        self.assertEqual(self.v(), [])
        self.assertEqual(self.v(platform="android", dest="local_only"), [])

    def test_rejects_malformed_or_unknown_sha(self):
        for bad in ("main", "v18", self.good[:7], self.good.upper(), "0" * 40, "", "g" * 40):
            self.assertTrue(self.v(sha=bad), "should reject %r" % bad)

    def test_rejects_sha_outside_authoritative_line(self):
        errs = self.v(sha=self.side)
        self.assertTrue(any("authoritative" in e for e in errs), errs)

    def test_rejects_reused_and_non_monotonic_numbers(self):
        self.assertTrue(self.v(build="18"))            # historical v18 tag
        self.assertTrue(self.v(build="20"))            # coordinated build-20 tag
        self.assertTrue(self.v(build="19"))            # below the highest published number (releases only increase)
        self.assertEqual(self.v(build="19", dest="local_only"), [])   # a local-only artifact consumes no number

    def test_rejects_bad_number_platform_destination(self):
        for b in ("0", "-1", "021", "abc", "", "1.5", "99999"):
            self.assertTrue(self.v(build=b), b)
        self.assertTrue(self.v(platform="mac"))
        self.assertTrue(self.v(dest="steam"))

    def test_names_follow_the_standard(self):
        n = C.names(19)
        self.assertEqual(n["release_title"], "Ragdoll Rally Build 19")
        self.assertEqual(n["android"], "Ragdoll Rally Build 19 APK.apk")
        self.assertEqual(n["windows"], "Ragdoll Rally Build 19 EXE.zip")
        self.assertEqual(n["linux"], "Ragdoll Rally Build 19 Linux.tar.gz")
        self.assertEqual(n["tag"], "build-19")
        self.assertIn("internal abc1234", C.names(19, "abc1234")["windows"])

class Manifest(unittest.TestCase):
    SHA = "a" * 40

    def make(self, d, platforms=("android", "windows", "linux"), sha=None, build=19, dirty=False):
        nm = C.names(build)
        for p in platforms:
            path = os.path.join(d, nm[p])
            open(path, "wb").write(("payload-" + p).encode())
            json.dump({"source_sha": sha or self.SHA, "build_number": build, "platform": C.PROV_NAME[p], "working_tree_dirty": dirty,
                       "artifact_sha256": C.sha256_file(path), "artifact_bytes": os.path.getsize(path), "engine": "Godot 4.7.1",
                       "build_config": "release", "built_at_utc": "2026-10-12T00:00:00Z"}, open(path + ".provenance.json", "w"))

    def test_happy_path_and_tamper_detection(self):
        with tempfile.TemporaryDirectory() as d:
            self.make(d)
            self.assertEqual(C.write_manifest(d, 19, self.SHA, ["android", "windows", "linux"], "local_only"), [])
            self.assertEqual(C.verify_dir(d), [])
            man = json.load(open(os.path.join(d, "build-manifest.json")))
            self.assertEqual((man["build_number"], man["source_sha"], len(man["artifacts"])), (19, self.SHA, 3))
            self.assertTrue(man["native_runtime_compat"].startswith("r2-"))
            open(os.path.join(d, C.names(19)["windows"]), "ab").write(b"x")              # tamper after the manifest
            self.assertTrue(C.verify_dir(d))

    def test_refuses_mixed_sources_numbers_dirty_and_missing(self):
        with tempfile.TemporaryDirectory() as d:
            self.make(d)
            pv = os.path.join(d, C.names(19)["linux"] + ".provenance.json")
            j = json.load(open(pv)); j["source_sha"] = "b" * 40; json.dump(j, open(pv, "w"))
            self.assertTrue(C.write_manifest(d, 19, self.SHA, ["android", "windows", "linux"], "local_only"))
        with tempfile.TemporaryDirectory() as d:
            self.make(d, build=18)                                                         # built for another number
            self.assertTrue(C.make_manifest(d, 19, self.SHA, ["android", "windows", "linux"], "local_only")[1])
        with tempfile.TemporaryDirectory() as d:
            self.make(d, dirty=True)
            self.assertTrue(C.make_manifest(d, 19, self.SHA, ["android", "windows", "linux"], "local_only")[1])
        with tempfile.TemporaryDirectory() as d:
            self.make(d, platforms=("android", "windows"))                                 # a partial set cannot pass as 'all'
            self.assertTrue(C.make_manifest(d, 19, self.SHA, ["android", "windows", "linux"], "local_only")[1])
            self.assertFalse(os.path.exists(os.path.join(d, "build-manifest.json")))

class VersionCode(unittest.TestCase):
    def test_version_code_is_above_every_shipped_apk_and_increases(self):
        shipped = [b["version_code"] for b in json.load(open(os.path.join(C.ROOT, "release", "native_baselines.json")))["baselines"]]
        self.assertTrue(C.version_code(19) > max(shipped), "Build 19 must install over v14-v18 (versionCode %d vs %d)" % (C.version_code(19), max(shipped)))
        self.assertEqual(C.version_code(19), 1019)
        self.assertTrue(all(C.version_code(n + 1) > C.version_code(n) for n in range(1, 500)))

class Workflows(unittest.TestCase):
    def test_policy_checker_passes(self):
        r = subprocess.run([sys.executable, os.path.join(C.ROOT, "tools", "check_policy.py")], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stdout[-800:])

if __name__ == "__main__":
    unittest.main(verbosity=1)
