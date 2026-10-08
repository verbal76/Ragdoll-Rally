extends SceneTree
## Level-20 stress + per-board runtime validation. Every board gets real physics throws at maxed upgrades (and a stock baseline):
## destruction must happen and be bounded (bodies, frame time), the camera must stay out of solids with line of sight, slow motion
## must hand time back, and the run must end cleanly.
##   godot --headless --path launch -s tests/verify_stress.gd         (env STRESS_BOARDS=downtown,oldtown to subset)
const Rules := preload("res://scripts/rules.gd")
const CamSafe := preload("res://scripts/cam_safe.gd")
const Destruction := preload("res://scripts/destruction.gd")
var fails := 0
var main: Node
var table: Array = []

func check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		fails += 1

func _init() -> void:
	Engine.max_fps = 0
	_run.call_deferred()

func frames(n: int) -> void:
	for i in n:
		await process_frame

func _fin(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)

func _aim(b: float, s: float) -> void:
	main.drag_vec = (main._basis_back * b + main._basis_side * s) * main.AIM_MAX_PX
	main._update_aim()

func _lv(l: int) -> Dictionary:
	var d := Rules.empty_levels()
	for k in Rules.MAYHEM_KEYS:
		d[k] = l
	if l > 0:
		d["spin"] = 5
		d["durability"] = 5
		d["ignition"] = 3
	return d

func _throw(env_id: String, lv: Dictionary, b: float, s: float) -> Dictionary:
	main.levels = lv
	main.start_game(0, Rules.env_index(env_id))
	await frames(3)
	var T = main.town
	_aim(b, s)
	main.fire()
	var n := 0
	var sane := true
	var cam_bad := 0
	var cam_samples := 0
	var min_ts := 1.0
	var peak_awake := 0
	var worst := 0.0
	var times: Array[float] = []
	var t_prev: int = Time.get_ticks_usec()
	var space: PhysicsDirectSpaceState3D = root.world_3d.direct_space_state
	while main.state == 1 and n < 60 * 40:
		await physics_frame
		n += 1
		var now: int = Time.get_ticks_usec()
		var ms: float = float(now - t_prev) / 1000.0
		t_prev = now
		if n > 3:
			times.append(ms)
		worst = maxf(worst, ms)
		min_ts = minf(min_ts, Engine.time_scale)
		for body in main.ragdoll.bodies:
			if not _fin(body.global_position) or not _fin(body.linear_velocity):
				sane = false
		if n % 4 == 0 and main.t_first_impact >= 0.0:
			cam_samples += 1
			var cp: Vector3 = main.cam.global_position
			var focus: Vector3 = main.ragdoll.centre()
			# the lens must never be inside standing geometry; a line of sight is required unless Ragnar himself is inside a structure
			# (tunnelling through a wall: nothing can see him there until he comes out)
			var focus_buried: bool = CamSafe.inside_solid(space, focus, 0.6)
			if CamSafe.inside_solid(space, cp, 0.5) or (not focus_buried and CamSafe.clear_fraction(space, cp, focus, 0.15) < 0.97):
				cam_bad += 1
		if n % 15 == 0:
			var awake := 0
			for p in T.pieces:
				if is_instance_valid(p) and not p.sleeping and not p.freeze:
					awake += 1
			peak_awake = maxi(peak_awake, awake)
	var broken := 0
	var dissolved := 0
	for p in T.pieces:
		if is_instance_valid(p) and p.get_meta("dissolved", false):
			dissolved += 1
		elif not is_instance_valid(p) or not p.freeze or p.get_meta("capped", false):
			broken += 1
	times.sort()
	var p95: float = times[int(float(times.size()) * 0.95)] if times.size() > 20 else 0.0
	return {"frames": n, "state": main.state, "score": main.scoring.total(), "sane": sane, "cam_bad": cam_bad, "cam_n": cam_samples, "min_ts": min_ts,
		"ts_end": Engine.time_scale, "awake": peak_awake, "worst": worst, "p95": p95, "broken": broken, "dissolved": dissolved,
		"shells": T.shells_open.size(), "craters": main.craters, "limbs": main.limbs_lost, "end": main.ragdoll.centre(),
		"expl": int(main.scoring.lines.get("Explosions", 0)), "dest": int(main.scoring.lines.get("Destruction", 0))}

func _run() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.skip_select = true
	root.add_child(main)
	await frames(5)
	seed(777)
	var boards: Array = []
	var only: String = OS.get_environment("STRESS_BOARDS")
	for en in Rules.ENVIRONMENTS:
		if only == "" or only.split(",").has(str(en["id"])):
			boards.append(str(en["id"]))
	var vectors := [[1.0, 0.0], [0.9, 0.3], [1.3, -0.3]]
	for id in boards:
		print("---- board: %s" % id)
		var lo_broken := 0.0
		var hi_broken := 0.0
		var ok_all := true
		var cam_bad := 0
		var cam_n := 0
		var peak := 0
		var worst := 0.0
		var p95 := 0.0
		var min_ts := 1.0
		var ts_ok := true
		var best_score := 0
		var any_crater := false
		for v in vectors:
			var lo: Dictionary = await _throw(id, _lv(0), v[0], v[1])
			var hi: Dictionary = await _throw(id, _lv(20), v[0], v[1])
			lo_broken += float(lo.broken + lo.dissolved)
			hi_broken += float(hi.broken + hi.dissolved)
			ok_all = ok_all and lo.sane and hi.sane and lo.state != 1 and hi.state != 1
			cam_bad += hi.cam_bad + lo.cam_bad
			cam_n += hi.cam_n + lo.cam_n
			peak = maxi(peak, hi.awake)
			worst = maxf(worst, hi.worst)
			p95 = maxf(p95, hi.p95)
			min_ts = minf(min_ts, hi.min_ts)
			ts_ok = ts_ok and absf(hi.ts_end - 1.0) < 0.001 and absf(lo.ts_end - 1.0) < 0.001
			best_score = maxi(best_score, hi.score)
			any_crater = any_crater or hi.craters > 0
			print("      throw %s: Lv0 broke %d (score %d, x %.0f) | Lv20 broke %d + dissolved %d, shells %d, craters %d, limbs %d, score %d (destr %d, expl %d), x %.0f, awake %d, worst %.1f ms p95 %.1f ms, min time scale %.2f, cam bad %d/%d" % [str(v), lo.broken, lo.score, lo.end.x, hi.broken, hi.dissolved, hi.shells, hi.craters, hi.limbs, hi.score, hi.dest, hi.expl, hi.end.x, hi.awake, hi.worst, hi.p95, hi.min_ts, hi.cam_bad, hi.cam_n])
		table.append({"id": id, "lo": lo_broken / 3.0, "hi": hi_broken / 3.0, "peak": peak, "worst": worst, "p95": p95, "cam_bad": cam_bad, "cam_n": cam_n, "min_ts": min_ts, "score": best_score})
		check(ok_all, "%s: every throw (stock and Lv20) ends cleanly with finite physics" % id)
		check(hi_broken > lo_broken * 1.4 or hi_broken > 60.0, "%s: Lv20 wrecks far more than stock (%.0f vs %.0f pieces/throw)" % [id, hi_broken / 3.0, lo_broken / 3.0])
		check(peak <= 220, "%s: simulated bodies stay inside the budget at Lv20 (peak %d)" % [id, peak])
		check(cam_n == 0 or float(cam_bad) / float(cam_n) <= 0.03, "%s: camera stays out of solids with a line of sight (%d bad of %d samples)" % [id, cam_bad, cam_n])
		check(ts_ok, "%s: time scale is back to 1.0 when the run ends (dipped to %.2f)" % [id, min_ts])
		check(p95 < 45.0, "%s: Lv20 p95 step time %.1f ms (headless physics)" % [id, p95])
	print("---- STRESS TABLE (avg pieces broken/throw, peak awake, worst/p95 step ms, camera bad, min time scale, best Lv20 score)")
	for r in table:
		print("      %-13s Lv0 %5.0f  Lv20 %5.0f  awake %3d  worst %5.1f  p95 %5.1f  cam %d/%d  slow %.2f  score %d" % [r.id, r.lo, r.hi, r.peak, r.worst, r.p95, r.cam_bad, r.cam_n, r.min_ts, r.score])
	print("---- STRESS %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
