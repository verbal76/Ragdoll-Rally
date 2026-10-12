#!/usr/bin/env python3
"""Offline tests for the OTA publisher / native-release gates (needs the repository history, no network, no Godot).
  python3 launch/tools/test_ota_tools.py
Reproduces the v14-v18 incident: the live poc-g2 manifest (seq 3, faeb937) must block native releases that it would downgrade,
and the publisher must refuse older payloads and non-increasing sequences."""
import json, os, subprocess, sys, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.join(HERE, "ota_tools.py")
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
FIX = os.path.join(HERE, "..", "tests", "fixtures", "ota_manifest_poc-g2_seq3_faeb937.json")

def run(*a):
    r = subprocess.run([sys.executable, TOOLS, *a], capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr

def epoch(rev):
    return int(subprocess.run(["git", "-C", REPO, "rev-list", "--count", rev], capture_output=True, text=True).stdout.strip())

def write(d, name, obj):
    p = os.path.join(d, name)
    json.dump(obj, open(p, "w"))
    return p

class Gates(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.live = json.load(open(FIX))
        self.v18 = subprocess.run(["git", "-C", REPO, "rev-parse", "v18^{commit}"], capture_output=True, text=True).stdout.strip()

    def man(self, **over):
        m = {"id": "poc-g2-4-test", "name": "t", "sequence": 4, "channel": "poc-g2", "runtime_compat": self.live["runtime_compat"],
             "url": "https://example.invalid/x.pck", "sha256": "0" * 64, "size": 1, "source_sha": self.v18, "source_epoch": epoch(self.v18),
             "published_at": "2026-10-12T00:00:00Z"}
        m.update(over)
        return m

    # --- native gate: the incident
    def test_native_gate_blocks_a_native_build_the_old_channel_would_downgrade(self):
        live = write(self.tmp, "live.json", self.live)
        code, out = run("native-gate", "--live", live, "--epoch", str(epoch("v18")), "--compat", self.live["runtime_compat"])
        self.assertEqual(code, 1, out)
        self.assertIn("DOWNGRADE", out)

    def test_native_gate_passes_for_the_build_the_manifest_was_made_for(self):
        live = write(self.tmp, "live.json", self.live)
        code, out = run("native-gate", "--live", live, "--epoch", str(epoch("v14")), "--compat", self.live["runtime_compat"])
        self.assertEqual(code, 0, out)       # v14 predates faeb937: the OTA was a legitimate upgrade for it

    def test_native_gate_passes_after_a_baseline_equal_ota(self):
        live = write(self.tmp, "live.json", self.man())
        code, out = run("native-gate", "--live", live, "--epoch", str(epoch("v18")), "--compat", self.live["runtime_compat"])
        self.assertEqual(code, 0, out)

    def test_native_gate_ignores_a_manifest_for_another_runtime(self):
        live = write(self.tmp, "live.json", self.live)
        code, out = run("native-gate", "--live", live, "--epoch", "999", "--compat", "r3-newruntime")
        self.assertEqual(code, 0, out)

    def test_native_gate_passes_when_no_channel_exists(self):
        code, out = run("native-gate", "--live", os.path.join(self.tmp, "none.json"), "--epoch", "999", "--compat", "r3-x")
        self.assertEqual(code, 0, out)

    # --- publisher guard
    def test_guard_refuses_the_old_payload_with_a_higher_sequence(self):
        old = self.man(sequence=9, source_sha=self.live["source_sha"], source_epoch=epoch("faeb937"))
        code, out = run("guard", "--manifest", write(self.tmp, "m.json", old), "--live", write(self.tmp, "l.json", self.live))
        self.assertEqual(code, 1, out)
        self.assertIn("OLDER than native baseline", out)

    def test_guard_accepts_the_baseline_equal_payload(self):
        code, out = run("guard", "--manifest", write(self.tmp, "m.json", self.man()), "--live", write(self.tmp, "l.json", self.live))
        self.assertEqual(code, 0, out)

    def test_guard_requires_a_greater_sequence(self):
        code, out = run("guard", "--manifest", write(self.tmp, "m.json", self.man(sequence=3)), "--live", write(self.tmp, "l.json", self.live))
        self.assertEqual(code, 1, out)
        self.assertIn("not greater", out)

    def test_guard_requires_source_provenance(self):
        m = self.man()
        del m["source_epoch"]
        code, out = run("guard", "--manifest", write(self.tmp, "m.json", m), "--live", write(self.tmp, "l.json", self.live))
        self.assertEqual(code, 1, out)

    def test_guard_rollback_needs_explicit_authorization(self):
        old = self.man(sequence=9, source_sha=self.live["source_sha"], source_epoch=epoch("faeb937"))
        self.assertEqual(run("guard", "--manifest", write(self.tmp, "m.json", old), "--live", write(self.tmp, "l.json", self.live))[0], 1)
        old["rollback"] = {"authorized": True, "reason": "owner approved return to faeb937", "floor_epoch": old["source_epoch"]}
        code, out = run("guard", "--manifest", write(self.tmp, "m2.json", old), "--live", write(self.tmp, "l.json", self.live))
        self.assertEqual(code, 0, out)

    def test_guard_rejects_a_source_outside_the_authoritative_history(self):
        code, out = run("guard", "--manifest", write(self.tmp, "m.json", self.man(source_sha="1" * 40)), "--live", write(self.tmp, "l.json", self.live))
        self.assertEqual(code, 1, out)

    # --- tooling
    def test_baselines_are_consistent_with_the_tags(self):
        b = json.load(open(os.path.join(REPO, "release", "native_baselines.json")))["baselines"]
        self.assertEqual([x["tag"] for x in b][:5], ["v14", "v15", "v16", "v17", "v18"])
        for x in b:
            self.assertEqual(x["source_epoch"], epoch(x["tag"]), x["tag"])
        self.assertEqual({x["runtime_compat"] for x in b[:5]}, {self.live["runtime_compat"]})

    def test_new_build_tags_count_as_native_baselines(self):
        """Coordinated builds are tagged build-<N>; the OTA guards must treat them exactly like the historical v<N> releases."""
        from unittest import mock
        sys.path.insert(0, HERE)
        import ota_tools as ota
        fake = {("tag", "-l", "v[0-9]*", "build-[0-9]*"): "v13\nv18\nbuild-19\nbuild-x\nbuild-20"}
        def g(*a, repo=None):
            return fake.get(a, "sha-" + a[1].split("^")[0] if a[0] == "rev-parse" else "")
        with mock.patch.object(ota, "git", g), mock.patch.object(ota, "fingerprint", lambda rev=None, root=None: "r2-fake"), \
                mock.patch.object(ota, "epoch_of", lambda rev="HEAD", repo=None: 100 if rev == "sha-build-19" else 90):
            b = ota.computed_baselines()
        self.assertEqual([x["tag"] for x in b], ["v18", "build-19", "build-20"])
        self.assertEqual([x["version"] for x in b], [18, 19, 20])
        self.assertEqual([x["channel"] for x in b], ["poc-g2", "g3", "g3"])
        self.assertEqual(b[1]["source_epoch"], 100)

if __name__ == "__main__":
    unittest.main(verbosity=2)
