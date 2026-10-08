extends SceneTree
## Mayhem pass: 20-level scaling, impact energy / penetration, shell destruction (expand, punch, collapse, restore, budgets),
## save migration. Board-wide audits live in audit_boards.gd / verify_cities.gd.
##   godot --headless --path launch -s tests/verify_mayhem.gd
const Rules := preload("res://scripts/rules.gd")
const Destruction := preload("res://scripts/destruction.gd")
const CamSafe := preload("res://scripts/cam_safe.gd")
const DestructionProfile := preload("res://scripts/destruction_profile.gd")
var fails := 0
var main: Node

func check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		fails += 1

func _init() -> void:
	_run.call_deferred()

func _levels(l: int) -> Dictionary:
	var d: Dictionary = Rules.empty_levels()
	for k in Rules.MAYHEM_KEYS:
		d[k] = l
	return d

func _run() -> void:
	_pure()
	await _camera()
	await _shells()
	await _structure()
	await _blood()
	await _effects()
	print("---- MAYHEM %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)

func _pure() -> void:
	var st: Dictionary = Rules.CHARACTERS[0]["stats"]
	# 20-level scaling is monotone and strong at the top
	var prev: Dictionary = Rules.effective(st, _levels(0))
	var mono := true
	for l in range(1, 21):
		var e: Dictionary = Rules.effective(st, _levels(l))
		for k in ["launch_mult", "impact_power", "destruct_mult", "explode_radius", "explode_power", "range_cap", "apex_cap", "restitution", "ricochet_deg"]:
			if float(e[k]) < float(prev[k]):
				mono = false
		prev = e
	check(mono, "every mayhem number is monotone across levels 0..20")
	var e0: Dictionary = Rules.effective(st, _levels(0))
	var e20: Dictionary = Rules.effective(st, _levels(20))
	check(float(e20["destruct_mult"]) > 8.0 and float(e20["explode_radius"]) > 25.0 and float(e20["range_cap"]) >= 330.0, "Lv20 is absurd: destruct x%.1f, blast %.0f m, range cap %.0f m" % [e20["destruct_mult"], e20["explode_radius"], e20["range_cap"]])
	check(float(e0["destruct_mult"]) == 1.0 and Rules.mayhem_band(0) == "Stock" and Rules.mayhem_band(4) == "Ragdoll Chaos" and Rules.mayhem_band(8) == "Destructive Chaos" and Rules.mayhem_band(12) == "Building Wrecker" and Rules.mayhem_band(16) == "City Destroyer" and Rules.mayhem_band(20) == "Absurd Mayhem", "qualitative bands 1-4/5-8/9-12/13-16/17-20")
	check(Rules.crater_tier(1) == 1 and Rules.crater_tier(20) == 4 and Rules.crater_tier(0) == 0, "crater tiers scale with explosive level")
	# energy model: a wall of 6 masonry cells (tough 3.7 each)
	var costs: Array = []
	for i in 6:
		costs.append(Rules.piece_cost(3.7))
	var weak: Dictionary = Rules.punch_walk(Rules.punch_budget(30.0), costs)
	var mid: Dictionary = Rules.punch_walk(Rules.punch_budget(60.0), costs)
	var big: Dictionary = Rules.punch_walk(Rules.punch_budget(400.0), costs)
	check(bool(weak["blocked"]) and int(weak["n"]) < 6, "a weak hit is stopped inside the building (%d of 6 cells)" % weak["n"])
	check(int(mid["n"]) > int(weak["n"]), "more energy breaks more pieces (%d -> %d)" % [weak["n"], mid["n"]])
	check(not bool(big["blocked"]) and int(big["n"]) == 6 and float(big["keep"]) > 0.9, "overwhelming energy exits the far side keeping %.0f%% momentum" % (100.0 * float(big["keep"])))
	check(float(weak["keep"]) < float(big["keep"]), "momentum kept rises with energy")
	var tap: Dictionary = Rules.punch_walk(Rules.punch_budget(7.0), [Rules.piece_cost(6.5), Rules.piece_cost(6.5)], true)
	check(int(tap["n"]) == 1 and bool(tap["blocked"]), "a hit just above a piece's toughness breaks that piece and nothing behind it")
	# typical throws vs the level: speed 28 m/s
	var dens: Array[int] = []
	for l in [0, 5, 10, 15, 20]:
		var fe: Dictionary = Rules.effective(st, _levels(l))
		var effk: float = 28.0 * float(fe["impact_power"]) * float(fe["destruct_mult"])
		var w: Dictionary = Rules.punch_walk(Rules.punch_budget(effk), _costs(40, 3.7))
		dens.append(int(w["n"]))
	print("      cells broken (28 m/s) at Lv 0/5/10/15/20: ", dens)
	check(dens[0] < dens[1] and dens[1] < dens[2] and dens[2] <= dens[3] and dens[4] == 40, "cells broken rise with Destruction level and Lv20 clears a 40-cell path")
	check(dens[0] <= 3, "stock Ragnar chips a building rather than tunnelling it (%d cells)" % dens[0])
	# save migration: a maxed v13 save keeps its spending power, nothing is lost
	var old: Dictionary = Rules.empty_levels()
	old["power"] = 5
	old["destruction"] = 5
	old["explosive"] = 4
	old["bounce"] = 2
	var mig: Dictionary = Rules.migrate_levels(old)
	var lv: Dictionary = mig["levels"]
	check(int(lv["power"]) >= 8 and int(lv["destruction"]) >= 7 and int(lv["explosive"]) >= 6 and int(lv["bounce"]) >= 3, "migration re-spends old credits on the 20-level curve (%s)" % str(lv))
	var spent_old := 0
	var spent_new := 0
	for k in Rules.LEGACY_COSTS.keys():
		for i in int(old.get(k, 0)):
			spent_old += int((Rules.LEGACY_COSTS[k] as Array)[i])
		for i in int(lv[k]):
			spent_new += Rules.mayhem_cost(k, i)
	check(spent_new + int(mig["refund"]) == spent_old, "migration conserves credits exactly (%d + refund %d = %d)" % [spent_new, mig["refund"], spent_old])
	var zero: Dictionary = Rules.migrate_levels(Rules.empty_levels())
	check(int(zero["refund"]) == 0 and int((zero["levels"] as Dictionary)["power"]) == 0, "empty save migrates to empty")

func _costs(n: int, tough: float) -> Array:
	var a: Array = []
	for i in n:
		a.append(Rules.piece_cost(tough))
	return a

func _shells() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.skip_select = true
	main.force_rebuild = true
	root.add_child(main)
	for i in 5:
		await process_frame
	main.start_game(0, Rules.env_index("hill_skyline"))
	for i in 4:
		await process_frame
	var T = main.town
	var shells: Array = []
	for p in T.pieces:
		if Destruction.is_shell(p):
			shells.append(p)
	check(shells.size() > 60, "hillside buildings are destruction shells (%d)" % shells.size())
	var n_before: int = T.pieces.size()
	var sh: RigidBody3D = shells[shells.size() / 2]
	var cells: Array = Destruction.expand(T, sh)
	check(cells.size() >= 4 and not T.pieces.has(sh) and T.pieces.has(cells[0]), "expanding a shell swaps it for %d frozen cells" % cells.size())
	var vol := 0.0
	for c in cells:
		var s: Vector3 = (c.get_meta("half") as Vector3) * 2.0
		vol += s.x * s.y * s.z
	var sv: float = float(Destruction._shell_volume(sh))
	check(absf(vol - sv) / sv < 0.12, "cells tile the shell volume (%.0f vs %.0f m3)" % [vol, sv])
	# restore
	Destruction.restore_all(T)
	check(T.pieces.has(sh) and not T.pieces.has(cells[0]) and sh.collision_layer == 4 and T.shells_open.is_empty(), "restore brings the shell back and cells go dormant")
	# punch at the building's mid height from the launch side
	var res_lo: Dictionary = {}
	var res_hi: Dictionary = {}
	var out_lo := 0
	var kept_rest := Vector3.ZERO
	for lvl in [0, 20]:
		T = main.town
		sh = null
		for p in T.pieces:
			if Destruction.is_shell(p) and p.get_meta("mat") == "masonry":
				sh = p
				break
		var pos: Vector3 = sh.global_position - Vector3(3.0, 0, 0)
		var fe: Dictionary = Rules.effective(Rules.CHARACTERS[0]["stats"], _levels(lvl))
		var effk: float = 30.0 * float(fe["impact_power"]) * float(fe["destruct_mult"])
		var r: Dictionary = Destruction.punch(T, sh, pos, Vector3.RIGHT, effk, T.smash_push)
		print("      Lv%d punch: released %d, dissolved %d, keep %.2f, blocked %s" % [lvl, (r["released"] as Array).size(), (r["dissolved"] as Array).size(), r["keep"], r["blocked"]])
		if lvl == 0:
			res_lo = r
			out_lo = (r["released"] as Array).size()
		else:
			res_hi = r
		main.reset()
		for i in 3:
			await process_frame
		T = main.town
	check(out_lo >= 1, "even a stock hit always releases the piece it touched")
	check((res_hi["released"] as Array).size() + (res_hi["dissolved"] as Array).size() > out_lo and float(res_hi["keep"]) > float(res_lo["keep"]), "Lv20 breaks more and keeps more momentum than Lv0")
	check((res_hi["released"] as Array).size() <= Destruction.MAX_RELEASE_PER_IMPACT, "one impact never frees more than %d rigid bodies" % Destruction.MAX_RELEASE_PER_IMPACT)
	check(T.shells_open.is_empty(), "a fresh run starts with every shell closed")

func _box_body(pos: Vector3, size: Vector3, rigid: bool = false) -> PhysicsBody3D:
	var b: PhysicsBody3D = RigidBody3D.new() if rigid else StaticBody3D.new()
	b.collision_layer = 4 if rigid else 1
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	b.position = pos
	root.add_child(b)
	return b

func _camera() -> void:
	var wall := _box_body(Vector3(0, 10, -8), Vector3(40, 20, 4))           # a building between Ragnar and the camera
	var ground := _box_body(Vector3(0, -1, 0), Vector3(200, 2, 200))
	for i in 3:
		await physics_frame
	var space: PhysicsDirectSpaceState3D = root.world_3d.direct_space_state
	var focus := Vector3(0, 6, 0)
	var desired := Vector3(0, 8, -20)                                         # wants to sit behind the wall
	var safe: Vector3 = CamSafe.resolve(space, focus, desired)
	check(not CamSafe.inside_solid(space, safe), "camera never ends up inside the building (at %s)" % str(safe))
	check(CamSafe.clear_fraction(space, focus, safe, CamSafe.RADIUS * 0.5) >= 0.99, "camera keeps a line of sight to the ragdoll")
	check(focus.distance_to(safe) >= CamSafe.MIN_DIST, "camera stays at least %.1f m from Ragdoll (%.1f)" % [CamSafe.MIN_DIST, focus.distance_to(safe)])
	var open_pos := Vector3(0, 8, 14)
	check(CamSafe.resolve(space, focus, open_pos).is_equal_approx(open_pos), "an unobstructed camera is not moved")
	# a released (moving) piece does not block the lens
	var chunk := _box_body(Vector3(0, 6, 10), Vector3(3, 3, 3), true) as RigidBody3D
	chunk.freeze = false
	chunk.gravity_scale = 0.0
	for i in 2:
		await physics_frame
	check(CamSafe.resolve(space, focus, open_pos).is_equal_approx(open_pos), "released debris never blocks the camera")
	# focus buried in a wall (tunnelling through a building): camera climbs out instead of sitting in the masonry
	var inner := Vector3(0, 10, -8)
	var s2: Vector3 = CamSafe.resolve(space, inner, inner + Vector3(0, 0, -10))
	check(not CamSafe.inside_solid(space, s2), "camera recovers outside the structure when Ragdoll is inside it (%s)" % str(s2))
	# ground: camera above the terrain
	var low: Vector3 = CamSafe.resolve(space, Vector3(0, 1.5, 0), Vector3(0, -0.5, 20))
	check(low.y > 0.0 or not CamSafe.inside_solid(space, low), "camera is not placed under the ground")
	wall.queue_free()
	ground.queue_free()
	chunk.queue_free()

func _blood() -> void:
	main.gore = true
	main.fx.gore = true
	# a wall facing -X (blood from a ragdoll flying in +X), a sloped roof, and ground
	var wall := _box_body(Vector3(500, 10, 0), Vector3(2, 20, 30))
	var roof := _box_body(Vector3(500, 30, 60), Vector3(20, 1, 20))
	roof.rotation.z = deg_to_rad(25.0)
	var ground := _box_body(Vector3(500, -1, 120), Vector3(60, 2, 60))
	for i in 3:
		await physics_frame
	var ok_wall := true
	var pl: Array = main._blood_mark(Vector3(498.0, 8, 0), Vector3.RIGHT, 1.0, 3)
	for p in pl:
		if absf(float(p["pos"].x) - 499.0) > 0.05 or float(p["normal"].dot(Vector3.LEFT)) < 0.98:
			ok_wall = false
	check(pl.size() >= 2 and ok_wall, "blood on a wall sits ON the wall surface, normal facing out (%d marks)" % pl.size())
	var pr: Array = main._blood_mark(Vector3(500, 32, 60), Vector3.DOWN, 1.0, 2)
	var ok_roof := not pr.is_empty()
	for p in pr:
		var n: Vector3 = p["normal"]
		if n.y < 0.85 or n.y > 0.97:
			ok_roof = false
	check(ok_roof, "blood on a sloped roof follows the slope (normal y %.2f)" % (float(pr[0]["normal"].y) if not pr.is_empty() else -1.0))
	var pg: Array = main._blood_mark(Vector3(500, 1, 120), Vector3.DOWN, 1.0, 2)
	check(not pg.is_empty() and absf(float(pg[0]["pos"].y)) < 0.05 and float(pg[0]["normal"].y) > 0.99, "blood on the ground lies on the ground")
	check(main._blood_mark(Vector3(498.0, 8, 300), Vector3.RIGHT, 1.0, 0).is_empty(), "no surface in reach -> no floating blood")
	# a mark on a moving chunk rides it
	var chunk := _box_body(Vector3(500, 10, -60), Vector3(4, 4, 4), true) as RigidBody3D
	chunk.freeze = true
	for i in 2:
		await physics_frame
	var before: int = main.fx._splat_follow.size()
	var pc: Array = main._blood_mark(Vector3(500, 10, -63), Vector3.BACK, 1.0, 0)
	var host_found := false
	for h in main.fx._splat_follow:
		if h == chunk:
			host_found = true
	check(not pc.is_empty() and host_found, "blood on a building chunk is attached to the chunk (moves/falls with it)")
	chunk.freeze = false
	chunk.gravity_scale = 0.0
	chunk.linear_velocity = Vector3(0, 0, -10)
	var pos0: Vector3 = Vector3.ZERO
	for i in main.fx._splats.size():
		if main.fx._splat_follow[i] == chunk:
			pos0 = main.fx._splats[i].global_position
	for i in 20:
		await process_frame
		await physics_frame
	var moved := 0.0
	for i in main.fx._splats.size():
		if main.fx._splat_follow[i] == chunk:
			moved = main.fx._splats[i].global_position.distance_to(pos0)
	check(moved > 1.0, "the attached mark followed the moving chunk (%.1f m)" % moved)
	wall.queue_free()
	roof.queue_free()
	ground.queue_free()
	chunk.queue_free()

func _effects() -> void:
	main.start_game(0, Rules.env_index("hill_steep"))
	for i in 4:
		await process_frame
	var T = main.town
	# explosion radius / power scale with the level, craters scale with tier, effects pools stay bounded
	var res1: Dictionary = T.explode(Vector3(60, 0, 0), Rules.blast_radius(1), Rules.blast_power(1))
	var res20: Dictionary = T.explode(Vector3(60, 0, 0), Rules.blast_radius(20), Rules.blast_power(20))
	check((res20["released"] as Array).size() >= (res1["released"] as Array).size(), "a Lv20 blast frees at least as many pieces as Lv1 (%d vs %d)" % [(res20["released"] as Array).size(), (res1["released"] as Array).size()])
	var c1: float = main.fx.crater(Vector3(40, 0, 40), Vector3.UP, Rules.blast_radius(3), Rules.crater_tier(3))
	var c4: float = main.fx.crater(Vector3(40, 0, 60), Vector3.UP, Rules.blast_radius(20), Rules.crater_tier(20))
	check(c4 > c1 * 3.0, "catastrophic crater is much larger than a small one (%.1f vs %.1f m)" % [c4, c1])
	for i in 20:
		main.fx.crater(Vector3(40 + i, 0, 80), Vector3.UP, 20.0, 4)
	var vis := 0
	for n in main.fx._craters:
		if n.visible:
			vis += 1
	check(vis <= main.fx.CRATER_POOL, "crater pool is bounded (%d <= %d)" % [vis, main.fx.CRATER_POOL])
	var flames: int = 0
	for u in main.fx._flame_user:
		if u != 0:
			flames += 1
	check(flames <= main.fx.FLAME_POOL, "flames stay inside the pool (%d)" % flames)
	# cinematic slow motion: only significant events, merges, bounded, recovers
	check(Rules.slowmo_weight(2, 40.0) < Rules.SLOWMO_THRESHOLD, "a chipped wall does not trigger slow motion")
	check(Rules.slowmo_weight(14, 120.0) >= 0.9 and Rules.slowmo_weight(0, 0.0, 30.0) >= 0.9, "a levelled building or a Lv20 blast does")
	var st: Dictionary = Rules.slowmo_new()
	var now := 0.0
	var min_scale := 1.0
	var merges_ok := true
	for step in 400:
		var ev := 0.0
		if step == 10:
			ev = 0.8
		elif step == 22 or step == 35:
			ev = 0.9
		st = Rules.slowmo_step(st, now, 0.016, ev)
		min_scale = minf(min_scale, float(st["scale"]))
		now += 0.016
		if step == 30 and float(st["scale"]) > 0.6:
			merges_ok = false                     # events inside the window keep the dip going, they do not restart it
	check(min_scale >= Rules.SLOWMO_MIN_SCALE - 0.001 and min_scale < 0.5, "slow motion dips to %.2f, never below the %.2f floor" % [min_scale, Rules.SLOWMO_MIN_SCALE])
	check(merges_ok, "close events merge into one slow moment")
	check(absf(float(st["scale"]) - 1.0) < 0.001, "time returns to normal after the moment")
	check(float(st["spent"]) < Rules.SLOWMO_RUN_BUDGET, "a chain stays inside the per-run slow-motion budget (%.1f s)" % float(st["spent"]))
	st = Rules.slowmo_new()
	now = 0.0
	for step in 2000:
		st = Rules.slowmo_step(st, now, 0.016, 1.0)
		now += 0.016
	check(float(st["spent"]) <= Rules.SLOWMO_RUN_BUDGET + 1.5 and float(st["scale"]) == 1.0, "even constant events end in normal time once the budget is spent")

func _structure() -> void:
	main.force_rebuild = false
	main.start_game(0, Rules.env_index("downtown"))
	for i in 4:
		await process_frame
	var T = main.town
	# stacked storeys: remove the support of the upper segment and it falls
	var lower: RigidBody3D = null
	for p in T.pieces:
		if Destruction.is_shell(p) and p.has_meta("above") and is_instance_valid(p.get_meta("above")):
			lower = p
			break
	check(lower != null, "tall buildings are stacks of linked storeys")
	if lower != null:
		var upper: RigidBody3D = lower.get_meta("above")
		var cells: Array = Destruction.expand(T, lower)
		var top_f := -1
		for c in cells:
			top_f = maxi(top_f, (c.get_meta("cidx") as Vector3i).y)
		var rel: Array = []
		for c in cells:
			if (c.get_meta("cidx") as Vector3i).y == top_f and c.get_meta("kind") != "roof":
				T.release(c, Vector3.ZERO)
				rel.append(c)
		var fell: Array = Destruction.collapse(T, rel)
		check(fell.size() >= 2 and not T.pieces.has(upper), "removing a storey's support drops the storeys above it (%d pieces fell)" % fell.size())
	# a designer profile overrides the material default
	var shell2: RigidBody3D = null
	for p in T.pieces:
		if Destruction.is_shell(p) and not p.has_meta("above") and not p.has_meta("below"):
			shell2 = p
			break
	if shell2 != null:
		var prof := DestructionProfile.new()
		prof.cell_tough = 0.25
		shell2.set_meta("profile", prof)
		var tough: float = float(shell2.get_meta("tough"))
		var cs: Array = Destruction.expand(T, shell2)
		check(absf(float((cs[0] as RigidBody3D).get_meta("tough")) - tough * 0.25) < 0.01, "a DestructionProfile resource overrides the material defaults")
	# simulation budget: past ACTIVE_HARD pieces dissolve to debris instead of becoming bodies
	var frozen: Array = []
	for p in T.pieces:
		if p.freeze and not p.get_meta("capped", false):
			frozen.append(p)
	var before_live: int = T.active_released()
	var n_rel := 0
	for p in frozen:
		if n_rel >= T.ACTIVE_HARD + 40:
			break
		T.release(p, Vector3.ZERO)
		n_rel += 1
	var live: int = T.active_released()
	check(live <= T.ACTIVE_HARD + 2, "releasing %d pieces never simulates more than the budget (%d live, budget %d)" % [n_rel, live, T.ACTIVE_HARD])
	var dis := 0
	for p in T.pieces:
		if p.get_meta("dissolved", false):
			dis += 1
	check(dis >= 30, "the overflow dissolved into debris instead (%d pieces)" % dis)
	# fast reset (no rebuild) restores everything: shells, dissolved pieces, positions
	var town_before = T
	main.reset()
	for i in 3:
		await process_frame
	T = main.town
	var all_back := true
	var open_cells := 0
	for p in T.pieces:
		if not p.freeze or p.collision_layer != 4 or not p.visible:
			all_back = false
		if p.has_meta("shell_of"):
			open_cells += 1
	check(T == town_before and T.shells_open.is_empty() and all_back and open_cells == 0, "fast reset: same world, every shell closed, every dissolved or released piece restored")
	main.force_rebuild = true
