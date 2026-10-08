extends RefCounted
## Launch / delivery systems. A launcher is DATA: an aiming mode, a trajectory model, a camera, launch effects and a five-level
## upgrade curve. The game core only asks this file "what are the stats of launcher X at level N" and "what does aiming mean
## for mode M"; adding another ridiculous delivery system later is one more entry in ROSTER (and, if it needs a new way of
## aiming, one more mode handled in main.gd's aim dispatch). Launcher levels (1..5) improve the MACHINE and stack with the 20
## character mayhem levels in Rules.
## Use with:  const Launchers := preload("res://scripts/launchers.gd")

const Rules := preload("res://scripts/rules.gd")

const MAX_LEVEL := 5

## Aiming modes:
##   "arc"       pull back and release; dotted ballistic preview (slingshot, catapult)
##   "direct"    point a gun at a visible target, fire (cannon); laser sight + target marker, no ballistic arc
##   "charge"    point, hold through a charge-up, discharge (railgun)
##   "topdown"   overhead tactical view, move a bullseye, the game solves a lob (artillery)
##
## Per-launcher keys (each stat is [level 1 .. level 5], interpolated linearly):
##   speed       muzzle/launch speed (m/s) for direct modes; for arc modes a multiplier on the pull-power speed
##   range_mult  multiplier on the character's range governor cap (arc modes)   apex_mult  same for apex
##   pitch_max   steepest launch angle (deg)  pitch_min  flattest/downward (deg, direct)  yaw  traverse each side (deg, direct)
##   impact      multiplier on impact energy into the destruction model (penetration / blast trigger)
##   gravity_k   fraction of normal gravity during the first flat_t seconds (direct modes fly nearly straight)
##   charge_t    seconds of charge (charge mode)   min_range / max_range  artillery target ring (m)
##   cost        price of each level 1..5 (level 1 is the unlock price for everything except the slingshot, owned from the start)
const ROSTER: Array[Dictionary] = [
	{"id": "slingshot", "name": "SLINGSHOT", "mode": "arc", "tag": "MEDIUM RANGE CHAOS",
		"desc": "The classic. Pull back, let go, hope. Near and middle city.",
		"owned": true, "unlock": 0, "cost": [0, 600, 1500, 3200, 6000],
		"speed": [1.0, 1.08, 1.17, 1.26, 1.36], "range_mult": [1.0, 1.12, 1.26, 1.42, 1.6], "apex_mult": [1.0, 1.1, 1.22, 1.35, 1.5],
		"pitch_max": [40.0, 40.0, 41.0, 42.0, 43.0], "impact": [1.0, 1.1, 1.22, 1.36, 1.55], "gravity_k": [1.0, 1.0, 1.0, 1.0, 1.0], "flat_t": [0.0, 0.0, 0.0, 0.0, 0.0],
		"preview": 30, "windup": 0.0, "cam": "chase", "flash": 0.0},
	{"id": "catapult", "name": "CATAPULT", "mode": "arc", "tag": "DEEP-MAP HIGH ARCS",
		"desc": "Wind. Tension. Release. Whump. Ragnar vanishes into the sky and comes down on the back of the city.",
		"unlock": 2500, "cost": [2500, 1800, 3600, 6500, 11000],
		"speed": [1.0, 1.1, 1.22, 1.35, 1.5], "range_mult": [1.7, 1.95, 2.2, 2.5, 2.8], "apex_mult": [2.0, 2.3, 2.6, 2.95, 3.3],
		"pitch_max": [58.0, 61.0, 64.0, 67.0, 70.0], "impact": [1.1, 1.2, 1.32, 1.46, 1.65], "gravity_k": [1.0, 1.0, 1.0, 1.0, 1.0], "flat_t": [0.0, 0.0, 0.0, 0.0, 0.0],
		"preview": 46, "windup": 0.55, "cam": "chase_high", "flash": 0.0},
	{"id": "cannon", "name": "CANNON", "mode": "direct", "tag": "DIRECT FIRE",
		"desc": "Point it at THAT. Fire Ragnar straight into a facade, a rooftop, a tower.",
		"unlock": 6000, "cost": [6000, 3200, 6000, 10000, 16000],
		"speed": [72.0, 80.0, 89.0, 99.0, 110.0], "range_mult": [1.0, 1.0, 1.0, 1.0, 1.0], "apex_mult": [1.0, 1.0, 1.0, 1.0, 1.0],
		"pitch_max": [38.0, 40.0, 42.0, 44.0, 46.0], "pitch_min": [-4.0, -5.0, -6.0, -7.0, -8.0], "yaw": [30.0, 34.0, 38.0, 42.0, 46.0],
		"impact": [1.3, 1.5, 1.75, 2.0, 2.3], "gravity_k": [0.5, 0.42, 0.36, 0.3, 0.25], "flat_t": [1.2, 1.4, 1.6, 1.8, 2.0],
		"preview": 0, "windup": 0.0, "cam": "chase_low", "flash": 1.0},
	{"id": "artillery", "name": "HEAVY ARTILLERY", "mode": "topdown", "tag": "INDIRECT PRECISION",
		"desc": "Tactical view. Drop the bullseye anywhere in range. Ragnar comes down from above - if nothing is in the way.",
		"unlock": 12000, "cost": [12000, 5000, 9000, 15000, 24000],
		"speed": [95.0, 108.0, 122.0, 137.0, 152.0], "range_mult": [1.0, 1.0, 1.0, 1.0, 1.0], "apex_mult": [1.0, 1.0, 1.0, 1.0, 1.0],
		"pitch_max": [66.0, 66.0, 66.0, 66.0, 66.0], "min_range": [50.0, 50.0, 50.0, 50.0, 50.0], "max_range": [140.0, 175.0, 215.0, 255.0, 300.0],
		"impact": [1.5, 1.7, 1.95, 2.25, 2.6], "gravity_k": [1.0, 1.0, 1.0, 1.0, 1.0], "flat_t": [0.0, 0.0, 0.0, 0.0, 0.0],
		"preview": 0, "windup": 0.4, "cam": "topdown", "flash": 1.2},
	{"id": "railgun", "name": "RAILGUN", "mode": "charge", "tag": "ENDGAME PENETRATION",
		"desc": "Aim down a line through the city. Charge. Discharge. Everything in the line has a bad day.",
		"unlock": 25000, "cost": [25000, 9000, 16000, 26000, 40000],
		"speed": [130.0, 148.0, 166.0, 185.0, 205.0], "range_mult": [1.0, 1.0, 1.0, 1.0, 1.0], "apex_mult": [1.0, 1.0, 1.0, 1.0, 1.0],
		"pitch_max": [14.0, 15.0, 16.0, 17.0, 18.0], "pitch_min": [-3.0, -3.5, -4.0, -4.5, -5.0], "yaw": [40.0, 44.0, 48.0, 52.0, 56.0],
		"impact": [2.4, 3.0, 3.7, 4.5, 5.5], "gravity_k": [0.1, 0.08, 0.06, 0.04, 0.03], "flat_t": [2.4, 2.8, 3.2, 3.6, 4.0],
		"charge_t": [2.6, 2.3, 2.0, 1.7, 1.4], "preview": 0, "windup": 0.0, "cam": "chase_low", "flash": 1.6},
]

static func ids() -> Array[String]:
	var out: Array[String] = []
	for r in ROSTER:
		out.append(str(r["id"]))
	return out

static func by_id(id: String) -> Dictionary:
	for r in ROSTER:
		if str(r["id"]) == id:
			return r
	return ROSTER[0]

static func index_of(id: String) -> int:
	for i in ROSTER.size():
		if str(ROSTER[i]["id"]) == id:
			return i
	return 0

## Interpolated stat for a level (1..5, fractional allowed). Missing stats return `def`.
static func stat(id: String, key: String, level: float, def: float = 0.0) -> float:
	var r: Dictionary = by_id(id)
	if not r.has(key):
		return def
	var arr: Array = r[key]
	var t: float = clampf(level - 1.0, 0.0, float(arr.size() - 1))
	var i: int = int(floor(t))
	var j: int = mini(i + 1, arr.size() - 1)
	return lerpf(float(arr[i]), float(arr[j]), t - float(i))

## All stats of a launcher at a level, as one dictionary (what main.gd consumes).
static func stats(id: String, level: int) -> Dictionary:
	var r: Dictionary = by_id(id)
	var lv: float = float(clampi(level, 1, MAX_LEVEL))
	return {
		"id": id, "mode": r["mode"], "name": r["name"], "cam": r.get("cam", "chase"), "level": int(lv),
		"speed": stat(id, "speed", lv, 1.0), "range_mult": stat(id, "range_mult", lv, 1.0), "apex_mult": stat(id, "apex_mult", lv, 1.0),
		"pitch_max": stat(id, "pitch_max", lv, 40.0), "pitch_min": stat(id, "pitch_min", lv, 0.0), "yaw": stat(id, "yaw", lv, 0.0),
		"impact": stat(id, "impact", lv, 1.0), "gravity_k": stat(id, "gravity_k", lv, 1.0), "flat_t": stat(id, "flat_t", lv, 0.0),
		"charge_t": stat(id, "charge_t", lv, 0.0), "min_range": stat(id, "min_range", lv, 0.0), "max_range": stat(id, "max_range", lv, 0.0),
		"windup": float(r.get("windup", 0.0)), "preview": int(r.get("preview", 30)), "flash": float(r.get("flash", 0.0)),
	}

# ------------------------------------------------------------------ economy
## Price of the NEXT purchase for a launcher: unlock (when not owned), then upgrades. -1 = maxed.
## `lv` 0 = not owned (the slingshot is owned at level 1 from the start).
static func next_cost(id: String, lv: int) -> int:
	var r: Dictionary = by_id(id)
	var costs: Array = r["cost"]
	if lv >= MAX_LEVEL:
		return -1
	if lv <= 0:
		return int(r["unlock"])
	return int(costs[lv])                      # costs[1] = level 2 ... costs[4] = level 5

static func total_cost(id: String) -> int:
	var t := 0
	var lv := 0
	while next_cost(id, lv) >= 0:
		t += next_cost(id, lv)
		lv += 1
	return t

static func empty_levels() -> Dictionary:
	var d: Dictionary = {}
	for r in ROSTER:
		d[str(r["id"])] = 1 if bool(r.get("owned", false)) else 0
	return d

# ------------------------------------------------------------------ ballistics
## Launch speed that carries a body from `origin` to `target` along a lob of the given pitch (degrees), under gravity `g`.
## Returns {"ok", "speed", "dir", "t"}. ok = false when the target is not reachable at that pitch (or is behind / too close).
static func solve_lob(origin: Vector3, target: Vector3, pitch_deg: float, g: float) -> Dictionary:
	var d := Vector3(target.x - origin.x, 0.0, target.z - origin.z)
	var dist: float = d.length()
	if dist < 1.0:
		return {"ok": false, "speed": 0.0, "dir": Vector3.RIGHT, "t": 0.0}
	var th: float = deg_to_rad(pitch_deg)
	var den: float = 2.0 * cos(th) * cos(th) * (dist * tan(th) - (target.y - origin.y))
	if den <= 0.0001:
		return {"ok": false, "speed": 0.0, "dir": Vector3.RIGHT, "t": 0.0}
	var v: float = sqrt(g * dist * dist / den)
	var h: Vector3 = d / dist
	var dir: Vector3 = (h * cos(th) + Vector3.UP * sin(th)).normalized()
	return {"ok": true, "speed": v, "dir": dir, "t": dist / (v * cos(th))}

## Direction for a direct-fire gun at yaw/pitch (degrees; yaw 0 = +X, positive yaw toward +Z).
static func direct_dir(yaw_deg: float, pitch_deg: float) -> Vector3:
	var y: float = deg_to_rad(yaw_deg)
	var p: float = deg_to_rad(pitch_deg)
	return Vector3(cos(p) * cos(y), sin(p), cos(p) * sin(y)).normalized()

## Yaw/pitch (degrees) that point from `origin` at `target`, clamped to the launcher's mechanical limits.
static func aim_at(st: Dictionary, origin: Vector3, target: Vector3) -> Vector2:
	var d: Vector3 = target - origin
	var yaw: float = rad_to_deg(atan2(d.z, maxf(d.x, 0.001)))
	var pitch: float = rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length()))
	return Vector2(clampf(yaw, -float(st["yaw"]), float(st["yaw"])), clampf(pitch, float(st["pitch_min"]), float(st["pitch_max"])))

## Impact-energy speed: speed above 60 m/s counts for a third, so a 200 m/s railgun round is overwhelmingly violent
## but not a thousand times a stock throw (energy is what pays for penetration, see Rules.punch_*).
static func energy_speed(speed: float) -> float:
	return minf(speed, 60.0) + maxf(speed - 60.0, 0.0) * 0.33

## Launch speed of a direct-fire machine with the character's Launch Power folded in (35% of the character bonus applies).
static func direct_speed(st: Dictionary, launch_mult: float) -> float:
	return minf(float(st["speed"]) * lerpf(1.0, launch_mult, 0.35), 260.0)

# ------------------------------------------------------------------ direct-fire compensation
## Height (m, relative to the muzzle) of a direct-fire round at horizontal distance `dist`: gravity is `gk` of normal for the
## first `flat_t` seconds (the round flies nearly straight) and normal afterwards. Used to aim so the round arrives where the
## sight marker is, and by tests to prove the flight is a real trajectory, not a teleport.
static func sim_height(speed: float, pitch_deg: float, dist: float, gk: float, flat_t: float, g: float) -> float:
	var th: float = deg_to_rad(pitch_deg)
	var vx: float = speed * cos(th)
	var vy: float = speed * sin(th)
	var x := 0.0
	var y := 0.0
	var t := 0.0
	var dt := 0.01
	while x < dist and t < 12.0:
		var gg: float = g * (gk if t < flat_t else 1.0)
		vy -= gg * dt
		x += vx * dt
		y += vy * dt
		t += dt
	return y

## Pitch (deg) at which the round passes `dy` metres above/below the muzzle at horizontal distance `dist`.
static func compensate_pitch(st: Dictionary, speed: float, dist: float, dy: float, g: float) -> float:
	var lo: float = float(st["pitch_min"]) - 6.0
	var hi: float = float(st["pitch_max"]) + 12.0
	for i in 28:
		var mid: float = (lo + hi) * 0.5
		if sim_height(speed, mid, dist, float(st["gravity_k"]), float(st["flat_t"]), g) < dy:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5
