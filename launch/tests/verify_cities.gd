extends SceneTree
## City quality gate: every environment is loaded, inspected and thrown through with several vectors / characters.
##   godot --headless --path launch -s tests/verify_cities.gd
## Prints a per-city performance table (frame time, body counts, debris) for the handoff report.

const Rules := preload("res://scripts/rules.gd")
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

func _aim(b: float, s: float) -> void:
	main.drag_vec = (main._basis_back * b + main._basis_side * s) * main.AIM_MAX_PX
	main._update_aim()

func _maxed() -> Dictionary:
	var d := Rules.empty_levels()
	for k in d.keys():
		d[k] = int(Rules.UPGRADES[k]["max"])
	return d

## One automated throw. Returns metrics.
func _throw(char_i: int, env_id: String, lv: Dictionary, b: float, s: float) -> Dictionary:
	main.levels = lv
	main.start_game(char_i, Rules.env_index(env_id))
	await frames(3)
	var T = main.town
	var pieces0: int = T.pieces.size()
	_aim(b, s)
	main.fire()
	var n := 0
	var sane := true
	var min_y := 99.0
	var min_agl := 99.0
	var max_x := -99.0
	var worst_dt := 0.0
	var peak_awake := 0
	var t_prev: int = Time.get_ticks_usec()
	var first_fall_frame := -1
	while main.state == 1 and n < 60 * 16:
		await physics_frame
		n += 1
		var now: int = Time.get_ticks_usec()
		worst_dt = maxf(worst_dt, float(now - t_prev) / 1000.0)
		t_prev = now
		for body in main.ragdoll.bodies:
			if not _fin(body.global_position) or not _fin(body.linear_velocity):
				sane = false
			min_y = minf(min_y, body.global_position.y)
			min_agl = minf(min_agl, body.global_position.y - T.ground_y(body.global_position.x, body.global_position.z))
		var c: Vector3 = main.ragdoll.centre()
		max_x = maxf(max_x, c.x)
		if n % 20 == 0:
			var awake := 0
			for p in T.pieces:
				if is_instance_valid(p) and not p.sleeping and not p.freeze:
					awake += 1
			peak_awake = maxi(peak_awake, awake)
	var broken := 0
	for p in T.pieces:
		if not is_instance_valid(p) or not p.freeze:
			broken += 1
	return {"frames": n, "state": main.state, "score": main.scoring.total(), "skips": main.skips, "limbs": main.limbs_lost, "sane": sane, "min_y": min_y, "min_agl": min_agl,
		"max_x": max_x, "worst_ms": worst_dt, "awake": peak_awake, "pieces": pieces0, "moved": broken, "oob": main._oob_at >= 0.0, "end": main.ragdoll.centre(),
		"fire_peak": T.burning_count, "credit": Rules.bank_credit(main.scoring.lines)}

## Can a legal launch (soft-limited pitch, governed speed, lateral aim within +-50 deg) pass through p? (ignores collisions)
func _reachable(p: Vector3) -> bool:
	var dx: float = p.x
	var dz: float = p.z
	var dist: float = sqrt(dx * dx + dz * dz)
	if absf(atan2(dz, dx)) > deg_to_rad(50.0) or dist < 1.0:
		return false
	var g: float = Rules.g_eff()
	for pd in range(3, 39, 1):
		var th: float = deg_to_rad(float(pd))
		var c: float = cos(th)
		var den: float = 2.0 * c * c * (dist * tan(th) + 2.3 - p.y)
		if den <= 0.0:
			continue
		var v: float = sqrt(g * dist * dist / den)
		if v <= 68.0 and v >= 8.0 and Rules.ideal_range(v, th) <= 180.5 and Rules.ideal_apex(v, th) <= 60.5:
			return true
	return false

func _signature(T) -> int:
	var h: int = 17
	for p in T.pieces:
		var q: Vector3 = p.global_position
		h = (h * 31 + int(q.x * 100.0) * 7 + int(q.y * 100.0) * 13 + int(q.z * 100.0) * 17) & 0x7fffffff
	for sp in T.static_pos:
		h = (h * 31 + int(sp.x * 100.0) * 5 + int(sp.z * 100.0) * 11) & 0x7fffffff
	return h

func _run() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.skip_select = true
	root.add_child(main)
	await frames(5)
	seed(1234)
	var ids: Array = []
	for en in Rules.ENVIRONMENTS:
		ids.append(str(en["id"]))
	check(ids.size() == 11 and not ids.has("coming_soon"), "11 environments (4 hillside + 5 v13 cities + Grand Fortress + Test Yard): %s" % ", ".join(ids))
	for en in Rules.ENVIRONMENTS:
		check(bool(en["playable"]), "%s is playable (no COMING SOON / LOCKED)" % en["id"])
	var vectors := [[0.6, 0.0], [0.9, 0.35], [1.0, -0.35], [1.3, 0.0], [0.35, 0.0]]
	for id in ids:
		print("---- city: %s" % id)
		main.levels = Rules.empty_levels()
		main.start_game(0, Rules.env_index(id))
		await frames(4)
		var T = main.town
		check(T.env_id == id, "%s: loads as itself" % id)
		var sig1: int = _signature(T)
		var np: int = T.pieces.size()
		var nprops: int = T.props.size()
		var nstat: int = T.static_pos.size()
		# deterministic load: a second load is identical
		main.start_game(0, Rules.env_index(id))
		await frames(4)
		T = main.town
		check(_signature(T) == sig1 and T.pieces.size() == np, "%s: deterministic loading (layout signature %d identical on reload, %d pieces)" % [id, sig1, np])
		# spawn / launch corridor
		var near := 0
		for p in T.pieces:
			var q: Vector3 = p.global_position
			if Vector2(q.x, q.z).length() < 16.0:
				near += 1
		for sp in T.static_pos:
			if Vector2(sp.x, sp.z).length() < 16.0:
				near += 1
		check(near == 0, "%s: spawn area is clear (%d solids within 16 m)" % [id, near])
		check(main.state == 0 and main.ragdoll.centre().y > 0.5 and main.ragdoll.centre().y < 6.0, "%s: valid spawn, AIM state, ragdoll at %s" % [id, main.ragdoll.centre()])
		check(np >= 60 or id == "yard", "%s: enough destructible pieces (%d)" % [id, np])
		check(T.targets.size() >= 4, "%s: %d scoring targets" % [id, T.targets.size()])
		# targets must be reachable under the governor (range cap 180 m, apex cap 60 m)
		var unreachable := 0
		for tg in T.targets:
			var p: Vector3 = tg["pos"]
			if not _reachable(p):
				unreachable += 1
		if unreachable > 0:
			var names: Array = []
			for tg in T.targets:
				if not _reachable(tg["pos"]):
					names.append("%s %s" % [tg["name"], tg["pos"]])
			print("      unreachable: ", names)
		check(unreachable == 0, "%s: every target is reachable under the launch governor (%d unreachable)" % [id, unreachable])
		var xs := {}
		for p in T.pieces:
			xs[int(p.global_position.x / 30.0)] = true
		check(xs.size() >= 3 or id == "yard", "%s: content spread across %d depth bands (no dominant empty area)" % [id, xs.size()])
		match id:
			"downtown":
				check(T.glass.size() >= 100, "downtown: glass fronts (%d panes)" % T.glass.size())
				var tall := 0.0
				for p in T.pieces:
					tall = maxf(tall, p.global_position.y)
				check(tall >= 25.0, "downtown: verticality (tallest piece at %.0f m)" % tall)
			"oldtown":
				check(T.fire_nodes.size() >= 40, "oldtown: combustible timber (%d burnables)" % T.fire_nodes.size())
			"suburbia":
				var tramp := 0
				for ch in T.get_children():
					if ch is StaticBody3D and str(ch.get_meta("mat", "")) == "trampoline":
						tramp += 1
				check(tramp >= 2, "suburbia: trampolines (%d)" % tramp)
			"industrial":
				check(T.tnt.size() >= 4 or T.props.size() >= 8, "industrial: explosive chains (%d TNT, %d props)" % [T.tnt.size(), T.props.size()])
			"resort":
				check(T.glass.size() >= 30, "resort: glass (%d panes)" % T.glass.size())
		# automated throws
		var worst := 0.0
		var ok_all := true
		var skip_sane := true
		var peak_awake := 0
		var tot_score := 0
		var runs := 0
		var runs_with_hits := 0
		for v in vectors:
			var r: Dictionary = await _throw(0, id, Rules.empty_levels(), v[0], v[1])
			runs += 1
			worst = maxf(worst, r.worst_ms)
			peak_awake = maxi(peak_awake, r.awake)
			tot_score += r.score
			if r.score > 0:
				runs_with_hits += 1
			var good: bool = r.state != 1 and r.sane and r.min_agl > -1.5 and r.frames > 20
			if not good:
				ok_all = false
			if r.skips > 14 or r.score > 14000:
				skip_sane = false
			print("      throw %s base: frames %d score %d skips %d limbs %d end x %.0f y %.1f worst %.1f ms awake %d" % [v, r.frames, r.score, r.skips, r.limbs, r.end.x, r.end.y, r.worst_ms, r.awake])
		for spec in [[6, 1.0, 0.0], [10, 0.8, -0.3], [15, 1.3, 0.2]]:
			var r2: Dictionary = await _throw(spec[0], id, _maxed(), spec[1], spec[2])
			runs += 1
			worst = maxf(worst, r2.worst_ms)
			peak_awake = maxi(peak_awake, r2.awake)
			tot_score += r2.score
			if r2.score > 0:
				runs_with_hits += 1
			var good2: bool = r2.state != 1 and r2.sane and r2.min_agl > -1.5 and r2.frames > 20 and r2.max_x < 215.0
			if not good2:
				ok_all = false
			if r2.skips > 14 or r2.score > 20000:
				skip_sane = false
			print("      throw %s char %d maxed: frames %d score %d skips %d limbs %d end x %.0f y %.1f worst %.1f ms awake %d" % [spec, spec[0], r2.frames, r2.score, r2.skips, r2.limbs, r2.end.x, r2.end.y, r2.worst_ms, r2.awake])
		check(ok_all, "%s: all %d automated throws end cleanly: finite physics, no fall-through, no stuck run" % [id, runs])
		check(runs_with_hits >= runs - 1, "%s: throws score (%d of %d runs scored)" % [id, runs_with_hits, runs])
		check(skip_sane, "%s: skip counts / scores stay bounded" % id)
		check(peak_awake <= 220, "%s: awake rigid bodies stay bounded (peak %d)" % [id, peak_awake])
		check(worst < 120.0, "%s: worst frame %.1f ms (headless software)" % [id, worst])
		table.append({"id": id, "pieces": np, "props": nprops, "static": nstat, "tnt": T.tnt.size(), "glass": T.glass.size(), "burn": T.fire_nodes.size(),
			"targets": T.targets.size(), "worst_ms": worst, "awake": peak_awake, "avg_score": tot_score / maxi(runs, 1)})
	print("---- CITY TABLE")
	for row in table:
		print("      %-10s pieces %4d props %3d static %4d tnt %2d glass %4d burnables %3d targets %2d | worst %.1f ms, peak awake %3d, avg score %d" % [row.id, row.pieces, row.props, row.static, row.tnt, row.glass, row.burn, row.targets, row.worst_ms, row.awake, row.avg_score])
	# lighting a fire after the runs must leave the cleanup intact (no debris accumulation across resets)
	main.start_game(0, Rules.env_index("downtown"))
	await frames(4)
	var before: int = root.get_child_count()
	for i in 4:
		main.start_game(0, Rules.env_index(ids[i % ids.size()]))
		await frames(3)
	var leaked: int = main.get_child_count()
	await frames(2)
	check(main.get_child_count() <= leaked and main.get_children().filter(func(c): return c.get_script() != null and str(c.get_script().resource_path).ends_with("town.gd")).size() == 1, "reset cycles keep exactly one Town (no accumulation)")
	print("---- CITIES %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
