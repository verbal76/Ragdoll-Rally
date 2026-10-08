# v15 candidate: mayhem & destruction pass + launch devices

Built on v14 (`6006432`). Everything here is GDScript/assets: OTA-compatible with the installed v14 build (runtime_compat `r2-abbbcedcb90e`, identical to v14).

## Why Ragnar bounced off buildings (root causes)
1. Buildings were single frozen blocks (hill cities) or immovable static boxes (Downtown, Resort, Industrial, fortress walls, signs): nothing to break, so contact was always a bounce.
2. `Town.smash` released pieces in a radius but not always the piece that was touched, so Ragnar kept colliding with it.
3. Upgrades topped out at 5 levels and the launch governor (range 180 m, wall at 215 m) was smaller than the content, so tall/deep geometry was unreachable.
4. Blood was placed at the reported contact point (inside the body), not on the surface; explosions were a fixed 7 m cosmetic.

## Architecture (new files)
- `destruction.gd` - buildings are ONE frozen *shell* body; a `shell` meta holds a lazy plan of cells. First hard hit/blast expands the shell into frozen cells (about 2.4 ms per building on desktop, cached for reuse). `punch()` walks the ragdoll's path through pieces paying `PUNCH_COST_K * tough^2` from an energy budget `(speed*impact_power*destruct_k*launcher)^2`; what is left decides momentum kept (`Rules.punch_walk`). Unsupported storeys fall (`collapse`, stacks linked with `link_stack`). Over-budget pieces dissolve into pooled debris. `PROFILES` + `destruction_profile.gd` (Resource) hold per-material tuning.
- `Town`: `shell_box`, `dissolve`, `ACTIVE_HARD=125`, settle-to-freeze after 7 s, aftermath persists as frozen chunks; fire carried by flying chunks; `hazards`, detonation queue, embers.
- `hazards.gd` - gas company / fuel depot / tank farm: detonate on heavy damage, 5 s of fire, nearby blasts (chained with delays, max 12 per run) or a hard-flying chunk.
- `outskirts.gd` - deep districts out to ~318 m on all 11 boards, building heights capped by the Lv20 reach envelope (`Rules.reach_height`), 3 deep landmark targets, hazard lots. World is 330 m deep (was 215).
- `cam_safe.gd` - sphere-cast chase camera: never inside standing geometry, line of sight kept, flying debris never blocks, hysteresis.
- `launchers.gd`, `launcher_rig.gd` - launch devices as data (below).

## 20-level character mayhem
Launch Power, Bounce, Ricochet, Destruction, Explosive Impact: 20 levels (bands 1-4 Ragdoll Chaos, 5-8 Destructive Chaos, 9-12 Building Wrecker, 13-16 City Destroyer, 17-20 Absurd Mayhem). Destruction multiplier 1.0 -> 9.4; blast radius 5.9 -> 31 m; crater tier 1-4; range cap 150 -> 340 m. Save schema 3 re-spends old credits on the new curve and refunds the surplus (conserved exactly, tested).

## Launch devices (each has 5 levels, stacks with the 20 character levels)
Slingshot (arc; Lv1 identical to the old launcher), Catapult (high deep arc, wind-up), Cannon (direct fire, laser sight + marker, compensated drop), Heavy Artillery (top-down bullseye, solved 66-degree lob, real flight, obstructions are hit), Railgun (direct, charge sequence, 130-205 m/s, hypervelocity plow-through). Unlock prices 2500 / 6000 / 12000 / 25000 credits (a good run banks ~2000). Add a launcher = one entry in `Launchers.ROSTER` (+ an aim mode if it needs a new one).

## Cinematic slowdown, blood, craters, scoring
Event-driven `Engine.time_scale` dips (floor 0.24, merged events, 7 s per run budget, restored at run end). Blood = ray to the real surface, glued to the chunk it hit. Craters (disc + rim + long fire), shockwave rings, secondary blasts. Chaos scoring: BUILDING DOWN, WENT THROUGH, COLLAPSE, HIGH RISE HIT, craters, hazard blasts; per-piece score uses sqrt of the destruction multiplier.

## Validation (local, no Actions minutes)
`tests/verify_mayhem.gd`, `verify_launchers.gd`, `verify_envelope.gd` (every board: reachability by minimum level, no indestructible building-scale statics), `verify_stress.gd` (all 11 boards, stock vs Lv20 real throws: bodies, step time, camera, time scale), plus v13/pivot/expanded/cities/hills/splash/ota.

## Known limits / not verified on a device
- Not played on a phone: launcher aim UI, top-down view, charge feel, camera feel and frame rate on real hardware are untested. Headless p95 step time at Lv20 is about 17-20 ms.
- Railgun maxed runs vary (about x 90 to the 330 m wall) because grazing contacts and blasts still bleed speed.
- Hill boards fit only 1-2 hazard structures (terrain); Downtown/Industrial have 3.
- Trees are not destructible (listed exception, with water, trampolines, ground and tilted ricochet signs).
