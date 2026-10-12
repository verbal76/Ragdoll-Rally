# Known issues

## KI-1 Intermittent late-flight camera framing failure (UNRESOLVED, not harmless until proven)
- Symptom: `tests/verify_expanded.gd` sometimes fails `"<shot>: ragdoll in camera view NN% of frames"` (48-76%, threshold 90%) together with
  `"<shot>: camera stays above ground"` (camera y <= 1.5 at the end of the flight). Observed on hard left, flat fast and overdrive long shots.
- Frequency: 3 failures in 19 full-test runs (also with NO parallel load: 2 of those); 2 failures in 72 seeded shots (seed 11 hard left, seed 22 overdrive long).
- Reproduction: not deterministic. The same seed replayed gave different flight lengths and outcomes (seed 11: fail, then pass), so unseeded `randomize()` is not
  the only source; physics/frame timing varies too.
- Mechanism hints (unproven): the chase camera updates per rendered frame (`_process`, collision-safe resolution in `cam_safe.gd`) while the test samples the
  frustum per physics tick (`await physics_frame`, `Engine.max_fps = 0`); failures end with the camera low near the ground and the ragdoll out of the frustum.
  This may be a real late-flight framing edge case in the game, not only test instability.
- Not changed: camera, physics timing, thresholds and assertions are untouched. A separate, owner-authorized investigation is needed (e.g. frame-locked
  stepping in the test to separate harness from game behaviour, then a camera fix if the game is at fault).
