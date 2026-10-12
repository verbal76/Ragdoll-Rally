# v14 candidate: hillside cities, flatter launch, blood and fire/smoke VFX

Built on the owner-tested v13 (release source `8c1caab`, rollback `v13`; older rollback `v12`).

## Why the old city read as scattered houses
The Grand Fortress map (and the v13 cities) placed independent buildings on a flat y = 0 plane: the hand-authored ones in clusters, the
big one by `_decor_city` / `_dense_city` scattering cottages and trees over a green box. There were no streets, blocks, lot frontages or
terrain, so nothing explained why a building was where it was.

## Rising terrain (terrain.gd)
`Terrain` is an analytic height field per preset seed: flat launch pad (x < 16 m), a ramp that climbs away along +X, a bowl that rises
toward the lateral edges, an optional central valley and noise ridges. The same `height()`/`normal()` drive the vertex-coloured mesh
(dry-grass / scrub / dirt by slope, muted yards in urban cells), the trimesh collision, the street layout and every building pad. A coarse
backdrop mesh and a MultiMesh of distant buildings continue the hills past the world wall so the city climbs into the sky.
Ground contact on slopes uses the terrain normal (`Town.ground_normal`), and every "near the ground" threshold in `main.gd` is now height
above terrain (`_agl`).

## Hillside generator (hillside.gd)
TERRAIN -> DISTRICTS (park / low / downtown core noise fields) -> STREETS -> BLOCKS -> LOTS -> BUILDINGS -> PROPS -> LANDMARKS.
- Traversing streets follow terrain contours (bisection on the height field), so they sweep around hills; climbing streets run up the
  slope with a gentle wobble. Both are draped as asphalt + sidewalk ribbons in one mesh.
- Blocks are the cells between two contour streets and two climbing streets. Frontage rows face each street (yaw = street tangent), share
  the block depth, and get a back-yard row; an infill pass fills what is left, yawed along its own contour; trees fill the rest.
- Buildings sit on pads: the body reaches 0.5 m below the lowest ground of its footprint; lots on slopes > 4.6 m across are rejected.
  Overlap is rejected against a spatial grid (no intersecting buildings).
- Heights are capped by the governor's ballistic envelope (`envelope(dist)`), so landmarks/targets are reachable; plain houses stay buildable
  on the high ground (reached by skipping up the hill).
- Landmarks per preset: church (twin towers), radio tower, hilltop mansion, corner store, rooftop tank, hospital - all `_bonus` targets.
- Deterministic: no `randf`; `Hillside.seed_override` exists for tests only.
- Presets (Rules.HILLS): HILLSIDE DISTRICT (steep, dense), VALLEY NEIGHBORHOODS (central channel), ROLLING HEIGHTS (parks, low density),
  SKYLINE HILL (tall core). The v13 cities and the Test Yard are unchanged flat maps (training / alternative identities).
- Building look: Kenney Modular Buildings cubes (CC0), assembled per lot (`_unit_mesh`, cached) and tinted per lot; the Kenney palette is blue-grey
  so the tint is the lot's pastel divided by it.

## Trajectory
`Rules.AIM_ELEV_GAIN` 1.05 -> 0.62: same speed, ~11 degrees flatter at a normal pull (see the evidence table in the owner report).
The soft pitch limit and the range/apex governor are unchanged.

## Blood
Kenney Splat Pack (CC0) atlas, tinted red at runtime (five red values), oriented to the surface normal (ground, slope or wall), 40-mark ring
buffer, 30 s life with a 3 s shrink. A small CPU droplet spray (<= 22 particles) accompanies hard hits and limb loss.

## Fire / smoke
Adapted from the supplied 3dFireSmoke pack (see `third_party/NOTICE.md`; the archive has no licence file): toon flame meshes (20, scaled by the
burning object's size) with a one-octave simplex shader, opaque low-poly toon puffs from CPUParticles3D (dust, crumble cloud, explosion fireball +
charcoal smoke + additive flash, burning smoke columns on the first 8 flames, burn-out smoke). The demo's 252 x ~12k-triangle spheres and
screen-texture read were not used.

## Fixes found on the way (v13 content defects)
`verify_cities` now checks ballistic reachability against the real governor instead of a box test. It found targets that v13's cruder test missed
(Downtown Penthouse / Skyline Sign, Industrial Smokestack, Resort Flamingo Sign / Aqua Penthouse, Grand Fortress Castle Crown / Monastery Spire /
Port Lighthouse): those buildings were lowered or moved into reach.
