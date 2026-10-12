# v13 gameplay / content round

Built on the physically tested v12 (rollback: tag `v12`, source `5ff3d5d`).

## Trajectory (soft limit, not a flat cap)
- Gesture pitch passes through unchanged up to 28 deg, then eases asymptotically toward 40 deg (`Rules.soft_pitch_deg`). Loft, rooftop access and ricochet angles are preserved; no gesture can fire a near-vertical rocket.
- Range/apex governor (`Rules.governed_speed`): ideal ballistic range soft-capped at 150 m (+6 m per Launch Power level, 180 m max); ideal apex soft-capped at 55 m (+1 m per level). The wall is at 215 m.
- Matrix test (`tests/verify_v13.gd`): 11 gestures x 3 upgrade tiers; all 18 characters at max upgrades stay inside the caps.

## World boundary
Root cause: the perimeter colliders were generic masonry statics, so a fast throw "exploded" (dismemberment, blood, score) against an invisible wall. Now they carry a `boundary` tag; touching one ends the run cleanly ("OUT OF BOUNDS", velocity damped, no carnage/explosions/score). Regression test: `verify_v13.gd`.

## Economy (score and bank are separate)
- Score stays big and exciting. Banked credits = weighted conversion (x1.7 scale, weights 0.4-0.75, diminishing above 2000, hard cap 3600/run).
- Skips: one skip per real bounce (airborne + 0.35 s cooldown), flat-ish pay (45 + 8/skip up to 85), combo x1.06 per link capped at 14 links (x1.84). v12 paid +2394 for 7 skips (per-part overcounting + 40*n compounded by a x2.9 combo); now 7 skips pay 475 base.
- Upgrade prices unchanged. Full tree = 47,950 credits: weak run ~200, average ~760, good ~2000, excellent ~3500 -> ~24 good runs / ~14 excellent runs to max.
- The player-visible "+10,000 (TEST)" button is removed. A developer grant exists only behind `--dev-economy` / `RR_DEV_ECONOMY=1`; `verify_v13.gd` and `tools/inspect_apk_content.py` (on the built APK) guard it.

## Cities (7 environments, none locked)
Downtown (24-46 m towers, glass, breakable crowns/ledges/balconies, rooftop tanks, awnings, scaffolds), Old Town (timber/masonry, stalls, powder store, well, canal + bridge, chimneys, bell tower, fire), Suburbia (houses, garages, fences, pools, trampolines, sheds, poles, slide), Industrial District (warehouses, containers, tank farm, cranes, stacks, explosive chain), Resort Strip (hotels, glass, balconies, pools, waterslide, tikis, lifeguard towers, umbrellas, kiosks, palms), Grand Fortress (the original big city, kept; launcher corridor cleared, Castle Crown moved into range), Ragdoll Test Yard (TRAINING).
Quality gate: `tests/verify_cities.gd` (spawn clearance, determinism, targets reachable under the governor, content spread, automated throws with base and maxed characters, bounded awake bodies, frame time).

## Release gates (CI)
verify, verify_ota, verify_splash, verify_pivot, verify_expanded, verify_v13, verify_cities, physics baseline, `verify_apk.py`, `inspect_apk_content.py`.
