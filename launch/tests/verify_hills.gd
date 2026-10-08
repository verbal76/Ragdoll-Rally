extends SceneTree
## Hillside cities: terrain shape, procedural-generation sanity over several seeds, launch-corridor fairness, target reachability under the
## launch governor, first-interaction distribution (ideal throws), and real physics throws (stability / performance).
##   godot --headless --path launch -s tests/verify_hills.gd
const Rules := preload("res://scripts/rules.gd")
const Terrain := preload("res://scripts/terrain.gd")
const Hillside := preload("res://scripts/hillside.gd")
var fails := 0
var main: Node
var table: Array = []

func check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		fails += 1

func frames(n: int) -> void:
	for i in n:
		await process_frame

func _init() -> void:
	Engine.max_fps = 0
	_run.call_deferred()

func _fin(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)

## SAT overlap of two yawed rectangles in the XZ plane (centre, half-extents, yaw).
func _rect_overlap(ca: Vector2, ha: Vector2, ya: float, cb: Vector2, hb: Vector2, yb: float) -> bool:
	var axes: Array[Vector2] = [Vector2(cos(ya), -sin(ya)), Vector2(sin(ya), cos(ya)), Vector2(cos(yb), -sin(yb)), Vector2(sin(yb), cos(yb))]
	var d: Vector2 = cb - ca
	for ax in axes:
		var ra: float = absf(ax.dot(Vector2(cos(ya), -sin(ya)))) * ha.x + absf(ax.dot(Vector2(sin(ya), cos(ya)))) * ha.y
		var rb: float = absf(ax.dot(Vector2(cos(yb), -sin(yb)))) * hb.x + absf(ax.dot(Vector2(sin(yb), cos(yb)))) * hb.y
		if absf(ax.dot(d)) > ra + rb - 0.05:
			return false
	return true

## Can a legal launch (soft-limited pitch, governed speed, lateral aim within +-50 deg) pass through `p`? Ignores collisions.
func _reachable(p: Vector3) -> bool:
	var launch := Vector3(0, 2.3, 0)
	var dx: float = p.x - launch.x
	var dz: float = p.z - launch.z
	var dist: float = sqrt(dx * dx + dz * dz)
	if absf(atan2(dz, dx)) > deg_to_rad(50.0) or dist < 1.0:
		return false
	var g: float = Rules.g_eff()
	for pd in range(4, 39, 1):
		var th: float = deg_to_rad(float(pd))
		var c: float = cos(th)
		var den: float = 2.0 * c * c * (dist * tan(th) + launch.y - p.y)
		if den <= 0.0:
			continue
		var v: float = sqrt(g * dist * dist / den)
		if v > 68.0 or v < 8.0:
			continue
		if Rules.ideal_range(v, th) <= Rules.RANGE_CAP_BASE + Rules.MAYHEM_MAX * Rules.RANGE_CAP_PER_LEVEL + 0.5 and Rules.ideal_apex(v, th) <= Rules.APEX_CAP_BASE + Rules.MAYHEM_MAX * Rules.APEX_CAP_PER_LEVEL + 0.5:
			return true
	return false

## Ideal (drag-free) flight from the launcher: first x where it meets terrain or a building footprint+height. Returns {x, hit}.
func _first_hit(ter, lots: Array, pitch_deg: float, speed: float, yaw_deg: float) -> Dictionary:
	var th: float = deg_to_rad(pitch_deg)
	var yw: float = deg_to_rad(yaw_deg)
	var vx: float = speed * cos(th) * cos(yw)
	var vz: float = speed * cos(th) * sin(yw)
	var vy: float = speed * sin(th)
	var g: float = Rules.g_eff()
	var t: float = 0.0
	while t < 12.0:
		t += 0.05
		var x: float = vx * t
		var z: float = vz * t
		var y: float = 2.3 + vy * t - 0.5 * g * t * t
		if x > Terrain.X1 or absf(z) > 130.0:
			return {"x": x, "hit": "wall"}
		if y < ter.height(x, z) + 0.2:
			return {"x": x, "hit": "terrain"}
		for lt in lots:
			var sz: Vector3 = lt["size"]
			var tp: Vector3 = lt["pos"]
			if y <= tp.y and y >= tp.y - sz.y and _rect_overlap(Vector2(x, z), Vector2(0.4, 0.4), 0.0, Vector2(tp.x, tp.z), Vector2(sz.x * 0.5, sz.z * 0.5), float(lt["yaw"])):
				return {"x": x, "hit": "building"}
	return {"x": 999.0, "hit": "none"}

func _run() -> void:
	# ========================================================================= terrain shape (each preset, 3 seeds)
	for h in Rules.HILLS:
		for sv in [0, 1, 2]:
			var pr: Dictionary = (h as Dictionary).duplicate()
			pr["seed"] = int(pr["seed"]) + sv * 313
			var ter := Terrain.new(pr)
			var tag: String = "%s/seed+%d" % [h["id"], sv * 313]
			var pad_ok := true
			for x in range(-25, 15, 5):
				for z in range(-30, 31, 10):
					if absf(ter.height(float(x), float(z))) > 0.001:
						pad_ok = false
			check(pad_ok, "%s: launch pad is flat at y = 0" % tag)
			var mn: float = 999.0
			var mx: float = -999.0
			var steep: float = 0.0
			for x in range(0, 216, 5):
				for z in range(-128, 129, 8):
					var hh: float = ter.height(float(x), float(z))
					mn = minf(mn, hh)
					mx = maxf(mx, hh)
					if x > 30:
						steep = maxf(steep, ter.slope(float(x), float(z)))
			check(mn >= -0.001 and mx > 14.0 and mx < 75.0, "%s: terrain 0..%.0f m, never below the launch pad" % [tag, mx])
			check(ter.height(150.0, 0.0) > ter.height(60.0, 0.0) + 2.0 or float(pr["valley"]) > 4.0, "%s: the land rises away from the launcher (h(60)=%.1f, h(150)=%.1f)" % [tag, ter.height(60.0, 0.0), ter.height(150.0, 0.0)])
			check(steep < 0.95, "%s: no cliff walls (max slope %.2f)" % [tag, steep])
	# ========================================================================= generator sanity per preset and seed
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.skip_select = true
	main.force_rebuild = true
	root.add_child(main)
	await frames(5)
	var sigs := {}
	for h in Rules.HILLS:
		for sv in [-1, 1, 2, 3]:
			Hillside.seed_override = -1 if sv < 0 else int(h["seed"]) + sv * 313
			var tag2: String = "%s/%s" % [h["id"], "own seed" if sv < 0 else "seed+%d" % (sv * 313)]
			var t0: int = Time.get_ticks_msec()
			main.start_game(0, Rules.env_index(str(h["id"])))
			await frames(3)
			var gen_ms: int = Time.get_ticks_msec() - t0
			var T = main.town
			var ter = T.terrain
			var st: Dictionary = Hillside.last_stats
			var lots: Array = st["lots"]
			check(lots.size() >= 70, "%s: %d buildings across %d contour streets x %d climbing streets" % [tag2, lots.size(), int(st["contours"]), int(st["climbs"])])
			# floating / buried / overlapping
			var floating := 0
			var buried := 0
			for lt in lots:
				var sz: Vector3 = lt["size"]
				var tp: Vector3 = lt["pos"]
				var hmin: float = 1e9
				var hmax: float = -1e9
				for sx in [-0.5, 0.0, 0.5]:
					for sz2 in [-0.5, 0.0, 0.5]:
						var yw2: float = lt["yaw"]
						var q: Vector2 = Vector2(tp.x, tp.z) + Vector2(cos(yw2), -sin(yw2)) * sz.x * sx + Vector2(sin(yw2), cos(yw2)) * sz.z * sz2
						var gh: float = ter.height(q.x, q.y)
						hmin = minf(hmin, gh)
						hmax = maxf(hmax, gh)
				var bottom: float = tp.y - sz.y
				if bottom > hmin + 0.05:
					floating += 1                       # the body must reach the lowest ground of its footprint
				if tp.y - hmax < 2.4:
					buried += 1                         # the roof must clear the highest ground by a storey
			check(floating == 0 and buried == 0, "%s: no floating (%d) or buried (%d) buildings" % [tag2, floating, buried])
			var overlaps := 0
			for i in lots.size():
				for j in range(i + 1, lots.size()):
					var a: Dictionary = lots[i]
					var b: Dictionary = lots[j]
					if Vector2(a["pos"].x - b["pos"].x, a["pos"].z - b["pos"].z).length() > 34.0:
						continue
					if _rect_overlap(Vector2(a["pos"].x, a["pos"].z), Vector2(a["size"].x, a["size"].z) * 0.5, a["yaw"], Vector2(b["pos"].x, b["pos"].z), Vector2(b["size"].x, b["size"].z) * 0.5, b["yaw"]):
						overlaps += 1
						if overlaps <= 6:
							print("      overlap ", a["tag"], " ", a["kind"], Vector3(int(a["pos"].x), int(a["pos"].y), int(a["pos"].z)), a["size"], "  vs  ", b["tag"], " ", b["kind"], Vector3(int(b["pos"].x), int(b["pos"].y), int(b["pos"].z)), b["size"])
			check(overlaps <= 2, "%s: buildings do not intersect each other (%d overlaps)" % [tag2, overlaps])
			# launcher corridor: nothing solid near the launcher or on the opening lane
			var near := 0
			for p in T.pieces:
				var q: Vector3 = p.global_position
				if q.x < 30.0 and absf(q.z) < 20.0:
					near += 1
			check(near == 0, "%s: opening corridor is clear (%d solids in x<30, |z|<20)" % [tag2, near])
			# coverage (no dominant empty areas) over 30 m cells of the urban region
			var cells := {}
			for p in T.pieces:
				var q2: Vector3 = p.global_position
				cells[Vector2i(int(q2.x / 30.0), int(q2.z / 30.0))] = true
			var total_cells := 0
			var covered := 0
			for cx in range(1, 7):
				for cz in range(-4, 4):
					total_cells += 1
					if cells.has(Vector2i(cx, cz)):
						covered += 1
			check(float(covered) / float(total_cells) >= 0.55, "%s: built-up coverage %d/%d cells" % [tag2, covered, total_cells])
			# variety: distinct footprint/height/colour combinations
			var kinds := {}
			for lt in lots:
				kinds["%d_%d_%d" % [int(lt["size"].x), int(lt["size"].y), int(lt["size"].z)]] = true
			check(kinds.size() >= 25, "%s: %d distinct building shapes (no repeated-clone neighbourhoods)" % [tag2, kinds.size()])
			# targets: reachable under the real governor, on the map
			var bad: Array = []
			for tg in T.targets:
				if not _reachable(tg["pos"]):
					bad.append(str(tg["name"]))
			check(T.targets.size() >= 5 and bad.is_empty(), "%s: %d targets, all ballistically reachable %s" % [tag2, T.targets.size(), str(bad)])
			# ideal throws: where does the first interaction happen? (not immediate, not a free flight over everything)
			var early := 0
			var over := 0
			var n_throws := 0
			var xs: Array = []
			for pd in [6.0, 10.0, 14.0, 18.0, 22.0, 28.0, 34.0]:
				for spd in [26.0, 36.0, 46.0, 58.0, 68.0]:
					for yw in [-30.0, -12.0, 0.0, 12.0, 30.0]:
						var gv: float = Rules.governed_speed(spd, deg_to_rad(pd), {})
						var r: Dictionary = _first_hit(ter, lots, pd, gv, yw)
						if Rules.ideal_range(gv, deg_to_rad(pd)) < 45.0:
							continue                         # a throw that cannot even leave the launch pad says nothing about the layout
						n_throws += 1
						xs.append(r["x"])
						if float(r["x"]) < 34.0:
							early += 1
						if r["hit"] == "wall":
							over += 1
			xs.sort()
			var med: float = xs[xs.size() / 2]
			check(float(early) / float(n_throws) < 0.25, "%s: only %d%% of ideal throws touch anything before x = 34 (launch corridor fair)" % [tag2, int(100.0 * float(early) / float(n_throws))])
			check(float(over) / float(n_throws) < 0.05, "%s: only %d%% of ideal throws fly over the whole city (median first contact x = %.0f)" % [tag2, int(100.0 * float(over) / float(n_throws)), med])
			check(gen_ms < 3000, "%s: generated + loaded in %d ms (headless desktop)" % [tag2, gen_ms])
			sigs["%s_%d" % [h["id"], sv]] = "%d_%d_%d" % [lots.size(), T.pieces.size(), int(Hillside.last_stats["trees"])]
	Hillside.seed_override = -1
	var distinct := {}
	for k in sigs.keys():
		distinct[sigs[k]] = true
	check(distinct.size() >= sigs.size() - 1, "every preset / seed produces a different city (%d signatures for %d maps)" % [distinct.size(), sigs.size()])
	# determinism: same preset twice -> same layout
	main.start_game(0, Rules.env_index("hill_steep"))
	await frames(3)
	var h1: int = _layout_hash(main.town)
	main.start_game(0, Rules.env_index("hill_steep"))
	await frames(3)
	check(_layout_hash(main.town) == h1, "deterministic: hill_steep loads with an identical layout twice (%d)" % h1)
	print("---- HILLS %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)

func _layout_hash(T) -> int:
	var h: int = 17
	for p in T.pieces:
		var q: Vector3 = p.global_position
		h = (h * 31 + int(q.x * 50.0) * 7 + int(q.y * 50.0) * 13 + int(q.z * 50.0) * 17) & 0x7fffffff
	return h
