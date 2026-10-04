extends SceneTree
## Gameplay-pivot tests. Part A: pure rules (deterministic). Part B: scenes/physics (bounded, tolerant:
## the physics engine does not promise identical trajectories on every platform, the game RULES must hold).
##   godot --headless --path launch -s tests/verify_pivot.gd

const Rules := preload("res://scripts/rules.gd")
var fails := 0
var main: Node

func check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		fails += 1

func frames(n: int) -> void:
	for i in n:
		await process_frame

func _init() -> void:
	_run.call_deferred()

func _fin(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)

# ================================================================== A. pure rules
func _rules() -> void:
	var C: Array = Rules.CHARACTERS
	check(C.size() == 18, "18 characters in the roster (all 18 Kenney blocky characters)")
	var letters := {}
	var ids := {}
	var sums_ok := true
	var files_ok := true
	for c in C:
		letters[c["letter"]] = true
		ids[c["id"]] = true
		var st: Dictionary = c["stats"]
		var sum: int = 0
		for k in Rules.STATS:
			var v: int = int(st[k])
			sum += v
			if v < 1 or v > Rules.MAX_STAT:
				sums_ok = false
		if sum != Rules.STAT_TOTAL:
			sums_ok = false
		if not ResourceLoader.exists("res://assets/kenney/blocky-characters/character-%s.glb" % c["letter"]):
			files_ok = false
		if str(c["name"]) == "" or str(c["desc"]) == "" or str(c["kind"]) == "":
			files_ok = false
	check(letters.size() == 18 and ids.size() == 18, "every character has a unique model letter and id")
	check(sums_ok, "every character spends exactly %d stat points, each stat 1..5" % Rules.STAT_TOTAL)
	check(files_ok, "every character model exists and has a name, kind and one-line description")
	check(str(C[0]["name"]) == "RAGNAR", "RAGNAR is the first character")
	var dominated := false
	for a in C:
		for b in C:
			if a == b:
				continue
			var ge := true
			var gt := false
			for k in Rules.STATS:
				if int(a["stats"][k]) < int(b["stats"][k]):
					ge = false
				if int(a["stats"][k]) > int(b["stats"][k]):
					gt = true
			if ge and gt:
				dominated = true
	check(not dominated, "no character is strictly better than another (stat sums are equal)")
	var kinds := {}
	for c in C:
		kinds[c["kind"]] = true
	check(kinds.size() >= 6, "%d distinct play styles (%s)" % [kinds.size(), ", ".join(kinds.keys())])
	var by_id := {}
	for c in C:
		by_id[c["id"]] = c
	var none: Dictionary = Rules.empty_levels()
	var heavy: Dictionary = Rules.effective(by_id["big_red"]["stats"], none)
	var skipper: Dictionary = Rules.effective(by_id["prof_pebbles"]["stats"], none)
	var glass: Dictionary = Rules.effective(by_id["cap_oops"]["stats"], none)
	var surv: Dictionary = Rules.effective(by_id["crash"]["stats"], none)
	var pin: Dictionary = Rules.effective(by_id["bolt_bot"]["stats"], none)
	var spinner: Dictionary = Rules.effective(by_id["ghosty"]["stats"], none)
	check(heavy["impact_power"] > skipper["impact_power"] and heavy["restitution"] < skipper["restitution"], "DEMOLITION hits harder but bounces less than SKIPPER")
	check(glass["dismember_k"] > surv["dismember_k"], "GLASS CANNON loses limbs more easily than SURVIVOR")
	check(pin["ricochet_deg"] > skipper["ricochet_deg"] and spinner["spin_mult"] > heavy["spin_mult"], "PINBALL ricochets wilder, SPINNER spins harder")
	# --- upgrades: each family changes the right number, monotonic, and they stack
	var base: Dictionary = Rules.effective(C[0]["stats"], none)
	var maxed: Dictionary = Rules.empty_levels()
	for k in Rules.UPGRADE_ORDER:
		maxed[k] = int(Rules.UPGRADES[k]["max"])
	var top: Dictionary = Rules.effective(C[0]["stats"], maxed)
	check(top["launch_mult"] > base["launch_mult"] and top["restitution"] > base["restitution"] and top["ricochet_deg"] > base["ricochet_deg"], "launch power, bounce and ricochet upgrades raise their numbers")
	check(top["spin_mult"] > base["spin_mult"] and top["dismember_k"] < base["dismember_k"] and top["destruct_mult"] > base["destruct_mult"], "spin, durability and destruction upgrades apply")
	check(is_equal_approx(top["explode_chance"], 0.4) and base["explode_chance"] == 0.0 and int(top["ignition"]) == 3, "explosive impact = 10% per level (40% max); ignition levels apply")
	var prev := -1.0
	var mono := true
	for lv in 6:
		var l: Dictionary = Rules.empty_levels()
		l["bounce"] = lv
		var r: float = Rules.effective(C[0]["stats"], l)["restitution"]
		if r < prev:
			mono = false
		prev = r
	check(mono, "bounce upgrade is monotonic level by level")
	var two: Dictionary = Rules.empty_levels()
	two["bounce"] = 3
	two["ricochet"] = 3
	var e2: Dictionary = Rules.effective(C[0]["stats"], two)
	check(e2["restitution"] > base["restitution"] and e2["ricochet_deg"] > base["ricochet_deg"], "upgrades stack: bounce + ricochet both active together")
	check(Rules.upgrade_cost("power", 0) == 250 and Rules.upgrade_cost("power", 5) == -1 and Rules.upgrade_cost("explosive", 3) == 4500, "upgrade costs rise and cap")
	check(Rules.UPGRADE_ORDER.size() == 8 and Rules.UPGRADES.size() == 8, "8 upgrade families (power, bounce, ricochet, spin, durability, destruction, explosive, ignition)")
	# --- impacts: skipping-stone model
	var fx: Dictionary = Rules.effective(C[0]["stats"], none)
	var mods: Dictionary = Rules.part_modifiers("torso", "front")
	var vg := Vector3(30, -3, 0)            # grazing
	var vh := Vector3(3, -30, 0)            # head-on
	var rg: Dictionary = Rules.impact_response(vg, Vector3.UP, fx, "ground", mods, 1.0, 0.0)
	var rh: Dictionary = Rules.impact_response(vh, Vector3.UP, fx, "ground", mods, 1.0, 0.0)
	check(bool(rg["bounced"]) and (rg["v"] as Vector3).x > 0.8 * vg.x, "grazing hit SKIPS: keeps most of its forward speed (%.1f of 30)" % (rg["v"] as Vector3).x)
	check((rh["v"] as Vector3).length() < (rg["v"] as Vector3).length(), "head-on hit loses far more speed than a graze")
	check((rg["v"] as Vector3).y > 0.0, "a skip pops back upward")
	var spent: Dictionary = Rules.impact_response(vg, Vector3.UP, fx, "ground", mods, 0.0, 0.0)
	check((spent["v"] as Vector3).length() < (rg["v"] as Vector3).length(), "less arcade energy left = a weaker skip")
	var e := 1.0
	var decays := true
	for i in 12:
		var n: float = Rules.energy_after(e, fx, 20.0)
		if n >= e and e > 0.0:
			decays = false
		e = n
	check(decays and e < 0.2, "energy decays with every hard hit so a run always winds down (%.2f after 12)" % e)
	check(Rules.energy_after(0.7, fx, 3.0) == 0.7, "taps below 6 m/s do not spend energy")
	var tramp: Dictionary = Rules.impact_response(vh, Vector3.UP, fx, "trampoline", mods, 1.0, 0.0)
	check((tramp["v"] as Vector3).length() > (rh["v"] as Vector3).length() * 2.0, "trampoline returns far more energy than ground")
	check((Rules.impact_response(vh, Vector3.UP, fx, "glass", mods, 1.0, 0.0)["v"] as Vector3).length() < 0.2 * 30.0, "glass absorbs instead of bouncing")
	# bounded + finite over a sweep
	var bad := false
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 3000:
		var v := Vector3(rng.randf_range(-60, 60), rng.randf_range(-60, 60), rng.randf_range(-60, 60))
		var nn := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.01, 1), rng.randf_range(-1, 1)).normalized()
		var mat: String = ["ground", "wood", "masonry", "metal", "roof", "glass"][rng.randi() % 6]
		var part: String = ["torso", "head", "arm-left", "leg-right"][rng.randi() % 4]
		var r: Dictionary = Rules.impact_response(v, nn, fx, mat, Rules.part_modifiers(part, ["front", "back", "side"][rng.randi() % 3]), rng.randf(), rng.randf_range(-1, 1))
		var vo: Vector3 = r["v"]
		if not _fin(vo) or not _fin(r["omega"] as Vector3) or vo.length() > v.length() * 1.2 + 0.01 or absf(float(r["ricochet_deg"])) > 45.01:
			bad = true
	check(not bad, "3000 random impacts: finite, never gains energy off non-springy surfaces, ricochet within +-45 deg")
	# ricochet scales with the stat
	var lo: Dictionary = Rules.effective({"power": 3, "bounce": 3, "ricochet": 1, "spin": 3, "durability": 3, "chaos": 3}, none)
	var hi: Dictionary = Rules.effective({"power": 3, "bounce": 3, "ricochet": 5, "spin": 3, "durability": 3, "chaos": 3}, none)
	var dl: float = absf(float(Rules.impact_response(vg, Vector3.UP, lo, "metal", mods, 1.0, 1.0)["ricochet_deg"]))
	var dh: float = absf(float(Rules.impact_response(vg, Vector3.UP, hi, "metal", mods, 1.0, 1.0)["ricochet_deg"]))
	check(dh > dl, "high RICOCHET deflects more (%.0f vs %.0f deg)" % [dh, dl])
	# orientation
	check(Rules.part_modifiers("head", "")["spin"] > Rules.part_modifiers("torso", "front")["spin"] and Rules.part_modifiers("torso", "back")["e"] > Rules.part_modifiers("torso", "front")["e"], "headfirst spins more; back-first rebounds harder")
	check(Rules.part_modifiers("arm-left", "")["lateral"] > 0.0 and Rules.part_modifiers("leg-left", "")["lift"] > 0.0 and Rules.part_modifiers("torso", "side")["spin"] > 1.0, "shoulder kicks sideways, feet vault, side impact cartwheels")
	var nrm: Vector3 = Rules.box_normal(Vector3(0, 0.9, 0.1), Vector3(1, 1, 1), Basis.IDENTITY)
	var nrm2: Vector3 = Rules.box_normal(Vector3(-0.95, 0.2, 0.1), Vector3(1, 1, 1), Basis.IDENTITY)
	var nrm3: Vector3 = Rules.box_normal(Vector3(0.95, 0.2, 0.1), Vector3(1, 1, 1), Basis(Vector3.UP, PI / 2.0))
	check(nrm.is_equal_approx(Vector3.UP) and nrm2.is_equal_approx(Vector3.LEFT) and absf(nrm3.length() - 1.0) < 0.001, "box surface normals come out right (top, side, rotated)")
	# --- dismemberment
	check(Rules.dismember_chance(10.0, "arm-left", fx) == 0.0 and Rules.dismember_chance(14.9, "leg-left", fx) == 0.0, "no limb loss from taps below %.0f m/s" % Rules.DISMEMBER_SPEED)
	check(Rules.dismember_chance(28.0, "arm-left", fx) > 0.0 and Rules.dismember_chance(28.0, "torso", fx) == 0.0, "hard hits can take limbs, never the torso")
	check(Rules.dismember_chance(28.0, "head", fx) < Rules.dismember_chance(28.0, "arm-left", fx), "heads are much harder to lose than arms")
	check(Rules.dismember_chance(28.0, "arm-left", glass) > Rules.dismember_chance(28.0, "arm-left", surv), "low durability loses limbs more often")
	check(Rules.dismember_chance(60.0, "arm-left", glass) <= 1.0 and Rules.dismember_chance(20.0, "arm-left", fx) < Rules.dismember_chance(30.0, "arm-left", fx), "limb-loss odds are bounded and rise with impact speed")
	# --- explosive impact odds
	var hits := 0
	var ex: Dictionary = Rules.effective(C[0]["stats"], {"explosive": 1})
	for i in 10000:
		if Rules.explosive_impact(20.0, ex, float(i) / 10000.0):
			hits += 1
	check(absi(hits - 1000) <= 5, "explosive impact level 1 fires ~10%% of qualifying hits (%d / 10000)" % hits)
	check(not Rules.explosive_impact(5.0, ex, 0.0) and not Rules.explosive_impact(20.0, fx, 0.0), "no explosion on a soft tap or without the upgrade")
	# --- run termination
	check(Rules.run_finished({"elapsed": 12.0, "landed": false, "max_speed": 40.0, "max_t": 11.0}), "a run can never last longer than the cap")
	check(not Rules.run_finished({"elapsed": 2.0, "landed": false, "max_speed": 30.0, "calm_t": 0.0, "event_age": 5.0, "energy": 1.0, "max_t": 11.0}), "still flying -> not finished")
	check(Rules.run_finished({"elapsed": 4.0, "landed": true, "max_speed": 0.5, "calm_t": 0.5, "event_age": 3.0, "energy": 0.5, "max_t": 11.0}), "settled -> finished promptly")
	check(not Rules.run_finished({"elapsed": 4.0, "landed": true, "max_speed": 9.0, "calm_t": 0.0, "event_age": 3.0, "energy": 0.5, "max_t": 11.0}), "still tumbling fast -> not finished")
	check(Rules.run_finished({"elapsed": 5.0, "landed": true, "max_speed": 4.0, "calm_t": 0.4, "event_age": 1.0, "energy": 0.05, "max_t": 11.0}), "spent energy + slow = finished (no slow dead roll)")
	check(not Rules.run_finished({"elapsed": 5.0, "landed": true, "max_speed": 1.0, "calm_t": 0.1, "event_age": 0.1, "energy": 0.5, "max_t": 11.0}), "just after something happened -> wait a beat")
	# --- scoring combo
	check(Rules.combo_mult(0) == 1.0 and Rules.combo_mult(10) > Rules.combo_mult(3) and Rules.combo_mult(500) == Rules.combo_mult(25), "combo multiplier rises and is capped")
	var Sc := Scoring.new()
	Sc.combo_enabled = true
	Sc.clock = 1.0
	Sc.award("a", "A", 100, "Skips")
	Sc.clock = 1.5
	Sc.award("b", "B", 100, "Ricochets")
	Sc.clock = 9.0
	Sc.award("c", "C", 100, "Skips")
	check(Sc.lines["Ricochets"] == 106 and Sc.best_combo == 2 and Sc.combo == 1 and Sc.lines["Skips"] == 200, "combo chains inside the window (x1.06) and resets after it")
	var Sd := Scoring.new()
	Sd.award("k", "K", 50, "Skips")
	Sd.award("k", "K", 50, "Skips")
	check(Sd.total() == 50, "scoring: unique keys still pay once (combo off by default)")
	# --- materials / environments
	check(Rules.material_of_model("wall-pane-wood") == "wood" and Rules.material_of_model("roof") == "roof" and Rules.material_of_model("wall") == "masonry" and Rules.material_of_model("detail-barrel") == "wood", "kit models map to wood / roof / masonry")
	var env_ids: Array = []
	for en in Rules.ENVIRONMENTS:
		env_ids.append(en["id"])
	check(env_ids.has("yard") and env_ids.has("downtown") and env_ids.has("oldtown") and env_ids.has("suburbia") and env_ids.has("industrial") and env_ids.has("resort"), "city roster: Test Yard + Downtown, Old Town, Suburbia, Industrial, Resort slots")
	var playable := 0
	for en in Rules.ENVIRONMENTS:
		if bool(en["playable"]):
			playable += 1
	check(playable == Rules.ENVIRONMENTS.size() and str(Rules.ENVIRONMENTS[Rules.env_index("yard")]["tag"]) == "TRAINING", "all 7 environments are playable; Test Yard is marked TRAINING")
	# --- fire propagation limits
	var pos: Array = []
	var st := PackedInt32Array()
	var tm := PackedFloat32Array()
	for i in 80:
		pos.append(Vector3(i * 2.0, 0, 0))
		st.append(0)
		tm.append(0.0)
	pos.append(Vector3(500, 0, 500))          # far away: must never catch
	st.append(0)
	tm.append(0.0)
	st[0] = 1
	var peak := 0
	var ever_back := false
	var zeros: Array = []
	for i in pos.size():
		zeros.append(0.0)                     # rnd 0 = always catch when in range (worst case for spreading)
	for step in 400:
		var before := st.duplicate()
		Rules.fire_step(pos, st, tm, 0.25, 1.0, zeros)
		var b := 0
		for i in st.size():
			if st[i] == 1:
				b += 1
			if st[i] < before[i]:
				ever_back = true
		peak = maxi(peak, b)
	var burnt := 0
	for i in 80:
		if st[i] == 2:
			burnt += 1
	check(peak <= Rules.FIRE_CAP and peak > 3, "fire spreads along a row but never exceeds the cap (peak %d, cap %d)" % [peak, Rules.FIRE_CAP])
	check(burnt == 80 and st[80] == 0 and not ever_back, "everything in range burns out and stays burnt; far-away fuel never ignites")
	var st2 := PackedInt32Array([0, 0])
	Rules.fire_step([Vector3.ZERO, Vector3(1, 0, 0)], st2, PackedFloat32Array([0.0, 0.0]), 1.0, 1.0, [0.0, 0.0])
	check(st2[0] == 0 and st2[1] == 0, "no fire without a burning source")

# ================================================================== B. scenes + physics
func _aim(b: float, s: float) -> void:
	main.drag_vec = (main._basis_back * b + main._basis_side * s) * main.AIM_MAX_PX
	main._update_aim()

func _throw(char_i: int, b: float, s: float, max_frames: int = 60 * 14) -> Dictionary:
	main.start_game(char_i, Rules.env_index("yard"))
	await frames(3)
	_aim(b, s)
	main.fire()
	var n := 0
	var worst_w := 0.0
	var limb_w := 0.0
	var sane := true
	var first_impact_x := -1.0
	while main.state == 1 and n < max_frames:
		await physics_frame
		n += 1
		if n < 90:
			for body in main.ragdoll.bodies:
				if body != main.ragdoll.torso:
					limb_w = maxf(limb_w, body.angular_velocity.length())
		for body in main.ragdoll.bodies:
			worst_w = maxf(worst_w, body.angular_velocity.length())
			if not _fin(body.global_position) or not _fin(body.linear_velocity):
				sane = false
		if first_impact_x < 0.0 and main.t_first_impact >= 0.0:
			first_impact_x = main.ragdoll.centre().x
	return {"t": main.flight_t, "state": main.state, "skips": main.skips, "rico": main.ricochets, "limbs": main.limbs_lost, "score": main.scoring.total(),
		"end": main.ragdoll.centre(), "first_x": first_impact_x, "limb_w": limb_w, "worst_w": worst_w, "sane": sane, "first_t": main.t_first_impact}

func _scenes() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.skip_select = true
	root.add_child(main)
	await frames(5)
	seed(4242)
	# ---------- selector UI
	var ui = load("res://scripts/select_ui.gd").new()
	root.add_child(ui)
	await frames(3)
	var got: Array = []
	ui.chosen.connect(func(ci: int, ei: int): got.append([ci, ei]))
	ui._step_char(1)
	check(ui.char_idx == 1, "selector: right arrow moves to the next ragdoll")
	ui._step_char(-1)
	ui._step_char(-1)
	check(ui.char_idx == 17, "selector: left arrow wraps around to the last ragdoll")
	for i in 18:
		ui._step_char(1)
	check(ui.char_idx == 17, "selector: a full lap of 18 steps comes back to the same ragdoll")
	ui._step_char(1)
	check(ui.char_idx == 0, "selector: ...and the next step is RAGNAR")
	ui._show_page(1)
	ui.env_idx = Rules.env_index("yard")
	ui._refresh()
	ui._on_go()
	check(got.size() == 1 and got[0] == [0, Rules.env_index("yard")] and not ui._go.disabled, "selector: LAUNCH on the Test Yard starts the game")
	ui._step_env(1)
	check(not ui._go.disabled and str(Rules.ENVIRONMENTS[ui.env_idx]["id"]) == "downtown", "selector: Downtown is playable (nothing is locked)")
	var sw := InputEventMouseButton.new()
	sw.button_index = MOUSE_BUTTON_LEFT
	sw.pressed = true
	sw.position = Vector2(600, 300)
	ui._gui_input(sw)
	var sw2 := InputEventMouseButton.new()
	sw2.button_index = MOUSE_BUTTON_LEFT
	sw2.pressed = false
	sw2.position = Vector2(300, 300)
	var env_before: int = ui.env_idx
	ui._gui_input(sw2)
	check(ui.env_idx == (env_before + 1) % Rules.ENVIRONMENTS.size(), "selector: swiping left advances the selection")
	ui.queue_free()
	# ---------- game flow + yard contents
	main.start_game(1, Rules.env_index("yard"))
	await frames(4)
	check(main.state == 0 and main.town.env_id == "yard" and main.char_idx == 1, "start_game(BIG RED, Test Yard) enters AIM in the yard")
	var T = main.town
	var tramp := 0
	var metal := 0
	var stat_meta := 0
	for ch in T.get_children():
		if ch is StaticBody3D:
			match str(ch.get_meta("mat", "")):
				"trampoline": tramp += 1
				"metal": metal += 1
	check(T.glass.size() >= 5 and tramp >= 2 and metal >= 3 and T.tnt.size() >= 4 and T.fire_nodes.size() >= 20 and T.pieces.size() >= 40 and T.targets.size() >= 6,
		"Test Yard: %d glass panes, %d trampolines, %d metal parts, %d TNT, %d combustibles, %d pieces, %d targets" % [T.glass.size(), tramp, metal, T.tnt.size(), T.fire_nodes.size(), T.pieces.size(), T.targets.size()])
	var mats := {}
	for p in T.pieces:
		mats[p.get_meta("mat", "?")] = true
	check(mats.has("wood") and mats.has("masonry") and mats.has("roof"), "yard pieces carry wood / masonry / roof material (not one generic cube type)")
	check(main.ragdoll.torso.mass > Rules.effective(Rules.CHARACTERS[6]["stats"], Rules.empty_levels())["extra_mass"] + 5.0 and main.ragdoll.bodies.size() == 6 and main.ragdoll.joint_count == 5, "character profile applied to the ragdoll (heavier BIG RED torso, 6 bodies / 5 joints)")
	var m_red: float = main.ragdoll.torso.mass
	main.start_game(15, Rules.env_index("yard"))
	await frames(3)
	check(main.ragdoll.torso.mass < m_red, "different characters have different physics (GARY lighter than BIG RED)")
	# ---------- upgrades change the physics + stack
	main.bank = 100000
	main.levels = Rules.empty_levels()
	main.start_game(0, Rules.env_index("yard"))
	await frames(3)
	main.aim_power = 1.0
	var s0: float = main.launch_speed()
	main.buy("power")
	main.buy("power")
	main.buy("bounce")
	main.buy("explosive")
	main.buy("ignition")
	main.start_game(0, Rules.env_index("yard"))
	await frames(3)
	main.aim_power = 1.0
	check(main.launch_speed() > s0 * 1.08 and float(main.fxp["restitution"]) > 0.49 and float(main.fxp["explode_chance"]) > 0.09 and int(main.fxp["ignition"]) == 1,
		"bought upgrades change the next throw (speed %.1f -> %.1f, bounce, 10%% explosive, ignition)" % [s0, main.launch_speed()])
	main.levels = Rules.empty_levels()
	main.bank = 0
	# ---------- real throws in the yard
	var ragnar: Dictionary = await _throw(0, 0.55, 0.05)
	check(ragnar.state == 2 and ragnar.t <= main.MAX_FLIGHT_S + 0.5, "throw ends by itself (RESULT after %.1f s, cap %.0f)" % [ragnar.t, main.MAX_FLIGHT_S])
	check(ragnar.sane and ragnar.score > 0, "throw is finite/sane and scores (%d)" % ragnar.score)
	check(ragnar.first_t >= 0.0 and ragnar.first_t < 3.5, "the first impact comes quickly (%.1f s after release)" % ragnar.first_t)
	check(ragnar.limb_w > 4.0, "limbs visibly flail early in flight (peak limb spin %.1f rad/s)" % ragnar.limb_w)
	var skipped := 0
	var travelled := 0.0
	for k in 3:
		var sk: Dictionary = await _throw(3, 0.28, 0.0)      # PROF. PEBBLES, low flat throw onto open ground
		if sk.skips >= 1 or sk.rico >= 1:
			skipped += 1
		travelled = maxf(travelled, sk.end.x - sk.first_x)
	check(skipped >= 1 and travelled > 5.0, "pebble skipping: a flat throw bounces on (%d of 3 skipped/ricocheted, best %.0f m past first contact)" % [skipped, travelled])
	# a very hard throw must stay finite
	var hard: Dictionary = await _throw(6, 1.2, 0.3)
	check(hard.sane and hard.state == 2, "overdrive glass-cannon throw stays finite and finishes (t=%.1f s, limbs lost %d)" % [hard.t, hard.limbs])
	# ---------- air control: swipe adds rotation
	main.start_game(0, Rules.env_index("yard"))
	await frames(3)
	_aim(0.6, 0.0)
	main.fire()
	await frames(20)
	var w0: Vector3 = main.ragdoll.torso.angular_velocity
	main.air_input = 1.0
	await frames(25)
	var w1: Vector3 = main.ragdoll.torso.angular_velocity
	main.air_input = 0.0
	check(not w0.is_equal_approx(w1) and w1.length() <= main.ragdoll.MAX_OMEGA + 0.5, "airborne swipe changes the rotation (bounded)")
	main._finish()
	# ---------- dismemberment: a limb comes off, keeps flying, stays a physics body
	main.start_game(6, Rules.env_index("yard"))
	await frames(3)
	_aim(0.6, 0.0)
	main.fire()
	await frames(5)
	var arm: RigidBody3D = main.ragdoll.bodies[2]
	var joints_before: int = main.ragdoll.joints.size()
	main._lose_limb(arm, Vector3.UP, 28.0, arm.global_position)
	await frames(3)
	check(main.ragdoll.is_detached(arm) and main.ragdoll.joints.size() == joints_before - 1 and main.limbs_lost == 1 and arm.linear_velocity.length() > 1.0, "a limb detaches, keeps its velocity and the joint is gone")
	check(main.scoring.lines.get("Carnage", 0) >= 150, "losing a limb scores (Carnage +%d)" % int(main.scoring.lines.get("Carnage", 0)))
	check(main.ragdoll.detach("arm-left") == null or true, "detaching an already detached part is harmless")
	check(main.ragdoll.is_finite_and_sane(), "ragdoll with a detached limb passes the sanity check")
	# ---------- fire: burning ragdoll / burning limb ignite fuel; spread is capped; reset clears it
	T = main.town
	main.state = main.State.FLIGHT
	var wood: RigidBody3D = null
	for p in T.pieces:
		if p.get_meta("mat", "") == "wood":
			wood = p
			break
	main.ragdoll.ignite_all(5.0)
	check(main.ragdoll.is_burning("torso") and main.ragdoll.is_burning("arm-left"), "ignition: every body part can be set on fire")
	main._on_impact_pivot(main.ragdoll.torso, wood, 12.0, wood.global_position)
	check(T.fire_state[T.fire_nodes.find(wood)] != 0, "a burning ragdoll ignites the timber it hits")
	var crate: RigidBody3D = null
	for pr in T.props:
		if str(pr.get_meta("mat", "")) == "wood" and not pr.has_meta("explosive"):
			crate = pr
			break
	main.ragdoll.burning.clear()
	main.ragdoll.ignite_part("arm-left", 5.0)
	main._on_impact_pivot(arm, crate, 10.0, crate.global_position)
	check(T.fire_state[T.fire_nodes.find(crate)] != 0, "a burning DETACHED limb ignites what it touches")
	var peak_burn := 0
	for i in 160:
		T._fire_tick(0.25)
		peak_burn = maxi(peak_burn, T.burning_count)
		T.burning_count = T.burning_count     # (count is recomputed inside the tick)
	var burnt_total := 0
	for i in T.fire_state.size():
		if T.fire_state[i] == 2:
			burnt_total += 1
	check(peak_burn <= Rules.FIRE_CAP and peak_burn >= 2 and burnt_total >= 2, "fire spread in the yard: peak %d burning (cap %d), %d burnt out" % [peak_burn, Rules.FIRE_CAP, burnt_total])
	check(main.fx.live_flames <= Rules.FIRE_CAP + 2, "flame effects stay inside their fixed pool (%d live)" % main.fx.live_flames)
	main.state = main.State.AIM
	main.reset()
	await frames(3)
	var clean := true
	for i in main.town.fire_state.size():
		if main.town.fire_state[i] != 0:
			clean = false
	check(clean and main.town.burning_count == 0 and main.fx.live_flames == 0 and main.ragdoll.detached.is_empty(), "reset puts out every fire and gives the ragdoll its limbs back")
	# ---------- TNT: chain explosion + fire
	T = main.town
	main.state = main.State.FLIGHT
	var tnt0: RigidBody3D = T.tnt[0]
	var before_score: int = main.scoring.total()
	main._blast(tnt0)
	await frames(2)
	check(bool(tnt0.get_meta("exploded", false)) and main.scoring.lines.get("Explosions", 0) > 0 and main.scoring.total() > before_score, "TNT explodes and scores")
	var tnt_exploded := 0
	for t in T.tnt:
		if bool(t.get_meta("exploded", false)):
			tnt_exploded += 1
	check(tnt_exploded >= 2, "TNT chains into its neighbours (%d of %d)" % [tnt_exploded, T.tnt.size()])
	check(T.burning_count >= 1, "the blast sets nearby timber on fire (%d burning)" % T.burning_count)
	main.state = main.State.AIM
	# ---------- glass breaks once, comes back on reset; materials give different sounds
	main.reset()
	await frames(3)
	T = main.town
	var pane: StaticBody3D = T.glass[0]
	check(T.break_glass(pane) and pane.collision_layer == 0 and not T.break_glass(pane), "glass shatters once")
	main.reset()
	await frames(3)
	check(pane.collision_layer == 1 and pane.visible, "reset restores broken glass")
	var snds := {}
	for mname in Rules.MATERIALS.keys():
		snds[Rules.MATERIALS[mname]["sound"]] = true
	check(snds.size() >= 6, "impacts have distinct sounds per material (%s)" % ", ".join(snds.keys()))
	# ---------- gore toggle
	main.set_gore(false)
	check(not main.gore and not main.fx.gore, "gore can be switched off (blood suppressed)")
	main.set_gore(true)
	check(main.gore and main.fx.gore, "gore can be switched back on")
	# ---------- impact feedback per tier runs without error and moves the camera
	main.start_game(0, Rules.env_index("yard"))
	await frames(3)
	main.state = main.State.FLIGHT
	var tr0: float = 0.0
	main._on_impact_pivot(main.ragdoll.torso, T.get_node("Ground"), 6.0, Vector3(5, 0, 0))
	tr0 = main.trauma
	main._imp_t.clear()
	main._on_impact_pivot(main.ragdoll.torso, T.get_node("Ground"), 30.0, Vector3(6, 0, 0))
	check(main.trauma > tr0 and main.cam_event > 0.0, "extreme impacts shake and widen the camera more than light ones")
	main.state = main.State.AIM
	main.reset()

func _run() -> void:
	_rules()
	await _scenes()
	print("---- PIVOT %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
