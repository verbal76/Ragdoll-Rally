# Launch: expanded playfield (v0.3.0-poc-expanded, native generation G2)

Owner finding (physical playtest): the slingshot is far stronger than the little village; left/right aiming had nothing to hit; the pull gesture ran out of screen. Response: **power unchanged, world rebuilt around it.**

## What changed
- **Power preserved**: `MIN_SPEED 9`, `MAX_SPEED 32`, curve `pow(power, 0.9)`, elevation `clamp(back,0.05,1)*1.6`, pull distance, gravity: unchanged (asserted in `tests/verify_expanded.gd`; full-power 45 deg range 104.5 m).
- **Three-quarter opening camera**: raised and rotated 30 deg so "pull back" (world -X) points to the **lower-left** of the screen (Settings -> "Pull view" mirrors it to lower-right). Drag is decomposed in the camera-aligned (back, side) basis, so a diagonal pull works and full power fits on screen from a mid-screen start (measured max drag 289 x 178 px for any aim in the arc). Lateral gain is 1.0 (was 0.7) so the horizontal arc reaches ~45 deg; far-left/right targets need it. Trajectory preview kept (30 dots, 4.8 s).
- **World**: playfield is now about 137 m deep x 160 m wide (x -25..112, z +-80) inside stone boundary walls with tall invisible colliders, so overshoots hit a wall instead of leaving. About 250 breakable pieces (frozen until struck), ~60 rigid props, static scenery. The original village is the central portion (unchanged).
- **13 targets** (value shown as a floating number; tier colors bronze/silver/gold/magenta), each scoring once per shot, additional to destruction/flip/airtime/distance scoring:
| Region | Target | Pts |
|---|---|---|
| center | House Roof | 100 |
| center | House Window | 150 |
| center | Chimney | 250 |
| center | Bullseye (landing) | 500 (+150 landing on the target ring) |
| center, far | Needle Gap (thread the gate) | 800 |
| center, far | Keep Window | 1200 |
| left-center | Old Tower toppled | 300 |
| left-center | Fortress Window | 400 |
| left-center | Bell Tower | 550 |
| right-center | Barrel Yard (heavy barrels) | 300 |
| right-center | Tall Chimney | 450 |
| far-left | Watchtower | 900 |
| far-right | Lighthouse | 900 |
- **Camera while flying**: follows the ragdoll's smoothed direction of travel (not a fixed +X offset), keeps standoff and height (wider after the first impact), clamps inside the walls. Verified in tests: ragdoll in view 100% of frames for hard left/right, long, high-lob, flat and diagonal shots.
- **Fast loop**: flight ends when settled (0.6 s), or after 2.5 s without impacts/releases once on the ground, or 11 s max; **tap during flight after 1.5 s skips to the result**; reset restores pieces/props in place (about 7 ms instead of about 100 ms for a rebuild; verified identical restoration). Flight timing now uses physics time (deterministic).
- **Bounded physics**: at most 90 released pieces stay simulated; older settled ones are re-frozen (they remain visible, no longer break).
- About: integers print without ".0"; settings now has a "Pull view" toggle (the Settings panel has three entries: Pull view, About, Close).

## Verification (CI + local)
`tests/verify_expanded.gd` (power, mapping, reachability of every target by ballistic search, regions, values, active cap, in-place reset, extreme shots, camera framing, stress shot, tap-to-skip, About formatting), `verify.gd`, `verify_ota.gd`, and the physics regression (legacy village) vs the Godot 4.4.1 reference. Not verified: real-phone frame rate with ~250 pieces, touch feel of the diagonal pull, label legibility.

## Known limitations
- The Keep Window/Needle Gap are near the practical max range (~95 m): they need near-full power with small yaw.
- Target markers are fixed-size labels and overlap when targets line up in the view.
- Boundary walls are tall invisible colliders: a very high lob can bounce off thin air near the edge.
- Elevation is still coupled to the back component of the pull (as in G1); lateral and back are independent.
