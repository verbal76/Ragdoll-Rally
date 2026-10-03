#!/usr/bin/env python3
"""Compare a migrated-engine physics fingerprint against the Godot 4.4.1 reference.
Chaotic outcomes legitimately differ between solver versions, so this checks the
INVARIANTS that define the toy: launch speeds/gravity, joint integrity, sanity,
destruction activity and broad trajectory class (not exact end positions)."""
import json, sys
ref, new = (json.load(open(p)) for p in sys.argv[1:3])
bad = []
if ref["launch_consts"] != new["launch_consts"]:
    bad.append("launch constants/gravity changed: %s vs %s" % (ref["launch_consts"], new["launch_consts"]))
IGNORED = {"physics/3d/physics_interpolation/scene_traversal", "physics/jolt_physics_3d/simulation/areas_detect_static_bodies"}  # new/removed in 4.7
for k in sorted(set(ref["settings"]) | set(new["settings"])):
    if k not in IGNORED and ref["settings"].get(k) != new["settings"].get(k):
        bad.append("physics setting drifted: %s %r -> %r" % (k, ref["settings"].get(k), new["settings"].get(k)))
for a, b in zip(ref["shots"], new["shots"]):
    i = a["i"]
    if not b["sane"]: bad.append("shot %d: unstable ragdoll" % i)
    if abs(a["max_speed"] - b["max_speed"]) > 0.05: bad.append("shot %d: launch speed %.2f -> %.2f" % (i, a["max_speed"], b["max_speed"]))
    if b["max_limb_dist"] > max(a["max_limb_dist"] * 1.25, 0.9): bad.append("shot %d: joint stretch %.2f -> %.2f" % (i, a["max_limb_dist"], b["max_limb_dist"]))
    if abs(a["released"] - b["released"]) > max(4, 0.35 * a["released"]): bad.append("shot %d: destruction %d -> %d pieces" % (i, a["released"], b["released"]))
    dx = abs(a["torso_end"][0] - b["torso_end"][0]); dz = abs(a["torso_end"][2] - b["torso_end"][2])
    if dx > 8.0 or dz > 8.0: bad.append("shot %d: end position drifted dx=%.1f dz=%.1f" % (i, dx, dz))
    if b["frames"] >= 60 * 25: bad.append("shot %d: did not settle" % i)
print("PHYSICS COMPARISON:", "OK" if not bad else "VIOLATIONS")
for b in bad: print("  -", b)
for a, b in zip(ref["shots"], new["shots"]):
    print("  shot %d speed %.2f/%.2f limb %.2f/%.2f released %d/%d end %s -> %s" % (a["i"], a["max_speed"], b["max_speed"], a["max_limb_dist"], b["max_limb_dist"], a["released"], b["released"], a["torso_end"], b["torso_end"]))
sys.exit(1 if bad else 0)
