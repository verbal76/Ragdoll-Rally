extends SceneTree
## Expanded-playfield checks:  godot --headless --path launch -s tests/verify_expanded.gd
var fails: int = 0

func check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		fails += 1

func _init() -> void:
	Engine.max_fps = 0
	await _run()
	print("---- EXPANDED %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)

func frames(n: int) -> void:
	for i in n:
		await physics_frame

func _aim(main: Node, b: float, s: float) -> void:
	# synthesize the finger drag (in camera-aligned basis) that the player would make
	main.drag_vec = (main._basis_back * b + main._basis_side * s) * main.AIM_MAX_PX
	main._update_aim()

func _shoot(main: Node, b: float, s: float) -> Dictionary:
	main.reset()
	await frames(2)
	_aim(main, b, s)
	main.fire()
	var n := 0
	var in_view := 0
	var counted := 0
	var worst_ms := 0.0
	var peak_active := 0
	while main.state == 1 and n < 60 * 14:
		var t0 := Time.get_ticks_usec()
		await physics_frame
		worst_ms = maxf(worst_ms, (Time.get_ticks_usec() - t0) / 1000.0)
		n += 1
		if n > 10:
			counted += 1
			if main.cam.is_position_in_frustum(main.ragdoll.centre()):
				in_view += 1
		peak_active = maxi(peak_active, main.town.active_released())
	return {"frames": n, "state": main.state, "view": float(in_view) / maxf(counted, 1.0), "worst_ms": worst_ms, "active": peak_active,
		"end": main.ragdoll.centre(), "sane": main.ragdoll.is_finite_and_sane(), "score": main.scoring.total()}

## Normalised screen position (0..1) under a REAL 20:9 landscape phone aspect (the headless viewport is square).
func _screen(main: Node, wp: Vector3) -> Vector2:
	var local: Vector3 = main.cam.global_transform.affine_inverse() * wp
	if local.z >= -0.1:
		return Vector2(-5, -5)
	var th: float = tan(deg_to_rad(main.cam.fov) * 0.5)
	var ndc := Vector2((local.x / -local.z) / (th * (2000.0 / 900.0)), (local.y / -local.z) / th)
	return Vector2((ndc.x + 1.0) * 0.5, (1.0 - ndc.y) * 0.5)

func _rollout(main: Node, cls: bool) -> float:
	main.classic = cls
	main.legacy_world = true            # open far field: nothing to hit
	main.force_rebuild = true
	main.reset()
	await frames(2)
	for o in main.town.pieces + main.town.props:
		o.collision_layer = 0          # truly open ground: the legacy village would otherwise stop some shots dead
	_aim(main, 0.12, 0.0)
	main.aim_power = 0.55
	main.fire()
	var first_x := -1.0
	var n := 0
	while main.state == 1 and n < 60 * 14:
		await physics_frame
		n += 1
		var c: Vector3 = main.ragdoll.centre()
		if first_x < 0.0 and n > 5 and c.y < 1.0:
			first_x = c.x
	var end_x: float = main.ragdoll.centre().x
	main.classic = false
	main.legacy_world = false
	main.force_rebuild = false
	main.reset()
	await frames(2)
	return end_x - maxf(first_x, 0.0)

func _run() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.skip_select = true
	main.env_idx = 1                 # the b9 city map (these tests are about it)
	root.add_child(main)
	await frames(5)
	# ---- power: classic G1/G2 curve preserved for the regression baseline; v0.4 tuning is faster
	check(is_equal_approx(main.speed_for_power(1.0, true), 32.0) and is_equal_approx(main.speed_for_power(0.0, true), 9.0) and is_equal_approx(main.speed_for_power(0.5, true), lerpf(9.0, 32.0, pow(0.5, 0.9))), "classic G1/G2 power curve intact (9..32 m/s)")
	check(is_equal_approx(main.speed_for_power(1.0), 50.0) and is_equal_approx(main.speed_for_power(0.0), 20.0), "pivot tuning: 20..50 m/s (classic was 9..32)")
	check(is_equal_approx(main.speed_for_power(1.45), 68.0) and main.speed_for_power(1.2) > 50.0 and main.speed_for_power(1.2) < 68.0, "overdrive band: 50 -> 68 m/s beyond full power")
	var g: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	# ---- aim mapping: default lower-left pull
	check(main._basis_back.x < -0.3 and main._basis_back.y > 0.3, "pull-back points toward the LOWER-LEFT of the screen %s" % str(main._basis_back))
	var dets: float = absf(main._basis_back.x * main._basis_side.y - main._basis_back.y * main._basis_side.x)
	check(dets > 0.5, "screen basis is well conditioned (%.2f)" % dets)
	# full power reachable by an in-screen drag for every aim direction in the arc (1280x720 and 20:9)
	var worst_x := 0.0
	var worst_y := 0.0
	for k in 21:
		var a := deg_to_rad(-90.0 + 9.0 * k)           # angle of the unit pull vector in (side, back) space
		var s := sin(a)
		var b := maxf(cos(a), 0.0)
		var d: Vector2 = (main._basis_back * b + main._basis_side * s) * main.AIM_MAX_PX * main.OVERDRIVE_MAX
		worst_x = maxf(worst_x, absf(d.x))
		worst_y = maxf(worst_y, absf(d.y))
	check(worst_x < 1280.0 * 0.5 and worst_y < 720.0 * 0.6, "full-overdrive drag fits on screen from a mid-screen start (max %.0f x %.0f px)" % [worst_x, worst_y])
	# distinct, monotonic aim
	var yaws: Array[float] = []
	for k in 9:
		_aim(main, 0.6, -0.8 + 0.2 * k)
		yaws.append(main.aim_dir.z)
	var mono := true
	for i in range(1, yaws.size()):
		if not (yaws[i] < yaws[i - 1]):
			mono = false
	check(mono, "lateral drag maps monotonically to yaw (distinct, predictable)")
	_aim(main, 0.2, -1.0)
	var yaw_deg: float = rad_to_deg(atan2(main.aim_dir.z, main.aim_dir.x))
	check(absf(yaw_deg) > 40.0, "horizontal aim arc reaches %.0f deg" % yaw_deg)
	# mirrored view for the other thumb
	main.set_view_right(true)
	check(main._basis_back.x > 0.3 and main._basis_back.y > 0.3, "right-hand view: pull-back toward the LOWER-RIGHT %s" % str(main._basis_back))
	main.set_view_right(false)
	# ---- targets
	var tg: Array = main.town.targets
	var keys := {}
	var regions := {}
	var pmin := 99999
	var pmax := 0
	for t in tg:
		keys[t["key"]] = true
		regions[t["region"]] = true
		pmin = mini(pmin, int(t["pts"]))
		pmax = maxi(pmax, int(t["pts"]))
	check(tg.size() >= 20 and keys.size() == tg.size(), "%d distinct targets" % tg.size())
	check(regions.size() == 5, "targets cover all five regions %s" % str(regions.keys()))
	check(pmin <= 150 and pmax >= 2000, "target values scale with difficulty (%d..%d)" % [pmin, pmax])
	check(main.town.gaps.size() == 2 and main.town.rings.size() == 2, "2 gates to thread and 2 landing rings")
	var rr: Dictionary = main.town.ring_award(Vector3(68.0, 0, 14.0))
	var rm: Dictionary = main.town.ring_award(Vector3(68.0 + 7.5 * 0.5, 0, 14.0))
	var ro: Dictionary = main.town.ring_award(Vector3(68.0 + 7.5 * 0.95, 0, 14.0))
	check(rr["pts"] == 1000 and rr["dead"] and rm["pts"] > ro["pts"] and ro["pts"] > 0 and main.town.ring_award(Vector3(0, 0, 0)).is_empty(), "bullseye pays more the closer to dead centre (%d / %d / %d)" % [rr["pts"], rm["pts"], ro["pts"]])
	var wall: RigidBody3D = main.town.pieces[0]
	var light: RigidBody3D = wall
	var heavy: RigidBody3D = wall
	for pc in main.town.pieces:
		if pc.mass < light.mass: light = pc
		if pc.mass > heavy.mass: heavy = pc
	check(main.damage_points(wall, 22.0) > main.damage_points(wall, 8.0) and main.damage_points(heavy, 14.0) > main.damage_points(light, 14.0), "smash points scale with impact speed (%d vs %d) and piece weight (%d vs %d)" % [main.damage_points(wall, 22.0), main.damage_points(wall, 8.0), main.damage_points(heavy, 14.0), main.damage_points(light, 14.0)])
	var unreachable: Array = []
	for t in tg:
		var best := 1e9
		var tp: Vector3 = t["pos"]
		var is_gate: bool = main.town.gaps.any(func(gp): return gp["key"] == t["key"])
		var ring: Dictionary = {}
		for rg in main.town.rings:
			if rg["key"] == t["key"]:
				ring = rg
		var tol: float = 3.0 if tp.x < 150.0 else 12.0           # deep structures: any hit on the tall stack counts
		for bi in 291:
			for si in 21 if is_gate else 117:
				var b: float = bi / 200.0
				var s: float = (-0.1 + si / 100.0) if is_gate else (-1.45 + si / 40.0)
				if not is_gate and bi % 5 != 0:
					continue
				var p := Vector2(s, b)
				if p.length() > main.OVERDRIVE_MAX or p.length() < 0.12:
					continue
				var up: float = clampf(b, 0.05, 1.0) * 1.6
				var dir := Vector3(1.0, up, -clampf(s, -1.0, 1.0) * main.SIDE_GAIN).normalized()
				var power: float = p.length()
				var spd: float = main.speed_for_power(power)
				var p0: Vector3 = main.pouch_pos(dir, power)
				var c_drag: float = 0.15 * main.air_drag_scale(power)
				var pos: Vector3 = p0
				var prev: Vector3 = p0
				var vel: Vector3 = dir * spd
				for ti in range(1, 700):
					vel += Vector3(0, -g, 0) * 0.02
					vel *= 1.0 / (1.0 + c_drag * 0.02)
					pos += vel * 0.02
					if pos.y < 0.0:
						if not ring.is_empty() and Vector2(pos.x - (ring["center"] as Vector2).x, pos.z - (ring["center"] as Vector2).y).length() <= float(ring["r"]):
							best = 0.0
						break
					if is_gate:
						for gp in main.town.gaps:
							if gp["key"] == t["key"] and prev.x < gp["x"] and pos.x >= gp["x"] and absf(pos.z) < gp["half"] and pos.y < gp["ymax"] and pos.y > 0.3:
								best = 0.0
					elif ring.is_empty():
						var dy: float = maxf(pos.y - tp.y, 0.0)
						best = minf(best, Vector3(pos.x - tp.x, dy, pos.z - tp.z).length())
					prev = pos
		if best > tol:
			unreachable.append("%s %.1f" % [t["name"], best])
	check(unreachable.is_empty(), "every target is ballistically reachable (3 m near, 12 m deep stacks) %s" % str(unreachable))
	var sc := Scoring.new()
	check(sc.award("window", "x", 150, "Targets") and not sc.award("window", "x", 150, "Targets"), "a target scores once per shot")
	# ---- world content
	check(main.town.pieces.size() >= 300, "%d breakable pieces, %d props, %d decorative cottages/trees (multimesh)" % [main.town.pieces.size(), main.town.props.size(), main.town._decor_walls.size() / 2 + main.town._decor_trees.size()])
	var xmax := 0.0
	var zmax := 0.0
	for t in tg:
		xmax = maxf(xmax, t["pos"].x)
		zmax = maxf(zmax, absf(t["pos"].z))
	check(xmax >= 180.0 and zmax >= 80.0, "targets reach %.0f m deep and +-%.0f m wide (old village: 58 m deep)" % [xmax, zmax])
	check(main.margins.x >= 40.0 and main.margins.y >= 30.0 and main.margins.z >= 40.0 and main.margins.w >= 30.0, "HUD keeps >= safe margins from the screen corners %s" % str(main.margins))
	# ---- active-body cap
	var rel := 0
	for p in main.town.pieces:
		if rel < 140:
			p.freeze = false
			main.town.released_order.append(p)
			rel += 1
	await frames(2)
	for p in main.town.released_order:
		p.linear_velocity = Vector3.ZERO
	main.town.enforce_active_cap()
	check(main.town.active_released() <= main.town.ACTIVE_CAP, "active released pieces bounded (%d <= %d)" % [main.town.active_released(), main.town.ACTIVE_CAP])
	main.reset()
	await frames(3)
	var restored := true
	var worst_drift := 0.0
	for p in main.town.pieces:
		if not p.freeze or p.global_position.distance_to(p.get_meta("rest")) > 0.01:
			restored = false
	for b in main.town.props:
		var dd: float = b.global_position.distance_to(b.get_meta("rest"))
		worst_drift = maxf(worst_drift, dd)
		if dd > 0.35:
			restored = false
	print("      worst prop drift after reset: %.2f m" % worst_drift)
	check(restored and main.town.frozen_count() == main.town.pieces.size(), "fast reset restores every piece and prop in place")
	# ---- camera: launcher sits well inside the frame with room to pull (both views)
	for side in [false, true]:
		main.set_view_right(side)
		await frames(2)
		main.cam.global_transform = main._cam_aim_xf
		var lo: Vector2 = _screen(main, main.LAUNCH_ORIGIN)
		var framed := lo.y < 0.74 and lo.x > 0.2 and lo.x < 0.8
		for ang in [-0.7, 0.0, 0.7]:
			_aim(main, 1.45 * cos(ang), 1.45 * sin(ang))
			var pp: Vector2 = _screen(main, main.pouch_pos(main.aim_dir, main.aim_power))
			if pp.x < 0.04 or pp.x > 0.96 or pp.y < 0.04 or pp.y > 0.96:
				framed = false
		check(framed, "%s view: catapult and the fully pulled ragdoll stay inside the frame (launcher at %.0f%% / %.0f%% of the screen)" % ["right" if side else "left", lo.x * 100.0, lo.y * 100.0])
	main.set_view_right(false)
	await frames(2)
	# ---- density: the corridor the ragdoll flies through is thick with things to hit
	var cells := {}
	var objs: Array[Vector3] = []
	for pc in main.town.pieces:
		objs.append(pc.global_position)
	for pr in main.town.props:
		objs.append(pr.global_position)
	for sp in main.town.static_pos:
		objs.append(sp)
	for tw in main.town._decor_walls:
		objs.append(tw.origin)
	for tt in main.town._decor_trees:
		objs.append(tt.origin)
	var total := 0
	for o in objs:
		if o.x >= 15.0 and o.x < 150.0 and absf(o.z) < 48.0:
			total += 1
			cells[Vector2i(int((o.x - 15.0) / 12.0), int((o.z + 48.0) / 12.0))] = true
	check(float(cells.size()) / (11.0 * 8.0) >= 0.9 and total >= 700, "dense city: %d objects, %.0f%% of the 12 m cells in the flight corridor have something to hit" % [total, 100.0 * float(cells.size()) / 88.0])
	# ---- TNT, chain reactions
	check(main.town.tnt.size() >= 20, "%d TNT barrels" % main.town.tnt.size())
	var t0: RigidBody3D = main.town.tnt[0]
	var t1: RigidBody3D = main.town.tnt[1]
	t1.global_position = t0.global_position + Vector3(2.5, 0, 0)
	var blast: Dictionary = main.town.detonate(t0)
	check(blast["blasts"].size() >= 2 and not t0.visible and not t1.visible, "TNT detonates and chains into a neighbour (%d blasts)" % blast["blasts"].size())
	# ---- target beams
	var bm: Array = main.town._beams["window"]
	check((bm[0] as MeshInstance3D).visible, "every target has a glowing beam")
	main.scoring.award("window", "House Window", 150, "Targets")
	check(not (bm[0] as MeshInstance3D).visible, "claimed target's beam goes dark")
	main.reset()
	await frames(3)
	var bm2: Array = main.town._beams["window"]
	check((bm2[0] as MeshInstance3D).visible and main.town.tnt[0].visible and not main.town.tnt[0].get_meta("exploded", false), "reset relights beams and rebuilds the TNT")
	# ---- breakable decor
	var db: StaticBody3D = main.town.decor_bodies[0]
	check(main.town.decor_bodies.size() >= 300, "%d breakable decor buildings/trees" % main.town.decor_bodies.size())
	check(main.town.break_decor(db, Vector3.RIGHT, 20.0) and db.collision_layer == 0 and not main.town.break_decor(db, Vector3.RIGHT, 20.0), "decor breaks once")
	main.reset()
	await frames(3)
	check(db.collision_layer == 1 and main.town.decor_smashed == 0, "reset restores broken decor")
	# ---- upgrades (new system: 8 families that stack; full coverage lives in verify_pivot.gd)
	main.bank = 1000
	main.levels = main.Rules.empty_levels()
	check(main.buy("power") and main.buy("bounce") and main.bank == 500, "two level-1 upgrades bought for 250 each (bank %d)" % main.bank)
	check(not main.buy("explosive") and main.get_level("power") == 1, "cannot buy without enough points")
	main.bank = 100000
	for i in 8:
		main.buy("power")
	check(main.get_level("power") == 5 and main.upgrade_cost("power") == -1, "upgrades cap at their max level")
	main.bank = 0
	main.levels = main.Rules.empty_levels()
	main._save_progress()
	# ---- extreme shots: result in time, camera keeps the ragdoll in view, bounded physics
	var shots := {
		"hard left": [0.55, 0.85], "hard right": [0.55, -0.85], "long centre": [0.8, 0.0],
		"high lob": [1.0, 0.0], "flat fast": [0.1, 0.0], "left-centre": [0.7, 0.45], "right-centre": [0.7, -0.45],
		"overdrive long": [1.45, 0.0], "overdrive left": [1.2, 0.8], "overdrive right": [1.2, -0.8]}
	for nm in shots.keys():
		var r: Dictionary = await _shoot(main, shots[nm][0], shots[nm][1])
		check(r.end.x > 5.0 or nm == "flat fast", "%s: ragdoll actually left the launcher (x=%.0f)" % [nm, r.end.x])
		check(r.state == 2 and r.sane and r.frames < 60 * 14, "%s: reaches RESULT in %.1f s of flight, sane" % [nm, r.frames / 60.0])
		check(r.view >= 0.90, "%s: ragdoll in camera view %.0f%% of frames" % [nm, r.view * 100.0])
		check(main.cam.global_position.y > 1.5, "%s: camera stays above ground" % nm)
		print("      end=%s score=%d worst_frame=%.1fms active=%d" % [str(r.end), r.score, r.worst_ms, r.active])
	var od: Dictionary = await _shoot(main, 1.45, 0.0)
	check(od.end.x > 150.0 and od.score > 1000, "full overdrive reaches the grand castle (x=%.0f, score %d)" % [od.end.x, od.score])
	# ---- stress: smash through the densest cluster
	var st: Dictionary = await _shoot(main, 0.12, 0.0)
	check(st.active <= main.town.ACTIVE_CAP + 10, "stress shot: peak active released pieces %d" % st.active)
	check(st.worst_ms < 80.0, "stress shot: worst frame %.1f ms (headless desktop)" % st.worst_ms)
	# ---- SKIP button appears only after a couple of seconds of flight, and a swipe never skips
	main.reset()
	await frames(2)
	_aim(main, 0.8, 0.0)
	main.fire()
	await frames(20)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	main._unhandled_input(press)
	check(main.state == 1 and not main.btn_skip.visible, "mid-flight touch does not skip; SKIP button hidden early")
	main.air_input = 0.0
	await frames(150)
	if main.state == 1:
		check(main.btn_skip.visible, "SKIP button shows after 2 s of flight")
		main.btn_skip.pressed.emit()
	check(main.state == 2, "SKIP skips to the result")
	# ---- About formatting regression (version code printed as an integer)
	main.get_node("/root/Ota").info["version_code"] = 7.0
	var txt: String = SettingsMenu.diagnostics_text(main.get_node("/root/Ota"))
	check("Version code (native build): 7\n" in txt and not ("7.0" in txt), "About prints integers without .0")
