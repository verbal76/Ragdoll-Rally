# Physical test checklist (owner) — Launch G2 vs b2/b6

Install `ragdoll-rally-launch-g2-api36-5f6a122-b7.apk` (release `launch-g2-b7`) over the existing Launch (same package + signing). Keep b2 handy for comparison (uninstall first if you want a clean A/B).
1. Starts without crash; no Godot splash; Settings gear visible bottom-right; UI not clipped by cutouts/system bars (edge-to-edge is now on).
2. Same shots as before: full-power pull, flat shot into the house, high lob, left and right shots. Does it still feel like b2: launch speed, ragdoll floppiness, joint behavior, bounces/friction/landing, camera, scoring, destruction? Note anything that feels looser/stiffer/bouncier.
3. Frame rate during the biggest smash (the on-screen fps/phys readout).
4. Settings -> About: fields look right (Target SDK 36, compliant YES, generation g2, channel poc-g2, runtime-compat r2-...). Copy Diagnostics, paste somewhere.
5. Check for update: expect "no_update/manifest_unavailable" (nothing is published to poc-g2). App works offline (airplane mode).
6. Force-stop and relaunch; background/resume.
Report: anything that differs from b2/b6, especially physics feel.
Original: no APK this round (source not recoverable, see ORIGINAL_ARCHAEOLOGY.md).
