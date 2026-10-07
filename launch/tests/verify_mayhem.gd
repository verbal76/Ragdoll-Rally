extends SceneTree
## Mayhem pass: 20-level scaling, impact energy / penetration, shell destruction (expand, punch, collapse, restore, budgets),
## save migration. Board-wide audits live in audit_boards.gd / verify_cities.gd.
##   godot --headless --path launch -s tests/verify_mayhem.gd
const Rules := preload("res://scripts/rules.gd")
const Destruction := preload("res://scripts/destruction.gd")
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
	await _shells()
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
