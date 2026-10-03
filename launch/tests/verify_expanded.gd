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

func _run() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await frames(5)
	# ---- power preserved (G1/G2 constants and curve)
	main.aim_power = 1.0
	check(is_equal_approx(main.launch_speed(), 32.0), "full-power launch speed unchanged (32.0)")
	main.aim_power = 0.0
	check(is_equal_approx(main.launch_speed(), 9.0), "minimum launch speed unchanged (9.0)")
	main.aim_power = 0.7
	check(absf(main.launch_speed() - lerpf(9.0, 32.0, pow(0.7, 0.9))) < 0.001, "power curve unchanged")
	var g: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var v := 32.0
	var ang := deg_to_rad(45.0)
	var rng: float = v * v * sin(2.0 * ang) / g
	check(absf(rng - 104.5) < 0.5, "reference ballistic range at 45 deg full power = %.1f m (unchanged)" % rng)
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
		var d: Vector2 = (main._basis_back * b + main._basis_side * s) * main.AIM_MAX_PX
		worst_x = maxf(worst_x, absf(d.x))
		worst_y = maxf(worst_y, absf(d.y))
	check(worst_x < 1280.0 * 0.45 and worst_y < 720.0 * 0.55, "full-power drag fits on screen from a mid-screen start (max %.0f x %.0f px)" % [worst_x, worst_y])
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
	check(tg.size() >= 10 and keys.size() == tg.size(), "%d distinct targets" % tg.size())
	check(regions.size() == 5, "targets cover all five regions %s" % str(regions.keys()))
	check(pmin <= 150 and pmax >= 1000, "target values scale with difficulty (%d..%d)" % [pmin, pmax])
	var unreachable: Array = []
	for t in tg:
		var best := 1e9
		var tp: Vector3 = t["pos"]
		for bi in 51:
			for si in 101:
				var b: float = bi / 50.0
				var s: float = -1.0 + si / 50.0
				var p := Vector2(s, b)
				if p.length() > 1.0 or p.length() < 0.12:
					continue
				var up: float = clampf(b, 0.05, 1.0) * 1.6
				var dir := Vector3(1.0, up, -s * main.SIDE_GAIN).normalized()
				var power: float = p.length()
				var spd: float = lerpf(9.0, 32.0, pow(power, 0.9))
				var p0: Vector3 = main.LAUNCH_ORIGIN - dir * main.PULL_LEN * power
				var prev := p0
				for ti in range(1, 400):
					var tt: float = 0.02 * ti
					var pos: Vector3 = p0 + dir * spd * tt + Vector3(0, -0.5 * g * tt * tt, 0)
					if pos.y < 0.0:
						break
					if t["key"] == "needle":
						if prev.x < main.town.GAP_X and pos.x >= main.town.GAP_X and absf(pos.z) < main.town.GAP_HALF and pos.y < 6.5 and pos.y > 0.3:
							best = 0.0
					else:
						# hitting anywhere on the structure (vertical segment under the marker) counts
						var dy: float = maxf(pos.y - tp.y, 0.0)
						best = minf(best, Vector3(pos.x - tp.x, dy, pos.z - tp.z).length())
					prev = pos
		if best > 3.0:
			unreachable.append("%s %.1f" % [t["name"], best])
	check(unreachable.is_empty(), "every target is ballistically reachable within 3 m %s" % str(unreachable))
	var sc := Scoring.new()
	check(sc.award("window", "x", 150, "Targets") and not sc.award("window", "x", 150, "Targets"), "a target scores once per shot")
	# ---- world content
	check(main.town.pieces.size() >= 200, "%d breakable pieces, %d props" % [main.town.pieces.size(), main.town.props.size()])
	var xmax := 0.0
	var zmax := 0.0
	for t in tg:
		xmax = maxf(xmax, t["pos"].x)
		zmax = maxf(zmax, absf(t["pos"].z))
	check(xmax >= 85.0 and zmax >= 50.0, "playfield spans x to %.0f m and +-%.0f m" % [xmax, zmax])
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
	for p in main.town.pieces:
		if not p.freeze or p.global_position.distance_to(p.get_meta("rest")) > 0.01:
			restored = false
	for b in main.town.props:
		if b.global_position.distance_to(b.get_meta("rest")) > 0.05:
			restored = false
	check(restored and main.town.frozen_count() == main.town.pieces.size(), "fast reset restores every piece and prop in place")
	# ---- extreme shots: result in time, camera keeps the ragdoll in view, bounded physics
	var shots := {
		"hard left": [0.55, 0.85], "hard right": [0.55, -0.85], "long centre": [0.8, 0.0],
		"high lob": [1.0, 0.0], "flat fast": [0.1, 0.0], "left-centre": [0.7, 0.45], "right-centre": [0.7, -0.45]}
	for nm in shots.keys():
		var r: Dictionary = await _shoot(main, shots[nm][0], shots[nm][1])
		check(r.state == 2 and r.sane, "%s: reaches RESULT in %.1f s of flight, sane" % [nm, r.frames / 60.0])
		check(r.view >= 0.90, "%s: ragdoll in camera view %.0f%% of frames" % [nm, r.view * 100.0])
		check(main.cam.global_position.y > 1.5, "%s: camera stays above ground" % nm)
		print("      end=%s score=%d worst_frame=%.1fms active=%d" % [str(r.end), r.score, r.worst_ms, r.active])
	# ---- stress: smash through the densest cluster
	var st: Dictionary = await _shoot(main, 0.12, 0.0)
	check(st.active <= main.town.ACTIVE_CAP + 10, "stress shot: peak active released pieces %d" % st.active)
	check(st.worst_ms < 80.0, "stress shot: worst frame %.1f ms (headless desktop)" % st.worst_ms)
	# ---- tap-to-skip after 1.5 s of flight only
	main.reset()
	await frames(2)
	_aim(main, 0.8, 0.0)
	main.fire()
	await frames(20)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	main._unhandled_input(press)
	check(main.state == 1, "tap before 1.5 s does not skip")
	await frames(90)
	if main.state == 1:
		main._unhandled_input(press)
	check(main.state == 2, "tap after 1.5 s skips to the result")
	# ---- About formatting regression (version code printed as an integer)
	main.get_node("/root/Ota").info["version_code"] = 7.0
	var txt: String = SettingsMenu.diagnostics_text(main.get_node("/root/Ota"))
	check("Version code (native build): 7\n" in txt and not ("7.0" in txt), "About prints integers without .0")
