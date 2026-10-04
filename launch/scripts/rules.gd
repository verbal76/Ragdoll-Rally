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
# Only `playable` ones can be launched into. The rest are authored-city slots that show up in the
# selector as COMING SOON so the architecture (id -> builder) is in place.
const ENVIRONMENTS: Array[Dictionary] = [
	{"id": "yard", "name": "RAGDOLL TEST YARD", "playable": true,
		"desc": "Compact chaos lab: skip pads, glass, timber, masonry, a trampoline, TNT and kindling."},
	{"id": "city", "name": "THE BIG CITY", "playable": true,
		"desc": "The old b9 map: huge, dense, mostly wooden. Fire spreads."},
	{"id": "downtown", "name": "DOWNTOWN", "playable": false,
		"desc": "Skyscrapers, glass, rooftops, huge drops. Vertical ricochets. COMING SOON."},
	{"id": "oldtown", "name": "OLD TOWN", "playable": false,
		"desc": "Timber, market stalls, bell tower. FIRE. COMING SOON."},
	{"id": "suburbia", "name": "SUBURBIA", "playable": false,
		"desc": "Yards, pools, trampolines, cars. Skip city. COMING SOON."},
	{"id": "industrial", "name": "INDUSTRIAL DISTRICT", "playable": false,
		"desc": "Tanks, cranes, containers, explosives. COMING SOON."},
	{"id": "resort", "name": "RESORT STRIP", "playable": false,
		"desc": "Hotels, slides, curved glass. Weird rebounds. COMING SOON."},
]

# ----------------------------------------------------------------- upgrades
const UPGRADES: Dictionary = {
	"power": {"name": "LAUNCH POWER", "desc": "Faster launch, harder hits", "max": 5, "costs": [250, 500, 900, 1500, 2400]},
	"bounce": {"name": "BOUNCE", "desc": "Keeps more energy on impact", "max": 5, "costs": [250, 500, 900, 1500, 2400]},
	"ricochet": {"name": "RICOCHET", "desc": "Wilder deflections, more secondary hits", "max": 5, "costs": [250, 500, 900, 1500, 2400]},
	"spin": {"name": "SPIN", "desc": "More rotation and flailing", "max": 5, "costs": [200, 450, 800, 1300, 2000]},
	"durability": {"name": "DURABILITY", "desc": "Stays in one piece longer", "max": 5, "costs": [250, 500, 900, 1500, 2400]},
	"destruction": {"name": "DESTRUCTION", "desc": "Bigger breaks, bigger debris", "max": 5, "costs": [300, 600, 1000, 1700, 2600]},
	"explosive": {"name": "EXPLOSIVE IMPACT", "desc": "+10% chance a hard hit explodes", "max": 4, "costs": [800, 1600, 2800, 4500]},
	"ignition": {"name": "IGNITION", "desc": "Burn on hard impact; ignites what you touch", "max": 3, "costs": [600, 1500, 3000]},
}
const UPGRADE_ORDER: Array[String] = ["power", "bounce", "ricochet", "spin", "durability", "destruction", "explosive", "ignition"]

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
	var restitution: float = clampf(0.22 + 0.09 * b + 0.04 * lb, 0.1, 0.95)
	return {
		"launch_mult": 0.90 + 0.055 * p + 0.05 * lp,
		"impact_power": 0.8 + 0.1 * p + 0.1 * lp,
		"extra_mass": 0.35 * p + 0.5 * lp,
		"restitution": restitution,
		"tangent_keep": clampf(0.74 + 0.03 * b + 0.015 * lb, 0.5, 0.97),
		"energy_decay": clampf(0.34 - 0.30 * restitution, 0.06, 0.30),
		"ricochet_deg": 5.0 + 5.0 * r + 3.0 * lr,
		"jitter": 0.5 + 0.25 * c,
		"spin_mult": 0.7 + 0.22 * s + 0.12 * ls,
		"flail": 0.5 + 0.2 * s + 0.08 * ls,
		"dismember_k": clampf(1.6 - 0.24 * d - 0.1 * ld, 0.15, 2.0),
		"destruct_mult": 1.0 + 0.2 * float(lv.get("destruction", 0)),
		"explode_chance": clampf(0.10 * le, 0.0, 0.5),
		"ignition": li,
		"ignite_speed": 14.0 if li <= 1 else 9.0,
		"fire_spread": 1.0 + 0.25 * float(li),
		"assist": 0.25 + 0.05 * b + 0.04 * lb,        # extra skip retention on grazing hits (fades with energy)
	}

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
static func combo_mult(combo: int) -> float:
	return 1.0 + 0.08 * float(clampi(combo - 1, 0, 24))

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
