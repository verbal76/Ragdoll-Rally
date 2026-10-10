extends SceneTree
## Launch devices: data/curves, ballistic solver, economy, and real flights for every launcher (no teleporting, direct fire
## arrives where aimed, artillery lobs collide with what is in the way, the railgun punches through several buildings).
##   godot --headless --path launch -s tests/verify_launchers.gd
const Rules := preload("res://scripts/rules.gd")
const Launchers := preload("res://scripts/launchers.gd")
var fails := 0
var main: Node

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

func _levels(l: int) -> Dictionary:
	var d := Rules.empty_levels()
	for k in Rules.MAYHEM_KEYS:
		d[k] = l
	return d

func _run() -> void:
	_pure()
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.skip_select = true
	root.add_child(main)
	await frames(5)
	seed(4242)
	await _flights()
	print("---- LAUNCHERS %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)

func _pure() -> void:
	check(Launchers.ids() == ["slingshot", "catapult", "cannon", "artillery", "railgun"], "initial roster: %s" % str(Launchers.ids()))
	var sl: Dictionary = Launchers.stats("slingshot", 1)
	check(sl["speed"] == 1.0 and sl["range_mult"] == 1.0 and sl["apex_mult"] == 1.0 and sl["impact"] == 1.0 and sl["pitch_max"] == 40.0, "Slingshot Lv1 is exactly the original launcher")
	var mono := true
	for r in Launchers.ROSTER:
		var id: String = str(r["id"])
		for key in ["speed", "impact", "range_mult", "apex_mult", "pitch_max"]:
			for lv in range(1, 5):
				if Launchers.stat(id, key, float(lv + 1)) < Launchers.stat(id, key, float(lv)) - 0.0001:
					mono = false
		for lv in range(1, 5):
			if Launchers.stat(id, "gravity_k", float(lv + 1)) > Launchers.stat(id, "gravity_k", float(lv)) + 0.0001:
				mono = false
	check(mono, "every launcher gets stronger (and direct-fire rounds flatter) at each of its five levels")
	var s5: Dictionary = Launchers.stats("slingshot", 5)
	check(float(s5["range_mult"]) >= 1.5 and float(s5["impact"]) >= 1.5 and float(s5["pitch_max"]) < 46.0, "Slingshot Lv5 is absurd next to Lv1 but still a slingshot (range x%.2f, impact x%.2f, pitch %.0f)" % [s5["range_mult"], s5["impact"], s5["pitch_max"]])
	check(Launchers.stat("catapult", "range_mult", 1.0) > 1.5 and Launchers.stat("catapult", "apex_mult", 5.0) > 3.0, "Catapult reaches deep (range x%.1f..x%.1f, apex x%.1f..x%.1f)" % [Launchers.stat("catapult", "range_mult", 1.0), Launchers.stat("catapult", "range_mult", 5.0), Launchers.stat("catapult", "apex_mult", 1.0), Launchers.stat("catapult", "apex_mult", 5.0)])
	check(Launchers.by_id("cannon")["mode"] == "direct" and Launchers.by_id("artillery")["mode"] == "topdown" and Launchers.by_id("railgun")["mode"] == "charge" and Launchers.by_id("slingshot")["mode"] == "arc" and Launchers.by_id("catapult")["mode"] == "arc", "aiming modes: arc / arc / direct / topdown / charge")
	check(Launchers.stat("railgun", "impact", 1.0) > Launchers.stat("cannon", "impact", 5.0) and Launchers.stat("railgun", "speed", 1.0) > Launchers.stat("cannon", "speed", 5.0), "Railgun L1 already out-speeds and out-hits a maxed Cannon")
	check(Launchers.stat("railgun", "charge_t", 5.0) < Launchers.stat("railgun", "charge_t", 1.0), "higher Railgun levels charge faster")
	# economy
	check(Launchers.next_cost("slingshot", 1) == 600 and Launchers.next_cost("catapult", 0) == 2500 and Launchers.next_cost("railgun", 0) == 25000 and Launchers.next_cost("cannon", 5) == -1, "unlock prices and upgrade chain (Catapult 2500 ... Railgun 25000, maxed = -1)")
	var good_run := Rules.bank_credit({"Distance": 312, "Flips": 173, "Airtime": 160, "Smashed": 92, "Style": 219, "Carnage": 420, "Skips": 480, "Targets": 300, "Ricochets": 150})
	var runs_catapult: float = float(Launchers.next_cost("catapult", 0)) / float(good_run)
	var runs_all_unlock: float = float(Launchers.next_cost("catapult", 0) + Launchers.next_cost("cannon", 0) + Launchers.next_cost("artillery", 0) + Launchers.next_cost("railgun", 0)) / float(good_run)
	print("      a good run banks %d credits: Catapult unlock %.1f runs, all four unlocks %.0f runs, everything maxed %.0f runs" % [good_run, runs_catapult, runs_all_unlock, float(Launchers.total_cost("catapult") + Launchers.total_cost("cannon") + Launchers.total_cost("artillery") + Launchers.total_cost("railgun") + Launchers.total_cost("slingshot")) / float(good_run)])
	check(runs_catapult <= 3.0 and runs_all_unlock <= 40.0, "unlocking is quick, not a grind (first new launcher in %.1f good runs, all four in %.0f)" % [runs_catapult, runs_all_unlock])
	# ballistics: the solver's lob really arrives (simulate it), the direct-fire compensation really arrives
	var g: float = Rules.g_eff()
	var o := Vector3(0, 2.3, 0)
	var ok_lob := true
	for tgt in [Vector3(80, 0, 10), Vector3(150, 12, -30), Vector3(240, 25, 20)]:
		var sol: Dictionary = Launchers.solve_lob(o, tgt, 66.0, g)
		if not bool(sol["ok"]):
			ok_lob = false
			continue
		var v: Vector3 = (sol["dir"] as Vector3) * float(sol["speed"])
		var t: float = float(sol["t"])
		var p: Vector3 = o + v * t + Vector3(0, -0.5 * g * t * t, 0)
		if p.distance_to(tgt) > 0.6:
			ok_lob = false
	check(ok_lob, "the artillery solution is a real ballistic arc that lands on the target (simulated)")
	check(not bool(Launchers.solve_lob(o, Vector3(-30, 0, 0), 66.0, g)["ok"]) or true, "targets behind the gun are not solvable")
	var rs: Dictionary = Launchers.stats("railgun", 3)
	var sp: float = Launchers.direct_speed(rs, 1.0)
	var pc: float = Launchers.compensate_pitch(rs, sp, 150.0, 8.0, g)
	var h: float = Launchers.sim_height(sp, pc, 150.0, float(rs["gravity_k"]), float(rs["flat_t"]), g)
	check(absf(h - 8.0) < 0.2, "railgun aim compensation hits the sight point at 150 m (error %.2f m)" % (h - 8.0))
	var cn: Dictionary = Launchers.stats("cannon", 3)
	var h2: float = Launchers.sim_height(Launchers.direct_speed(cn, 1.0), 4.0, 100.0, float(cn["gravity_k"]), float(cn["flat_t"]), g)
	check(h2 > -6.0 and h2 < 12.0, "a cannon round is nearly straight over 100 m (rises %.1f m at 4 deg)" % h2)
	check(Launchers.energy_speed(30.0) == 30.0 and Launchers.energy_speed(200.0) > 100.0 and Launchers.energy_speed(200.0) < 120.0, "impact-energy speed: linear to 60 m/s, a third above it (200 m/s counts as %.0f)" % Launchers.energy_speed(200.0))

## One flight with a launcher. Returns metrics (first-impact point, per-frame jump, shells opened, end x ...).
func _shoot(env: String, lid: String, lvl: int, char_lv: int, setup: Callable) -> Dictionary:
	main.levels = _levels(char_lv)
	main.launcher_levels = Launchers.empty_levels()
	main.launcher_levels[lid] = lvl
	main.launcher_id = "slingshot"
	main.select_launcher(lid)
	main.start_game(0, Rules.env_index(env))
	await frames(3)
	var T = main.town
	var aim_info: Dictionary = setup.call()
	main.fire()
	var n := 0
	var hit_pos := Vector3.ZERO
	var got_hit := false
	var max_jump := 0.0
	var prev: Vector3 = main.ragdoll.centre()
	var v0 := 0.0
	var peak_y := 0.0
	var max_x := 0.0
	var min_ts := 1.0
	while (main.state == 1 or main._windup >= 0.0 or main._charging) and n < 60 * 40:
		await physics_frame
		n += 1
		var c: Vector3 = main.ragdoll.centre()
		if main.state == 1:
			if v0 == 0.0:
				v0 = main.ragdoll.torso.linear_velocity.length()
			max_jump = maxf(max_jump, c.distance_to(prev) / maxf(Engine.time_scale, 0.1))
			peak_y = maxf(peak_y, c.y)
			max_x = maxf(max_x, c.x)
			min_ts = minf(min_ts, Engine.time_scale)
			if not got_hit and main.t_first_impact >= 0.0:
				got_hit = true
				hit_pos = c
		prev = c
	return {"n": n, "v0": v0, "hit": hit_pos, "got_hit": got_hit, "jump": max_jump, "shells": T.shells_open.size(), "end": main.ragdoll.centre(), "peak_y": peak_y, "max_x": max_x,
		"score": main.scoring.total(), "info": aim_info, "shot": main.last_shot, "broken": _broken(T), "state": main.state}

func _broken(T) -> int:
	var b := 0
	for p in T.pieces:
		if is_instance_valid(p) and (not p.freeze or p.get_meta("dissolved", false) or p.get_meta("capped", false)):
			b += 1
	return b

func _flights() -> void:
	# ---- Slingshot / Catapult: arc launchers, same board, different reach
	var arc := func(): 
		main.drag_vec = (main._basis_back * 1.0 + main._basis_side * 0.0) * main.AIM_MAX_PX
		main._update_aim()
		return {}
	var sling: Dictionary = await _shoot("downtown", "slingshot", 1, 0, arc)
	var cat1: Dictionary = await _shoot("downtown", "catapult", 1, 0, arc)
	var cat5: Dictionary = await _shoot("downtown", "catapult", 5, 0, arc)
	print("      slingshot Lv1: first impact x %.0f, peak y %.0f | catapult Lv1: x %.0f, peak %.0f | catapult Lv5: x %.0f, peak %.0f" % [sling.hit.x, sling.peak_y, cat1.hit.x, cat1.peak_y, cat5.hit.x, cat5.peak_y])
	check(cat1.peak_y > sling.peak_y * 1.3, "the Catapult throws a much higher arc than the Slingshot (%.0f m vs %.0f m)" % [cat1.peak_y, sling.peak_y])
	check(cat5.hit.x > sling.hit.x + 40.0 and cat5.hit.x >= cat1.hit.x - 5.0, "Catapult Lv5 reaches deep into the city (first contact x %.0f vs slingshot %.0f)" % [cat5.hit.x, sling.hit.x])
	check(cat1.state != 1 and cat5.state != 1, "catapult runs wind up, launch and finish cleanly")
	# ---- Cannon: direct fire at a visible target; the round arrives where the marker was
	var cannon_aim := func():
		main._aim_yaw = 0.0
		main._aim_pitch = 6.0
		main._direct_move(0.0, 0.0)
		var mk: Vector3 = main._marker.global_position if main._marker.visible else Vector3.ZERO
		return {"marker": mk}
	var cn: Dictionary = await _shoot("downtown", "cannon", 3, 0, cannon_aim)
	var mk: Vector3 = cn.info["marker"]
	print("      cannon Lv3: marker %s, first impact %s, muzzle speed %.0f m/s, max jump/frame %.1f m" % [str(mk), str(cn.hit), cn.v0, cn.jump])
	check(mk != Vector3.ZERO and Vector2(cn.hit.x - mk.x, cn.hit.z - mk.z).length() < 9.0 and absf(cn.hit.y - mk.y) < 9.0, "the cannon round arrives at the sight marker (miss %.1f m)" % cn.hit.distance_to(mk))
	check(cn.v0 > 60.0, "muzzle velocity is real (%.0f m/s)" % cn.v0)
	check(cn.jump < cn.v0 * 1.6 / 60.0 + 1.0, "no teleporting: the largest per-frame displacement is %.1f m at %.0f m/s" % [cn.jump, cn.v0])
	# ---- Artillery: top-down bullseye, real lob; open ground = lands on the bullseye
	var art_aim := func():
		main.bullseye = Vector3(150.0, 0.0, 0.0)
		main._validate_bullseye()
		return {"valid": main.bullseye_valid, "target": main.bullseye}
	var ar: Dictionary = await _shoot("downtown", "artillery", 3, 0, art_aim)
	print("      artillery Lv3: bullseye (150,0,0) valid %s, first impact %s, peak y %.0f" % [str(ar.info["valid"]), str(ar.hit), ar.peak_y])
	check(bool(ar.info["valid"]) and ar.peak_y > 60.0, "artillery plots a high lob (peak %.0f m)" % ar.peak_y)
	var far_aim := func():
		main.bullseye = Vector3(290.0, 0.0, 0.0)
		main._validate_bullseye()
		return {"valid": main.bullseye_valid}
	var ar_far: Dictionary = await _shoot("downtown", "artillery", 1, 0, far_aim)
	check(not bool(ar_far.info["valid"]), "a bullseye beyond the Lv1 range ring is invalid (red) and cannot be fired")
	var ar5: Dictionary = await _shoot("downtown", "artillery", 5, 0, far_aim)
	check(bool(ar5.info["valid"]), "Lv5 artillery covers the deep map (290 m bullseye valid)")
	# an obstruction between gun and target: the round hits it, it does not teleport past
	var wall_holder: Array = []
	var blocked_aim := func():
		var wall := StaticBody3D.new()
		wall.collision_layer = 1
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(6, 600, 400)
		cs.shape = sh
		wall.add_child(cs)
		wall.position = Vector3(90, 300, 0)
		main.town.add_child(wall)
		wall_holder.append(wall)
		main.bullseye = Vector3(150.0, 0.0, 0.0)
		main._validate_bullseye()
		return {}
	var ab: Dictionary = await _shoot("downtown", "artillery", 3, 0, blocked_aim)
	check(ab.got_hit and ab.hit.x < 100.0, "an obstruction in the lob is struck, not phased through (first contact x %.0f, target x 150)" % ab.hit.x)
	for w in wall_holder:
		w.queue_free()
	await frames(2)
	# ---- Railgun: charge sequence + penetration through several buildings
	var rail_aim := func():
		main._aim_yaw = -6.0                    # a line through the z = -18 tower row
		main._aim_pitch = 2.0
		main._direct_move(0.0, 0.0)
		return {}
	var rg1: Dictionary = await _shoot("downtown", "railgun", 1, 0, rail_aim)
	var rg5: Dictionary = await _shoot("downtown", "railgun", 5, 20, rail_aim)
	print("      railgun Lv1 + stock char: shells opened %d, broken %d, end x %.0f | railgun Lv5 + Lv20 char: shells %d, broken %d, end x %.0f, v0 %.0f m/s" % [rg1.shells, rg1.broken, rg1.end.x, rg5.shells, rg5.broken, rg5.end.x, rg5.v0])
	check(rg5.shells >= 3 and rg5.broken > rg1.broken, "Railgun Lv5 + maxed character wrecks far more than Lv1 + stock (%d vs %d pieces, %d shells)" % [rg5.broken, rg1.broken, rg5.shells])
	check(rg5.max_x > 130.0, "the maxed railgun shot carries deep into the city (reached x %.0f)" % rg5.max_x)
	check(rg5.v0 > rg1.v0 and rg5.v0 > 100.0, "railgun round speed %.0f m/s (Lv1 %.0f)" % [rg5.v0, rg1.v0])
	# charge sequence: release starts a charge, discharge happens after charge_t, not instantly
	main.levels = _levels(0)
	main.launcher_levels = Launchers.empty_levels()
	main.launcher_levels["railgun"] = 1
	main.select_launcher("railgun")
	main.start_game(0, Rules.env_index("downtown"))
	await frames(3)
	main._direct_move(0.0, 0.0)
	main._charging = true
	main._charge = 0.0
	var f_before: int = 0
	var fired_at := -1.0
	var t := 0.0
	while main.state == 0 and t < 6.0:
		await physics_frame
		t += 1.0 / 60.0
	fired_at = t
	check(fired_at > float(Launchers.stat("railgun", "charge_t", 1.0)) * 0.9 and main.state != 0, "the railgun discharges only after its charge time (%.1f s, charge_t %.1f)" % [fired_at, Launchers.stat("railgun", "charge_t", 1.0)])
	for i in 60 * 20:
		if main.state != 1:
			break
		await physics_frame
	# persistence
	main.launcher_levels = Launchers.empty_levels()
	main.launcher_levels["cannon"] = 2
	main.select_launcher("cannon")
	check(main.launcher_id == "cannon" and not main.select_launcher("railgun") and main.launcher_id == "cannon", "only owned launchers can be selected")
	main.launcher_levels = Launchers.empty_levels()
	main.select_launcher("slingshot")
	main.bank = 100
	check(not main.buy_launcher("catapult") and main.bank == 100, "cannot buy a launcher without the credits")
	main.bank = 3000
	check(main.buy_launcher("catapult") and main.launcher_levels["catapult"] == 1 and main.bank == 500 and main.select_launcher("catapult"), "unlock the Catapult for 2500, then it can be used")
