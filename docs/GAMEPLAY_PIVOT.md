# RR Launch - gameplay pivot (fun-first rebuild)

The ragdoll is the game; the city is the playground. Fun overrides realism.

Rollback points: tag `launch-g2x-b9` (b9, `db4534e`) and `rr-checkpoint-b15` (the build before the pivot, `cac2e29`). Nothing was rewritten.

## Where things live
| File | What |
|---|---|
| `launch/scripts/rules.gd` | ALL game rules as pure functions/data: 18 characters + stat profiles, 8 upgrade families, materials, skip/ricochet maths, energy decay, dismemberment + explosion odds, run termination, fire spread, combo. Fully unit-tested. |
| `launch/scripts/ragdoll.gd` | Rig: loose flailing joints, per-character physics, limbs that detach and keep colliding, per-part burning. |
| `launch/scripts/main.gd` | Flow (select -> aim -> flight -> result), impact system, camera, upgrades UI. |
| `launch/scripts/town.gd` | Maps: RAGDOLL TEST YARD + the b9 city; material tags, fire engine, glass. |
| `launch/scripts/fx.gd` | Pooled effects: blood, per-material debris, explosions, flames, smoke, splats. |
| `launch/scripts/select_ui.gd` | CHOOSE YOUR RAGDOLL -> CHOOSE YOUR CITY (arrows + swipe). |
| `launch/tests/verify_pivot.gd` | The pivot tests (rules + scenes + physics). |

## Throw
Faster, flatter launch (20-50 m/s, overdrive to 68) and comedy gravity (1.8x on the ragdoll) so the first impact comes within ~1-3 s. Launch angle sets the tumble. Swipe left/right while airborne adds rotation (bounded).

## Flail
Limb angular damping ~0.1, wide swing spans, random whips while moving fast, per-limb launch spin. Angular velocity is clamped (26 rad/s per frame).

## Skip (pebble model) - `Rules.impact_response`
Velocity splits into normal + tangential parts. Grazing hits keep their forward speed (`tangent_keep`, plus an arcade assist that fades with the run's remaining energy), pop upward slightly, and rotate by a bounded ricochet angle around the surface normal. Each hard hit spends arcade energy (`energy_after`), so a run always winds down; speed is never created except off springy surfaces (trampoline, 3 uses per run). The body part and face that hit change the result: head-first = big spin + low ricochet, back = broad rebound, side = cartwheel, shoulder = sideways kick, feet = vault. Surface normals come from the box faces of whatever was hit.

## End of run
`Rules.run_finished`: ends when the torso (and any flying limb) is calm for ~0.5 s after something landed, or energy is spent and speed is low, or the 11 s cap. Fire/explosion events extend it while chaos is still unfolding. A SKIP button appears after 2 s.

## Characters
All 18 Kenney blocky characters. Every character has exactly 18 stat points over POWER / BOUNCE / RICOCHET / SPIN / DURABILITY / CHAOS (1-5), so none is strictly better. Styles: BALANCED, DEMOLITION, SURVIVOR, SKIPPER, PINBALL, SPINNER, GLASS CANNON. Stats feed `Rules.effective()` (launch speed, mass, restitution, tangent keep, ricochet angle, spin/flail, limb-loss factor).

## Upgrades (stack multiplicatively through `effective()`)
LAUNCH POWER, BOUNCE, RICOCHET, SPIN, DURABILITY, DESTRUCTION (5 levels each), EXPLOSIVE IMPACT (4 levels, +10% chance per level that a hard hit explodes), IGNITION (3 levels: you catch fire on a hard hit; burning parts ignite what they touch; detached limbs stay on fire). Bought with banked score. The upgrade panel has a `+10,000 (TEST)` button so combinations can be tried immediately.

## Dismemberment + blood
Only hits above 15 m/s can take a limb; odds rise with speed and fall with durability; the torso never comes off, heads rarely. A detached limb is its own physics body: keeps velocity, bounces, breaks things, scores, can burn and ignite fuel, leaves a short blood trail. Blood is cartoon particles + ground splats, pooled and capped. Settings -> Gore ON/OFF hides blood (limbs still come off; they are blocky pieces).

## Materials
wood (splinters, burns), glass (shatters, absorbs), masonry (chunks + dust, tough), metal (sparks, springy, hard ricochet), roof (light timber, burns), trampoline (very springy), ground. Each has its own sound, debris effect and bounce factor. Kit models map to a material by name (`Rules.material_of_model`).

## Fire
Combustible objects (timber pieces, crates/barrels, cottages, trees) register with the town. `Rules.fire_step` spreads fire through a spatial grid: capped at 26 burning things, 3.6 m range, 5 s burn, burnt things collapse/vanish. TNT that burns explodes. Flames/smoke use fixed pools.

## Explosions
TNT chains (radial impulse to pieces/props/ragdoll, ignites timber in range, debris + fireball + camera pull-back). The EXPLOSIVE IMPACT upgrade can detonate a blast at the point of a hard hit.

## Scoring
Distance, airtime, flips, smashes, glass, skips, ricochets, style (head-first etc.), limbs lost, explosions, fire (ignitions, spread milestones, burned down), targets. Events chained within 1.6 s build a combo: x1.08 per link up to x2.9; shown on screen.

## Environments
`Rules.ENVIRONMENTS` is the registry (id, name, playable, description) and `Town.build(legacy, env_id)` the router. Playable: RAGDOLL TEST YARD (compact chaos lab) and THE BIG CITY (the b9 map, not retuned for the pivot). DOWNTOWN, OLD TOWN, SUBURBIA, INDUSTRIAL DISTRICT, RESORT STRIP are listed in the selector as locked slots. Random city is future work; a city is just data + a builder.

## Performance
Fixed pools for all particles/flames/splats; active released pieces capped at 90; fire capped at 26 with grid lookups; trails capped at 4; score popups capped at 7; contact chatter filtered. Known cost centre: the b9 city registers ~1500 combustibles (grid keeps the step cheap) and ~880 breakable decor bodies.

## Not done / deferred
The 5 authored cities (only slots), random city, hit-stop/slow-mo, real dismembered-mesh rendering (limbs are the rig's blocky parts), final audio (sounds are synthesized placeholders), the b9 city is not tuned for the new physics.
