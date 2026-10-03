# Launch: expanded playfield (v0.3.0-poc-expanded, native generation G2)

Owner findings (physical playtest): the slingshot is far stronger than the little village; left/right aiming had nothing to hit; the pull gesture ran out of screen; later: HUD text was clipped at the screen corners, the city must be dramatically wider and 3-4x deeper, targets must have different values, smashes should pay by how much damage you do, and a dead-centre bullseye gave no bonus.
Response: **the old power is untouched, the world is rebuilt around it, and a new "overdrive" band extends reach.**

## Aiming and power
- **Three-quarter opening camera**: raised and rotated 30 deg so "pull back" (world -X) points to the **lower-left** of the screen (Settings -> "Pull view" mirrors it to lower-right). The drag is decomposed in the camera-aligned (back, side) basis, so a diagonal pull works. Horizontal arc reaches 45 deg (lateral gain 1.0, was 0.7).
- **Unchanged**: for every pull up to the old full power (1.0): the speed curve (`lerp(9, 32, p^0.9)`), elevation `clamp(back,0.05,1)*1.6`, pull distance, gravity, air drag. Asserted in `tests/verify_expanded.gd`.
- **Overdrive** (new): pulling past the old full-power point (up to 1.45; the drag now has a long diagonal to use) raises the launch speed 32 -> 46 m/s and fades the ragdoll's air drag to zero (a power bar tick marks the old maximum; the bar turns purple and "OVERDRIVE!" shows). Needed because the old power flies only about 76 m (drag-limited), while the city is now up to ~190 m deep. Disable by setting `OVERDRIVE_MAX := 1.0` in `main.gd`.
- **Bug fixed (existed in G1/G2)**: a steep full pull put the ragdoll under the ground, so those launches went nowhere. The pouch is now clamped above ground.

## The city (about 240 m deep x 260 m wide, inside stone boundary walls)
- Original village unchanged in the middle. Hand-built clusters left/right/deep (fortress, barn yard, watch village, harbor, mills/silos, abbey, port town, gates, keep, **grand castle**), about 500 breakable pieces (frozen until struck) and ~100 props, plus ~190 decorative (non-breakable, immovable) cottages and trees drawn with MultiMesh (a few draw calls) and one static collider body.
- **23 targets** (value floats above each), each once per shot, all in addition to damage/flip/airtime/distance scoring:
| Region | Target | Pts |
|---|---|---|
| center | House Roof 100, House Window 150, Chimney 250, Needle Gap (thread the gate) 800, Keep Window 1200, Grand Gate 1600, Castle Window 1800, Castle Crown 2500 | |
| left-center | Old Tower 300, Fortress Window 400, Bell Tower 550, Old Mill 1000 | |
| right-center | Barrel Yard 300, Tall Chimney 450, Grain Silo 1000 | |
| far-left | Watchtower 900, Cliff Watch 1100, Monastery Spire 1500 | |
| far-right | Lighthouse 900, Harbor Crane 1100, Port Lighthouse 1500 | |
| landing rings | Bullseye (68, 14) 500, Far Bullseye (130, -14) 1000 | |
- **Bullseye pays by closeness**: the first ground contact inside a ring scores base x2 for dead centre, x1 inner, x0.5 middle, x0.3 outer ("DEAD CENTRE", camera shake + sound); resting inside a ring also counts (best result per ring, once).
- **Damage scoring**: each smashed piece pays `(5 + 3 x mass) x clamp(impact speed / 14, 0.6, 2.5)`, shown as a "SMASH xN +pts" popup; props pay by weight and speed.

## Camera, loop, performance
- Follow camera is relative to the ragdoll's smoothed travel direction, widens after the first impact, clamps inside the walls; ragdoll in view 100% of frames in all tested extreme shots, including overdrive.
- Flight ends when settled (0.6 s), after 2.5 s with nothing happening once on the ground, or at 13 s; tap during flight after 1.5 s skips to the result; reset restores pieces/props in place (about 7 ms).
- At most 90 released pieces stay simulated (older settled ones re-freeze).
- **HUD safe area**: all corner elements (stats, fps, RESET, gear, power bar) respect `DisplayServer.get_display_safe_area()` plus a minimum margin (40 x 30 canvas px).

## Verification
`tests/verify_expanded.gd` (power unchanged, overdrive curve, mapping, targets/regions/values, ring tiers, damage scaling, every target reachable with a drag-aware flight model, active cap, in-place reset, 10 extreme shots incl. overdrive: result in time, camera framing, bounded frame time, tap-to-skip, About formatting, safe margins), `verify.gd`, `verify_ota.gd`, physics regression (original village) vs Godot 4.4.1. Not verified: phone frame rate with this much content, touch feel of the overdrive pull, safe-area behaviour on the Pixel (only the minimum margin was exercised on desktop).

## Known limitations
- Reaching the far castle needs near-full overdrive (a long diagonal drag of about 350 px); distant labels overlap near gates.
- Decorative cottages/trees are immovable (they stop the ragdoll but do not break).
- Boundary walls are tall invisible colliders: a very high lob can bounce off thin air at the edge.
