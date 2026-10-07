extends RefCounted
## RAGDOLL RALLY LAUNCH - game rules as pure, testable functions and data.
## No scene access in here: characters, environments, upgrades, impact/skip/ricochet math,
## dismemberment and explosion odds, run termination, fire spread. Fun overrides realism.
## Use from other scripts with:  const Rules := preload("res://scripts/rules.gd")

const STATS: Array[String] = ["power", "bounce", "ricochet", "spin", "durability", "chaos"]
const STAT_TOTAL := 18            # every character spends exactly this many points: no strictly-better character
const MAX_STAT := 5

# ----------------------------------------------------------------- characters
# 18 Kenney blocky characters (a..r). `letter` picks the model. Stats are 1..5 and always sum to 18.
const CHARACTERS: Array[Dictionary] = [
	{"id": "ragnar", "letter": "m", "name": "RAGNAR", "kind": "BALANCED", "desc": "Seemed like a good idea at the time.",
		"stats": {"power": 3, "bounce": 3, "ricochet": 3, "spin": 3, "durability": 3, "chaos": 3}},
	{"id": "big_red", "letter": "b", "name": "BIG RED", "kind": "DEMOLITION", "desc": "Hits like a parked truck. Lands like one too.",
		"stats": {"power": 5, "bounce": 1, "ricochet": 2, "spin": 2, "durability": 5, "chaos": 3}},
	{"id": "crash", "letter": "d", "name": "CRASH", "kind": "SURVIVOR", "desc": "Built for this. Literally. It's in the contract.",
		"stats": {"power": 2, "bounce": 3, "ricochet": 2, "spin": 2, "durability": 5, "chaos": 4}},
	{"id": "prof_pebbles", "letter": "i", "name": "PROF. PEBBLES", "kind": "SKIPPER", "desc": "Calculated this. Calculated it wrong. Skips anyway.",
		"stats": {"power": 2, "bounce": 5, "ricochet": 3, "spin": 3, "durability": 3, "chaos": 2}},
	{"id": "bolt_bot", "letter": "g", "name": "BOLT-BOT", "kind": "PINBALL", "desc": "Rattles like a loose screw. Is one.",
		"stats": {"power": 2, "bounce": 3, "ricochet": 5, "spin": 2, "durability": 2, "chaos": 4}},
	{"id": "ghosty", "letter": "n", "name": "GHOSTY", "kind": "SPINNER", "desc": "No bones to hold him together. Haunting rotations.",
		"stats": {"power": 2, "bounce": 2, "ricochet": 3, "spin": 5, "durability": 2, "chaos": 4}},
	{"id": "cap_oops", "letter": "p", "name": "CAPTAIN OOPS", "kind": "GLASS CANNON", "desc": "All cannon, no hull. Falls apart gloriously.",
		"stats": {"power": 5, "bounce": 2, "ricochet": 2, "spin": 3, "durability": 1, "chaos": 5}},
	{"id": "old_gus", "letter": "a", "name": "OLD GUS", "kind": "SURVIVOR", "desc": "Has survived worse. Mostly his knees.",
		"stats": {"power": 2, "bounce": 3, "ricochet": 3, "spin": 2, "durability": 5, "chaos": 3}},
	{"id": "officer_nope", "letter": "j", "name": "OFFICER NOPE", "kind": "DEMOLITION", "desc": "Not authorized to be this airborne.",
		"stats": {"power": 5, "bounce": 2, "ricochet": 2, "spin": 2, "durability": 4, "chaos": 3}},
	{"id": "brad", "letter": "q", "name": "BRAD FROM SALES", "kind": "BALANCED", "desc": "Circling back on this impact. Synergy.",
		"stats": {"power": 3, "bounce": 3, "ricochet": 3, "spin": 3, "durability": 2, "chaos": 4}},
	{"id": "zed", "letter": "l", "name": "ZED", "kind": "SURVIVOR", "desc": "Already dead. Limbs are optional.",
		"stats": {"power": 3, "bounce": 2, "ricochet": 2, "spin": 2, "durability": 4, "chaos": 5}},
	{"id": "grunk", "letter": "o", "name": "GRUNK", "kind": "DEMOLITION", "desc": "Grunk smash. Grunk also fly.",
		"stats": {"power": 5, "bounce": 2, "ricochet": 1, "spin": 2, "durability": 4, "chaos": 4}},
	{"id": "shadow", "letter": "r", "name": "SHADOW STEVE", "kind": "SPINNER", "desc": "Silent. Spinning. Slightly embarrassed.",
		"stats": {"power": 3, "bounce": 2, "ricochet": 2, "spin": 5, "durability": 2, "chaos": 4}},
	{"id": "zappy", "letter": "h", "name": "ZAPPY", "kind": "PINBALL", "desc": "Overclocked. Under-attached.",
		"stats": {"power": 3, "bounce": 2, "ricochet": 5, "spin": 2, "durability": 2, "chaos": 4}},
	{"id": "nurse_nate", "letter": "c", "name": "NURSE NATE", "kind": "BALANCED", "desc": "Says this will only hurt a little.",
		"stats": {"power": 3, "bounce": 3, "ricochet": 3, "spin": 2, "durability": 4, "chaos": 3}},
	{"id": "gary", "letter": "e", "name": "GARY", "kind": "SKIPPER", "desc": "Gary from accounting. Gary has had enough.",
		"stats": {"power": 2, "bounce": 5, "ricochet": 3, "spin": 3, "durability": 2, "chaos": 3}},
	{"id": "wendy", "letter": "f", "name": "WENDY WHOOPS", "kind": "PINBALL", "desc": "Bounces off everything, mostly on purpose.",
		"stats": {"power": 2, "bounce": 4, "ricochet": 4, "spin": 3, "durability": 2, "chaos": 3}},
	{"id": "mike", "letter": "k", "name": "MUSTACHE MIKE", "kind": "GLASS CANNON", "desc": "The mustache is load-bearing.",
		"stats": {"power": 4, "bounce": 2, "ricochet": 3, "spin": 3, "durability": 2, "chaos": 4}},
]

static func stat_pips(v: int) -> String:
	return "#".repeat(clampi(v, 0, MAX_STAT)) + ".".repeat(MAX_STAT - clampi(v, 0, MAX_STAT))

# ----------------------------------------------------------------- environments
# `playable` cities are validated by tests/verify_cities.gd before they are enabled. `tag` is shown next to the name
# ("TRAINING" for the Test Yard). `theme` tints the sky/ground so every city looks like its own place.
# v14: the rising hillside cities. Ragnar launches from the low point of a hillside city that climbs toward him.
# rise = height of the far end (m), side = extra rise at the lateral edges (bowl), valley = depth of a central channel,
# ridge = noise relief (m), dh = vertical spacing of the contour streets (m), density 0..1, tall = 0..1 share of tall buildings.
const HILLS: Array[Dictionary] = [
	{"id": "hill_steep", "name": "HILLSIDE DISTRICT", "seed": 7101, "rise": 30.0, "side": 18.0, "valley": 0.0, "valley_w": 40.0, "ridge": 3.2,
		"dh": 5.0, "density": 0.92, "tall": 0.08, "park": 0.10, "hub_x": 96.0, "hub_z": -30.0, "tower_x": 128.0, "tower_z": 26.0},
	{"id": "hill_valley", "name": "VALLEY NEIGHBORHOODS", "seed": 7202, "rise": 24.0, "side": 30.0, "valley": 9.0, "valley_w": 38.0, "ridge": 2.6,
		"dh": 5.6, "density": 0.82, "tall": 0.05, "park": 0.16, "hub_x": 84.0, "hub_z": 40.0, "tower_x": 118.0, "tower_z": -34.0},
	{"id": "hill_rolling", "name": "ROLLING HEIGHTS", "seed": 7303, "rise": 18.0, "side": 14.0, "valley": 0.0, "valley_w": 40.0, "ridge": 5.5,
		"dh": 5.8, "density": 0.68, "tall": 0.04, "park": 0.26, "hub_x": 104.0, "hub_z": 10.0, "tower_x": 132.0, "tower_z": -40.0},
	{"id": "hill_skyline", "name": "SKYLINE HILL", "seed": 7404, "rise": 26.0, "side": 22.0, "valley": 4.0, "valley_w": 34.0, "ridge": 2.8,
		"dh": 5.2, "density": 0.88, "tall": 0.34, "park": 0.08, "hub_x": 92.0, "hub_z": 0.0, "tower_x": 126.0, "tower_z": 30.0},
]

static func is_hill(id: String) -> bool:
	return id.begins_with("hill_")

static func hill_by_id(id: String) -> Dictionary:
	for h in HILLS:
		if str(h["id"]) == id:
			return h
	return HILLS[0]

const ENVIRONMENTS: Array[Dictionary] = [
	{"id": "hill_steep", "name": "HILLSIDE DISTRICT", "playable": true, "tag": "",
		"desc": "Steep, dense hillside neighborhoods climbing toward you. Crash deeper into the city as the streets rise.",
		"theme": {"sky_top": Color(0.34, 0.58, 0.88), "sky_hz": Color(0.86, 0.90, 0.95), "ground": Color(0.55, 0.58, 0.34), "road": Color(0.24, 0.24, 0.26)}},
	{"id": "hill_valley", "name": "VALLEY NEIGHBORHOODS", "playable": true, "tag": "",
		"desc": "A developed valley with neighborhoods climbing both sides. A longer corridor down the middle.",
		"theme": {"sky_top": Color(0.40, 0.62, 0.90), "sky_hz": Color(0.93, 0.89, 0.80), "ground": Color(0.58, 0.60, 0.36), "road": Color(0.24, 0.24, 0.26)}},
	{"id": "hill_rolling", "name": "ROLLING HEIGHTS", "playable": true, "tag": "",
		"desc": "Broad rolling hills, parks and lower-density streets. Long skips between neighborhoods.",
		"theme": {"sky_top": Color(0.30, 0.60, 0.92), "sky_hz": Color(0.88, 0.93, 0.98), "ground": Color(0.50, 0.62, 0.34), "road": Color(0.26, 0.26, 0.28)}},
	{"id": "hill_skyline", "name": "SKYLINE HILL", "playable": true, "tag": "",
		"desc": "A dense core of tall towers built into an elevated hillside. Smash up through the skyline.",
		"theme": {"sky_top": Color(0.28, 0.44, 0.74), "sky_hz": Color(0.82, 0.86, 0.92), "ground": Color(0.50, 0.52, 0.36), "road": Color(0.22, 0.22, 0.25)}},
	{"id": "downtown", "name": "DOWNTOWN", "playable": true, "tag": "",
		"desc": "Skyscraper canyons. Glass fronts, rooftop tanks, billboards, long drops. Think vertical.",
		"theme": {"sky_top": Color(0.20, 0.33, 0.62), "sky_hz": Color(0.72, 0.78, 0.9), "ground": Color(0.30, 0.31, 0.34), "road": Color(0.14, 0.14, 0.16)}},
	{"id": "oldtown", "name": "OLD TOWN", "playable": true, "tag": "",
		"desc": "Tight timber alleys, market stalls, a bell tower. It all burns. Chain destruction.",
		"theme": {"sky_top": Color(0.42, 0.50, 0.72), "sky_hz": Color(0.95, 0.82, 0.62), "ground": Color(0.50, 0.44, 0.34), "road": Color(0.50, 0.45, 0.38)}},
	{"id": "suburbia", "name": "SUBURBIA", "playable": true, "tag": "",
		"desc": "Low roofs, fences, pools and trampolines. Long horizontal skips across the lawns.",
		"theme": {"sky_top": Color(0.30, 0.60, 0.95), "sky_hz": Color(0.82, 0.92, 1.0), "ground": Color(0.38, 0.72, 0.34), "road": Color(0.20, 0.20, 0.22)}},
	{"id": "industrial", "name": "INDUSTRIAL DISTRICT", "playable": true, "tag": "",
		"desc": "Warehouses, containers, tanks and cranes. Explosive chains and heavy destruction.",
		"theme": {"sky_top": Color(0.40, 0.42, 0.48), "sky_hz": Color(0.86, 0.70, 0.52), "ground": Color(0.36, 0.34, 0.32), "road": Color(0.26, 0.25, 0.25)}},
	{"id": "resort", "name": "RESORT STRIP", "playable": true, "tag": "",
		"desc": "Pastel hotels, pools, a waterslide, palms and neon. Weird rebounds, big spectacle.",
		"theme": {"sky_top": Color(0.95, 0.52, 0.55), "sky_hz": Color(1.0, 0.86, 0.60), "ground": Color(0.90, 0.82, 0.62), "road": Color(0.88, 0.80, 0.72)}},
	{"id": "city", "name": "GRAND FORTRESS", "playable": true, "tag": "",
		"desc": "The sprawling castle country: curtain walls, keep, harbor and mills. Huge, long throws.",
		"theme": {"sky_top": Color(0.30, 0.55, 0.92), "sky_hz": Color(0.78, 0.88, 0.97), "ground": Color(0.40, 0.66, 0.34)}},
	{"id": "yard", "name": "RAGDOLL TEST YARD", "playable": true, "tag": "TRAINING",
		"desc": "Training ground: skip pads, glass, timber, masonry, trampoline, TNT. For testing mechanics.",
		"theme": {"sky_top": Color(0.30, 0.55, 0.92), "sky_hz": Color(0.78, 0.88, 0.97), "ground": Color(0.40, 0.66, 0.34)}},
]

static func env_index(id: String) -> int:
	for i in ENVIRONMENTS.size():
		if str(ENVIRONMENTS[i]["id"]) == id:
			return i
	return 0

static func env_by_id(id: String) -> Dictionary:
	return ENVIRONMENTS[env_index(id)]

# ----------------------------------------------------------------- upgrades
# v15: the five MAYHEM upgrades have 20 levels. Prices follow one curve: cost(L) = base * (1 + 0.55 (L-1) + 0.045 (L-1)^2) rounded to 5
# (level 1 = base, level 5 ~ 4x base, level 10 ~ 9.6x, level 20 ~ 27.6x). The whole tree is ~195k credits, about 80 decent runs (a run banks
# ~2000-3500 credits), with the first four levels of everything affordable inside the first one or two runs.
const MAYHEM_KEYS: Array[String] = ["power", "bounce", "ricochet", "destruction", "explosive"]
const MAYHEM_MAX := 20
const MAYHEM_BASE_COST := {"power": 150, "bounce": 110, "ricochet": 110, "destruction": 180, "explosive": 240}

static func mayhem_cost(key: String, level_index: int) -> int:
	var L: float = float(level_index)                      # 0-based index of the level being bought (0 = level 1)
	return int(round(float(MAYHEM_BASE_COST[key]) * (1.0 + 0.55 * L + 0.045 * L * L) / 5.0)) * 5

static func _mayhem_costs(key: String) -> Array:
	var out: Array = []
	for i in MAYHEM_MAX:
		out.append(mayhem_cost(key, i))
	return out

static var UPGRADES: Dictionary = {
	"power": {"name": "LAUNCH POWER", "desc": "Faster, higher, farther - up to absurd flights", "max": MAYHEM_MAX, "costs": _mayhem_costs("power")},
	"bounce": {"name": "BOUNCE", "desc": "Keeps more energy on impact", "max": MAYHEM_MAX, "costs": _mayhem_costs("bounce")},
	"ricochet": {"name": "RICOCHET", "desc": "Wilder deflections, more secondary hits", "max": MAYHEM_MAX, "costs": _mayhem_costs("ricochet")},
	"spin": {"name": "SPIN", "desc": "More rotation and flailing", "max": 5, "costs": [200, 450, 800, 1300, 2000]},
	"durability": {"name": "DURABILITY", "desc": "Stays in one piece longer", "max": 5, "costs": [250, 500, 900, 1500, 2400]},
	"destruction": {"name": "DESTRUCTION", "desc": "Wall breaker -> building wrecker -> city destroyer", "max": MAYHEM_MAX, "costs": _mayhem_costs("destruction")},
	"explosive": {"name": "EXPLOSIVE IMPACT", "desc": "Hard hits detonate: bigger and surer every level", "max": MAYHEM_MAX, "costs": _mayhem_costs("explosive")},
	"ignition": {"name": "IGNITION", "desc": "Burn on hard impact; ignites what you touch", "max": 3, "costs": [600, 1500, 3000]},
}
const UPGRADE_ORDER: Array[String] = ["power", "bounce", "ricochet", "spin", "durability", "destruction", "explosive", "ignition"]

# v12-v14 prices (5 levels): used ONLY to migrate old saves by value (credits spent -> equivalent new levels).
const LEGACY_COSTS := {
	"power": [250, 500, 900, 1500, 2400], "bounce": [250, 500, 900, 1500, 2400], "ricochet": [250, 500, 900, 1500, 2400],
	"destruction": [300, 600, 1000, 1700, 2600], "explosive": [800, 1600, 2800, 4500]}

## Old save -> new levels: the credits an old level cost are re-spent on the new curve (cheapest levels first); what is left over goes
## back to the bank. Nobody loses value and nobody is handed the mayhem tiers for free.
static func migrate_levels(old: Dictionary) -> Dictionary:
	var out: Dictionary = {"levels": old.duplicate(), "refund": 0}
	for key in LEGACY_COSTS.keys():
		var spent: int = 0
		for i in mini(int(old.get(key, 0)), (LEGACY_COSTS[key] as Array).size()):
			spent += int((LEGACY_COSTS[key] as Array)[i])
		var lvl: int = 0
		while lvl < MAYHEM_MAX and spent >= mayhem_cost(key, lvl):
			spent -= mayhem_cost(key, lvl)
			lvl += 1
		(out["levels"] as Dictionary)[key] = lvl
		out["refund"] = int(out["refund"]) + spent
	return out

static func upgrade_cost(key: String, level: int) -> int:
	var u: Dictionary = UPGRADES[key]
	if level >= int(u["max"]):
		return -1
	return int((u["costs"] as Array)[level])

static func empty_levels() -> Dictionary:
	var d: Dictionary = {}
	for k in UPGRADE_ORDER:
		d[k] = 0
	return d

# ----------------------------------------------------------------- materials
# bounce: restitution multiplier; tough: smash threshold multiplier; fire: can burn.
const MATERIALS: Dictionary = {
	"ground": {"bounce": 1.0, "friction": 1.0, "breaks": false, "fire": false, "sound": "thud"},
	"wood": {"bounce": 0.55, "friction": 0.9, "breaks": true, "fire": true, "sound": "wood"},
	"glass": {"bounce": 0.1, "friction": 0.3, "breaks": true, "fire": false, "sound": "glass"},
	"masonry": {"bounce": 0.75, "friction": 1.0, "breaks": true, "fire": false, "sound": "stone"},
	"metal": {"bounce": 1.15, "friction": 0.5, "breaks": false, "fire": false, "sound": "metal"},
	"roof": {"bounce": 0.85, "friction": 0.6, "breaks": true, "fire": true, "sound": "wood"},
	"trampoline": {"bounce": 2.6, "friction": 0.8, "breaks": false, "fire": false, "sound": "boing"},
	"water": {"bounce": 1.1, "friction": 0.15, "breaks": false, "fire": false, "sound": "splash"},
	"canvas": {"bounce": 1.5, "friction": 0.5, "breaks": false, "fire": true, "sound": "boing"},
}

## Material from a kit model name (Kenney Retro Fantasy Kit naming).
static func material_of_model(model: String) -> String:
	if model.begins_with("roof"):
		return "roof"
	for w in ["wood", "structure", "fence", "crate", "barrel", "ladder", "pulley", "dock", "overhang", "tree", "shrub"]:
		if model.contains(w):
			return "wood"
	return "masonry"

# ----------------------------------------------------------------- effective stats
## Turns a character's base stats + owned upgrade levels into the numbers physics uses.
static func effective(stats: Dictionary, lv: Dictionary) -> Dictionary:
	var p: float = float(stats.get("power", 3))
	var b: float = float(stats.get("bounce", 3))
	var r: float = float(stats.get("ricochet", 3))
	var s: float = float(stats.get("spin", 3))
	var d: float = float(stats.get("durability", 3))
	var c: float = float(stats.get("chaos", 3))
	var lp: float = float(lv.get("power", 0))
	var lb: float = float(lv.get("bounce", 0))
	var lr: float = float(lv.get("ricochet", 0))
	var ls: float = float(lv.get("spin", 0))
	var ld: float = float(lv.get("durability", 0))
	var le: float = float(lv.get("explosive", 0))
	var li: int = int(lv.get("ignition", 0))
	var restitution: float = clampf(0.22 + 0.09 * b + 0.015 * lb, 0.1, 0.95)
	return {
		"launch_mult": 0.90 + 0.055 * p + 0.045 * lp,
		"impact_power": 0.8 + 0.1 * p + 0.06 * lp,
		"extra_mass": 0.35 * p + 0.3 * lp,
		"restitution": restitution,
		"tangent_keep": clampf(0.74 + 0.03 * b + 0.006 * lb, 0.5, 0.97),
		"energy_decay": clampf(0.34 - 0.30 * restitution, 0.06, 0.30),
		"ricochet_deg": 5.0 + 5.0 * r + 1.5 * lr,
		"jitter": 0.5 + 0.25 * c,
		"spin_mult": 0.7 + 0.22 * s + 0.07 * ls,
		"flail": 0.5 + 0.2 * s + 0.05 * ls,
		"dismember_k": clampf(1.6 - 0.24 * d - 0.1 * ld, 0.15, 2.0),
		"destruct_mult": destruct_k(int(lv.get("destruction", 0))),
		"explode_radius": blast_radius(int(le)),
		"explode_power": blast_power(int(le)),
		"explode_level": int(le),
		"explode_chance": explode_chance(int(le)),
		"ignition": li,
		"ignite_speed": 14.0 if li <= 1 else 9.0,
		"fire_spread": 1.0 + 0.25 * float(li),
		"assist": 0.25 + 0.05 * b + 0.02 * lb,        # extra skip retention on grazing hits (fades with energy)
		"range_cap": RANGE_CAP_BASE + RANGE_CAP_PER_LEVEL * lp,   # launch governor (see governed_speed)
		"apex_cap": APEX_CAP_BASE + APEX_CAP_PER_LEVEL * lp,
	}


# ----------------------------------------------------------------- 20-level mayhem helpers
## Qualitative band names for a 0..20 level.
static func mayhem_band(level: int) -> String:
	if level <= 0: return "Stock"
	if level <= 4: return "Ragdoll Chaos"
	if level <= 8: return "Destructive Chaos"
	if level <= 12: return "Building Wrecker"
	if level <= 16: return "City Destroyer"
	return "Absurd Mayhem"

## Destruction multiplier on impact energy against structure strength (Lv0 1.0 ... Lv20 ~9.4).
static func destruct_k(level: int) -> float:
	var L: float = float(clampi(level, 0, MAYHEM_MAX))
	return 1.0 + 0.10 * L + 0.016 * L * L

## Probability that an impact above the energy threshold detonates (0 at Lv0).
static func explode_chance(level: int) -> float:
	if level <= 0: return 0.0
	return clampf(0.08 + 0.045 * float(level), 0.0, 0.95)

## Blast radius in metres (Lv1 ~5.9 ... Lv20 ~31).
static func blast_radius(level: int) -> float:
	if level <= 0: return 0.0
	var E: float = float(level)
	return 5.0 + 0.9 * E + 0.02 * E * E

## Blast impulse strength (Lv1 ~22 ... Lv20 ~64).
static func blast_power(level: int) -> float:
	if level <= 0: return 0.0
	return 20.0 + 2.2 * float(level)

## Crater severity 0 none, 1 small, 2 medium, 3 large, 4 catastrophic, from explosive level (and optional bonus energy).
static func crater_tier(level: int) -> int:
	if level <= 0: return 0
	if level <= 5: return 1
	if level <= 10: return 2
	if level <= 16: return 3
	return 4

## Kinetic energy proxy of an impact (mass-weighted v^2 / 2).
static func impact_energy(mass: float, speed: float) -> float:
	return 0.5 * mass * speed * speed

## Impact-energy model for structures. An impact brings `budget = (speed * impact_power * destruct_k)^2`. Each piece along the
## ragdoll's path costs `PUNCH_COST_K * tough^2` (weaker pieces are cheaper). The ragdoll breaks through pieces in order until
## the budget cannot pay for the next one (blocked -> normal bounce/ricochet) or the path ends (it exits the structure).
## What is left decides the momentum it keeps: overwhelming energy loses almost nothing, marginal energy loses most of it.
const PUNCH_COST_K := 28.0

static func piece_cost(tough: float) -> float:
	return PUNCH_COST_K * tough * tough

static func punch_budget(effk: float) -> float:
	return effk * effk

## costs: piece costs ordered along the path. Returns {"n": pieces broken, "left": remaining budget fraction 0..1,
## "blocked": bool (ran out before the path ended), "keep": momentum fraction the ragdoll keeps}.
static func punch_walk(budget: float, costs: Array) -> Dictionary:
	var start: float = maxf(budget, 0.001)
	var left: float = start
	var n: int = 0
	var blocked: bool = false
	for c in costs:
		var cost: float = float(c)
		if left < cost * 0.5:
			blocked = true
			break
		left = maxf(left - cost, 0.0)
		n += 1
	var frac: float = left / start
	var keep: float = clampf(sqrt(frac), 0.25, 0.985)
	if blocked:
		keep = clampf(sqrt(frac) * 0.6, 0.0, 0.6)
	return {"n": n, "left": frac, "blocked": blocked, "keep": keep}

# ----------------------------------------------------------------- cinematic slowdown (event driven, physics safe)
## Time dilation (Engine.time_scale scales the fixed physics step, so the simulation stays stable) is triggered only by
## significant destruction, never by distance, and never stacks: nearby events merge into one longer, stronger moment.
const SLOWMO_MIN_SCALE := 0.24
const SLOWMO_THRESHOLD := 0.3            # events lighter than this never slow the game
const SLOWMO_MAX_HOLD := 1.5             # real seconds one merged moment can last at most
const SLOWMO_RUN_BUDGET := 7.0           # real seconds of slow motion per run, so a long chain never drags the run

## 0..1 weight of a destruction event: pieces broken, impact energy, blast radius.
static func slowmo_weight(broken: int, effk: float, blast_radius: float = 0.0) -> float:
	var w: float = clampf(float(broken) / 14.0, 0.0, 1.0) * clampf(effk / 60.0, 0.4, 1.0)
	if blast_radius >= 9.0:
		w = maxf(w, clampf((blast_radius - 6.0) / 22.0, 0.0, 1.0))
	return clampf(w, 0.0, 1.0)

static func slowmo_scale(w: float) -> float:
	return lerpf(1.0, SLOWMO_MIN_SCALE, smoothstep(SLOWMO_THRESHOLD - 0.05, 1.0, w))

static func slowmo_new() -> Dictionary:
	return {"scale": 1.0, "w": 0.0, "start": -99.0, "until": -99.0, "spent": 0.0}

## State machine step. `now` = real seconds, `dt` = real seconds since last step, `event_w` = weight of an event this step (0 = none).
static func slowmo_step(s: Dictionary, now: float, dt: float, event_w: float) -> Dictionary:
	if event_w >= SLOWMO_THRESHOLD and float(s["spent"]) < SLOWMO_RUN_BUDGET:
		if now >= float(s["until"]):
			s["w"] = event_w                          # a fresh moment
			s["start"] = now
		else:
			s["w"] = maxf(float(s["w"]), event_w)     # merge into the running one (stronger, never a second dip)
		var hold: float = 0.22 + 0.9 * float(s["w"])
		s["until"] = minf(maxf(float(s["until"]), now + hold), float(s["start"]) + SLOWMO_MAX_HOLD)
	var target: float = 1.0
	if now < float(s["until"]) and float(s["spent"]) < SLOWMO_RUN_BUDGET:
		target = slowmo_scale(float(s["w"]))
	var cur: float = float(s["scale"])
	var rate: float = 22.0 if target < cur else 3.2   # dive in fast, ease out slowly
	cur = lerpf(cur, target, 1.0 - exp(-rate * dt))
	if absf(cur - target) < 0.01:
		cur = target
	s["scale"] = clampf(cur, SLOWMO_MIN_SCALE, 1.0)
	if cur < 0.95:
		s["spent"] = float(s["spent"]) + dt
	return s

# ----------------------------------------------------------------- launch trajectory governor
# v12 finding: a hard pull gave 46 deg at up to 72-95 m/s, i.e. a 300-500 m range and a 80-135 m apex: straight over the
# whole city and into the world wall. v13: (1) the upward angle is SOFT-limited, (2) the ideal ballistic range and apex are
# SOFT-capped so no gesture can leave the playfield. Normal throws are untouched; only extremes are compressed.
const RAGDOLL_GRAVITY_SCALE := 1.8
const BASE_GRAVITY := 9.8
const AIM_ELEV_GAIN := 0.62              # v14: gesture elevation gain (v13: 1.05). Pivot launches are ~12 deg flatter at the same power.
const SOFT_PITCH_START_DEG := 28.0        # at or below this the gesture's pitch passes through unchanged
const MAX_PITCH_DEG := 40.0               # absolute ceiling for any gesture (approached asymptotically, never reached)
const MIN_PITCH_DEG := 3.0
const RANGE_CAP_BASE := 150.0             # ideal (drag-free) ballistic range ceiling, metres...
const RANGE_CAP_PER_LEVEL := 9.5          # ...+9.5 m per Launch Power level (max 340 m at Lv20; world is extended to match)
const APEX_CAP_BASE := 55.0               # ideal apex ceiling, metres (tallest Downtown tower ~58 m)
const APEX_CAP_PER_LEVEL := 3.2
const SOFT_KNEE := 0.78                   # caps start compressing at this fraction of the ceiling

static func g_eff() -> float:
	return BASE_GRAVITY * RAGDOLL_GRAVITY_SCALE

## Smooth saturating cap: identity up to knee*cap, then eases asymptotically toward `cap` (never exceeds it).
static func soft_cap(x: float, cap: float, knee: float = SOFT_KNEE) -> float:
	var k: float = cap * knee
	if x <= k:
		return x
	var span: float = cap - k
	return k + span * (1.0 - exp(-(x - k) / span))

## Gesture pitch (degrees) -> launch pitch. Identity below SOFT_PITCH_START_DEG, then compressed toward MAX_PITCH_DEG.
static func soft_pitch_deg(raw_deg: float) -> float:
	var r: float = maxf(raw_deg, MIN_PITCH_DEG)
	if r <= SOFT_PITCH_START_DEG:
		return r
	return soft_cap(r, MAX_PITCH_DEG, SOFT_PITCH_START_DEG / MAX_PITCH_DEG)

static func ideal_range(speed: float, pitch_rad: float) -> float:
	return speed * speed * sin(2.0 * pitch_rad) / g_eff()

static func ideal_apex(speed: float, pitch_rad: float) -> float:
	var vy: float = speed * sin(pitch_rad)
	return vy * vy / (2.0 * g_eff())

## Launch speed after the range/apex governor (never raises speed).
static func governed_speed(speed: float, pitch_rad: float, fx: Dictionary = {}) -> float:
	var rc: float = float(fx.get("range_cap", RANGE_CAP_BASE))
	var ac: float = float(fx.get("apex_cap", APEX_CAP_BASE))
	var f: float = 1.0
	var r: float = ideal_range(speed, pitch_rad)
	if r > 0.001:
		f = minf(f, sqrt(soft_cap(r, rc) / r))
	var a: float = ideal_apex(speed, pitch_rad)
	if a > 0.001:
		f = minf(f, sqrt(soft_cap(a, ac) / a))
	return speed * f

## The launch direction for a gesture: raw pitch from the elevation component, then soft-limited.
## heading = unit horizontal direction; up = tan-like elevation component the gesture produced.
static func launch_dir(heading: Vector3, up: float) -> Vector3:
	var h := Vector3(heading.x, 0.0, heading.z)
	h = h.normalized() if h.length() > 0.0001 else Vector3.RIGHT
	var raw_deg: float = rad_to_deg(atan(maxf(up, 0.0)))
	var pitch: float = deg_to_rad(soft_pitch_deg(raw_deg))
	return (h * cos(pitch) + Vector3.UP * sin(pitch)).normalized()

# ----------------------------------------------------------------- economy: SCORE vs BANKED CREDITS
# Score can be huge and exciting. Permanent upgrade currency is a separate, weighted, diminishing conversion of it,
# so a spectacular skip chain feels great but cannot hand over the whole upgrade tree.
const CREDIT_WEIGHTS := {"Distance": 0.5, "Airtime": 0.5, "Flips": 0.5, "Smashed": 0.5, "Glass": 0.5, "Skips": 0.4, "Ricochets": 0.45,
	"Style": 0.4, "Carnage": 0.55, "Explosions": 0.5, "Fire": 0.5, "Targets": 0.75, "Impacts": 0.5}
const CREDIT_DEFAULT_WEIGHT := 0.5
const CREDIT_SCALE := 1.7                # tuned so a GOOD run (~2300 score) banks ~1900 -> full upgrade tree in ~25 good runs
const CREDIT_KNEE := 2000.0               # credits above this per run count at CREDIT_SLOPE_ABOVE
const CREDIT_SLOPE_ABOVE := 0.6
const CREDIT_RUN_CAP := 3600              # nothing can bank more than this in one run

static func bank_credit(lines: Dictionary) -> int:
	var raw: float = 0.0
	for k in lines.keys():
		raw += float(lines[k]) * float(CREDIT_WEIGHTS.get(k, CREDIT_DEFAULT_WEIGHT)) * CREDIT_SCALE
	if raw > CREDIT_KNEE:
		raw = CREDIT_KNEE + (raw - CREDIT_KNEE) * CREDIT_SLOPE_ABOVE
	return int(minf(raw, float(CREDIT_RUN_CAP)))

static func total_upgrade_cost() -> int:
	var t: int = 0
	for k in UPGRADE_ORDER:
		for c in (UPGRADES[k]["costs"] as Array):
			t += int(c)
	return t

## Points for the n-th skip of a run: gentle growth, capped (v12 paid 40*n and compounded with the combo).
static func skip_points(n: int) -> int:
	return 45 + 8 * mini(maxi(n - 1, 0), 5)

# ----------------------------------------------------------------- impacts
## Box surface normal from the contact point in the box's local space (everything in the yards is boxes).
static func box_normal(local_pos: Vector3, half: Vector3, basis: Basis) -> Vector3:
	var q := Vector3(local_pos.x / maxf(half.x, 0.001), local_pos.y / maxf(half.y, 0.001), local_pos.z / maxf(half.z, 0.001))
	var a := absf(q.x)
	var bb := absf(q.y)
	var c := absf(q.z)
	var n := Vector3.ZERO
	if bb >= a and bb >= c:
		n.y = signf(q.y) if q.y != 0.0 else 1.0
	elif a >= c:
		n.x = signf(q.x)
	else:
		n.z = signf(q.z)
	return (basis * n).normalized()

## Different body parts / orientations hit differently (physics + a little controlled assistance).
## `face` is only used for the torso: "front", "back" or "side".
static func part_modifiers(part: String, face: String) -> Dictionary:
	var m := {"e": 1.0, "spin": 1.0, "lift": 0.0, "lateral": 0.0, "label": ""}
	match part:
		"head":
			m = {"e": 0.75, "spin": 1.8, "lift": -0.1, "lateral": 0.0, "label": "HEADFIRST"}
		"arm-left", "arm-right":
			m = {"e": 0.9, "spin": 1.0, "lift": 0.0, "lateral": 0.22, "label": "SHOULDER"}
		"leg-left", "leg-right":
			m = {"e": 1.05, "spin": 1.3, "lift": 0.18, "lateral": 0.0, "label": "VAULT"}
		_:
			match face:
				"back":
					m = {"e": 1.2, "spin": 0.9, "lift": 0.05, "lateral": 0.0, "label": "BACKFLOP"}
				"side":
					m = {"e": 1.0, "spin": 1.4, "lift": 0.0, "lateral": 0.12, "label": "CARTWHEEL"}
				_:
					m = {"e": 0.95, "spin": 1.0, "lift": 0.0, "lateral": 0.0, "label": ""}
	return m

## The skipping-stone model. v_in = velocity just before the hit, n = surface normal (unit, pointing out
## of the surface), fx = effective(), mat = material name, mods = part_modifiers(), energy = 0..1 arcade
## energy left in the run, rnd = a value in [-1,1] (so the maths stays deterministic and testable).
## Returns {v, omega, bounced, graze, ricochet_deg}.  Speed never grows except off springy materials.
static func impact_response(v_in: Vector3, n: Vector3, fx: Dictionary, mat: String, mods: Dictionary, energy: float, rnd: float) -> Dictionary:
	var out := {"v": v_in, "omega": Vector3.ZERO, "bounced": false, "graze": 0.0, "ricochet_deg": 0.0}
	var speed: float = v_in.length()
	var nn: Vector3 = n.normalized()
	var vn: float = v_in.dot(nn)
	if speed < 0.01 or vn >= 0.0:
		return out
	var md: Dictionary = MATERIALS.get(mat, MATERIALS["ground"])
	var v_tan: Vector3 = v_in - nn * vn
	var graze: float = 1.0 - clampf(-vn / speed, 0.0, 1.0)        # 0 = head-on, 1 = grazing
	var e: float = float(fx["restitution"]) * float(md["bounce"]) * (0.65 + 0.7 * graze) * float(mods["e"])
	var keep_t: float = float(fx["tangent_keep"]) * (0.9 + 0.15 * graze) * lerpf(1.0, float(md["friction"]), 0.3)
	# arcade skip assist: grazing hits keep extra speed, fading as the run's energy is spent
	var assist: float = 1.0 + float(fx["assist"]) * graze * clampf(energy, 0.0, 1.0)
	var v_out: Vector3 = v_tan * keep_t * assist + nn * (-vn) * e
	# lift: small vertical pop on grazing hits (pebble skip) and for vaulting feet
	v_out += Vector3.UP * (speed * (0.06 * graze * float(fx["assist"]) * 4.0 + float(mods["lift"]) * 0.5)) * clampf(energy, 0.2, 1.0)
	# ricochet: bounded rotation of the outgoing direction around the surface normal (+ pinball kick)
	var dev_deg: float = float(fx["ricochet_deg"]) * float(fx["jitter"]) * rnd
	var dev: float = deg_to_rad(clampf(dev_deg, -45.0, 45.0))
	v_out = v_out.rotated(nn, dev)
	var lat: float = float(mods["lateral"])
	if lat != 0.0 and v_tan.length() > 0.1:
		v_out += nn.cross(v_tan.normalized()) * speed * lat * signf(rnd if rnd != 0.0 else 1.0)
	# never create energy out of a non-springy surface
	var cap: float = speed * (1.0 if float(md["bounce"]) <= 1.2 else float(md["bounce"]) * 0.9)
	if v_out.length() > cap:
		v_out = v_out.normalized() * cap
	# roll-over spin around (normal x tangent) scaled by how fast we were sliding
	var omega: Vector3 = Vector3.ZERO
	if v_tan.length() > 0.1:
		omega = nn.cross(v_tan.normalized()) * minf(v_tan.length() / 0.6, 30.0) * 0.35 * float(fx["spin_mult"]) * float(mods["spin"])
	out["v"] = v_out
	out["omega"] = omega
	out["bounced"] = true
	out["graze"] = graze
	out["ricochet_deg"] = rad_to_deg(dev)
	return out

## Arcade energy left after one more qualifying impact.
static func energy_after(energy: float, fx: Dictionary, speed: float) -> float:
	if speed < 6.0:
		return energy
	return clampf(energy * (1.0 - float(fx["energy_decay"])), 0.0, 1.0)

## Severity 0..1+ of an impact (drives feedback + dismemberment).
static func severity(speed: float) -> float:
	return clampf((speed - 4.0) / 26.0, 0.0, 1.5)

static func impact_tier(speed: float) -> String:
	if speed < 9.0:
		return "light"
	if speed < 17.0:
		return "medium"
	if speed < 27.0:
		return "major"
	return "extreme"

# ----------------------------------------------------------------- dismemberment / explosions
const DISMEMBER_SPEED := 15.0
const PART_WEIGHT := {"arm-left": 1.0, "arm-right": 1.0, "leg-left": 0.9, "leg-right": 0.9, "head": 0.2, "torso": 0.0}

static func dismember_chance(speed: float, part: String, fx: Dictionary) -> float:
	if speed < DISMEMBER_SPEED:
		return 0.0
	var w: float = float(PART_WEIGHT.get(part, 0.0))
	return clampf(clampf((speed - DISMEMBER_SPEED) / 18.0, 0.0, 1.0) * w * float(fx["dismember_k"]) * 0.8, 0.0, 0.65)

## rnd in [0,1).
static func explosive_impact(speed: float, fx: Dictionary, rnd: float) -> bool:
	return speed >= 12.0 and rnd < float(fx["explode_chance"])

# ----------------------------------------------------------------- run termination
## The throw ends when real kinetic action is over: no slow rolling for 8-15 seconds.
## s = {elapsed, landed, max_speed, calm_t (seconds below calm speed), event_age (seconds since last
## notable event), energy, burning (anything still on fire/in motion that matters), max_t}
static func run_finished(s: Dictionary) -> bool:
	var elapsed: float = float(s.get("elapsed", 0.0))
	if elapsed >= float(s.get("max_t", 11.0)):
		return true
	if not bool(s.get("landed", false)) or elapsed < 1.0:
		return false
	var spd: float = float(s.get("max_speed", 99.0))
	var calm_t: float = float(s.get("calm_t", 0.0))
	var ev: float = float(s.get("event_age", 99.0))
	if spd < 1.0 and calm_t > 0.35:
		return true
	if calm_t > 0.55 and ev > 0.9:
		return true
	if float(s.get("energy", 1.0)) < 0.12 and spd < 5.0 and calm_t > 0.35 and ev > 0.7:
		return true
	return false

static func is_calm(max_speed: float, energy: float) -> bool:
	return max_speed < (4.0 if energy > 0.2 else 6.5)

# ----------------------------------------------------------------- scoring helpers
## Combo multiplier: each scoring event within the window extends the combo.
const COMBO_MAX_LINKS := 14               # x1.84 at most (v12: x2.9)

static func combo_mult(combo: int) -> float:
	return 1.0 + 0.06 * float(clampi(combo - 1, 0, COMBO_MAX_LINKS))

# ----------------------------------------------------------------- fire (data model)
const FIRE_CAP := 26             # max simultaneously burning things (performance bound)
const FIRE_RADIUS := 3.6
const FIRE_BURN_T := 5.0
const FIRE_SPREAD_RATE := 0.45   # ignition chance per second per burning neighbour in range

## Pure spread step so fire propagation limits can be tested:
## positions[i], state[i] 0 = fuel, 1 = burning, 2 = burnt, timer[i] = seconds burning.
## rnds = optional random values per entry (0..1); when empty, randf() is used.
## grid = optional spatial hash {Vector2i cell -> PackedInt32Array of indices} (cell size `cell`) so only
## nearby fuel is examined. Returns {ignite: Array[int], burnt: Array[int]}.
static func fire_step(positions: Array, state: PackedInt32Array, timer: PackedFloat32Array, dt: float, spread_mult: float, rnds: Array = [], grid: Dictionary = {}, cell: float = 4.0) -> Dictionary:
	var ignite: Array[int] = []
	var burnt: Array[int] = []
	var burning_idx: Array[int] = []
	for i in state.size():
		if state[i] == 1:
			timer[i] += dt
			if timer[i] >= FIRE_BURN_T:
				state[i] = 2
				burnt.append(i)
			else:
				burning_idx.append(i)
	if burning_idx.is_empty():
		return {"ignite": ignite, "burnt": burnt}
	var near: Dictionary = {}
	var r2: float = FIRE_RADIUS * FIRE_RADIUS
	for j in burning_idx:
		var pj: Vector3 = positions[j]
		var cand: Array = []
		if grid.is_empty():
			cand = range(state.size())
		else:
			var cx: int = int(floor(pj.x / cell))
			var cz: int = int(floor(pj.z / cell))
			for dx in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					var arr = grid.get(Vector2i(cx + dx, cz + dz))
					if arr != null:
						cand.append_array(arr)
		for i in cand:
			if state[i] == 0 and (positions[i] as Vector3).distance_squared_to(pj) < r2:
				near[i] = int(near.get(i, 0)) + 1
	var burning: int = burning_idx.size()
	for i in near.keys():
		if burning + ignite.size() >= FIRE_CAP:
			break
		var rv: float = float(rnds[i]) if rnds.size() > int(i) else randf()
		if rv < minf(FIRE_SPREAD_RATE * spread_mult * dt * float(near[i]), 0.9):
			ignite.append(int(i))
	for i in ignite:
		state[i] = 1
		timer[i] = 0.0
	return {"ignite": ignite, "burnt": burnt}
