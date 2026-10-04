extends SceneTree
## v13 gameplay-round tests: trajectory governor, world boundary, economy (score vs bank), skip scoring,
## release gate for economy test controls, upgrades and character stats.
##   godot --headless --path launch -s tests/verify_v13.gd

const Rules := preload("res://scripts/rules.gd")
const Main := preload("res://scripts/main.gd")
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

## Reproduces main._update_aim for a gesture given as (pull-back b, sideways sd) in units of full-power drag.
func _gesture(b: float, sd: float, lv: Dictionary) -> Dictionary:
	var p := Vector2(sd, b)
	if p.length() > Main.OVERDRIVE_MAX:
		p = p.normalized() * Main.OVERDRIVE_MAX
	var power: float = p.length()
	var up: float = clampf(p.y, 0.05, 1.0) * 1.05
	var side: float = -clampf(p.x, -1.0, 1.0) * Main.SIDE_GAIN
	var dir: Vector3 = Rules.launch_dir(Vector3(1.0, 0.0, side), up / sqrt(1.0 + side * side))
	var fx: Dictionary = Rules.effective(Rules.CHARACTERS[0]["stats"], lv)
	var v: float = Main.speed_for_power(power) * float(fx.get("launch_mult", 1.0))
	var pitch: float = asin(clampf(dir.y, -1.0, 1.0))
	var gv: float = Rules.governed_speed(v, pitch, fx)
	return {"pitch": rad_to_deg(pitch), "speed": gv, "raw_speed": v, "range": Rules.ideal_range(gv, pitch), "apex": Rules.ideal_apex(gv, pitch),
		"range_cap": float(fx.get("range_cap", 0.0)), "apex_cap": float(fx.get("apex_cap", 0.0)), "power": power}

func _levels(n: int) -> Dictionary:
	var d := Rules.empty_levels()
	for k in d.keys():
		d[k] = mini(n, int(Rules.UPGRADES[k]["max"]))
	return d

func _run() -> void:
	# ============================================================ TRAJECTORY
	var gestures := {
		"shallow": [0.12, 0.0], "normal": [0.55, 0.0], "high": [0.9, 0.0], "extreme vertical": [1.45, 0.0],
		"diagonal": [0.8, 0.8], "short fast": [0.3, 0.0], "long fast": [1.3, 0.2], "slow": [0.2, 0.05], "screen edge": [0.4, 1.4],
		"full back-left": [1.0, -1.0], "tiny": [0.05, 0.0],
	}
	var max_pitch := 0.0
	var worst_range := 0.0
	var worst_apex := 0.0
	var apex_over_cap := false
	var range_over_cap := false
	for lvn in [0, 3, 5]:
		var lv: Dictionary = _levels(lvn)
		for gn in gestures.keys():
			var g: Dictionary = _gesture(gestures[gn][0], gestures[gn][1], lv)
			max_pitch = maxf(max_pitch, g.pitch)
			worst_range = maxf(worst_range, g.range)
			worst_apex = maxf(worst_apex, g.apex)
			if g.apex > g.apex_cap + 0.01:
				apex_over_cap = true
			if g.range > g.range_cap + 0.01:
				range_over_cap = true
	check(max_pitch < Rules.MAX_PITCH_DEG, "gesture matrix (11 gestures x 3 upgrade tiers): launch pitch never reaches the %.0f deg ceiling (max %.1f)" % [Rules.MAX_PITCH_DEG, max_pitch])
	check(not apex_over_cap and not range_over_cap, "ideal apex <= cap and ideal range <= cap for every gesture/upgrade combination (worst range %.0f m, apex %.0f m)" % [worst_range, worst_apex])
	check(worst_range < 181.0 and worst_range < Rules.RANGE_CAP_BASE + 5 * Rules.RANGE_CAP_PER_LEVEL + 0.5, "no gesture can out-range the playfield (%.0f m < 215 m wall)" % worst_range)
	for dg in [5.0, 12.0, 20.0, 28.0]:
		check(is_equal_approx(Rules.soft_pitch_deg(dg), maxf(dg, Rules.MIN_PITCH_DEG)), "pitch %.0f deg passes through untouched (loft, rooftops, skips keep their angle)" % dg)
	var prev := 0.0
	var mono := true
	for dg in range(0, 91, 3):
		var o: float = Rules.soft_pitch_deg(float(dg))
		if o < prev - 0.0001:
			mono = false
		prev = o
	check(mono and Rules.soft_pitch_deg(90.0) < Rules.MAX_PITCH_DEG and Rules.soft_pitch_deg(60.0) > 31.0, "soft pitch is monotonic, smooth and still rewards pulling higher (60 deg -> %.1f, 90 deg -> %.1f)" % [Rules.soft_pitch_deg(60.0), Rules.soft_pitch_deg(90.0)])
	var near_vertical: Vector3 = Rules.launch_dir(Vector3.RIGHT, 50.0)
	check(near_vertical.y < sin(deg_to_rad(Rules.MAX_PITCH_DEG)) and near_vertical.x > 0.76, "a near-vertical gesture (up=50) launches forward at < 40 deg, never straight up (dir %s)" % near_vertical)
	var g_lo: Dictionary = _gesture(0.55, 0.0, Rules.empty_levels())
	var g_hi: Dictionary = _gesture(1.0, 0.0, _levels(5))
	check(g_hi.range > g_lo.range * 1.5, "the governor still leaves room to scale: normal %.0f m -> maxed power %.0f m" % [g_lo.range, g_hi.range])
	var gs: float = Rules.governed_speed(30.0, deg_to_rad(15.0), {})
	check(is_equal_approx(gs, 30.0), "short throws are untouched by the governor")
	var sym := true
	for lvn in range(0, 6):
		var fx: Dictionary = Rules.effective(Rules.CHARACTERS[0]["stats"], _levels(lvn))
		if float(fx["range_cap"]) < Rules.RANGE_CAP_BASE or float(fx["apex_cap"]) < Rules.APEX_CAP_BASE:
			sym = false
	check(sym, "Launch Power raises the caps (range 150 -> 180 m, apex 55 -> 60 m)")

	# ============================================================ ECONOMY
	var total: int = Rules.total_upgrade_cost()
	var profiles := {
		"weak": {"Distance": 120, "Airtime": 40, "Flips": 30, "Smashed": 30, "Style": 20},
		"average": {"Distance": 220, "Airtime": 100, "Flips": 90, "Smashed": 60, "Style": 100, "Carnage": 150, "Skips": 228},
		"good": {"Distance": 312, "Flips": 173, "Airtime": 160, "Smashed": 92, "Style": 219, "Carnage": 420, "Skips": 480, "Targets": 300, "Ricochets": 150},
		"excellent": {"Distance": 450, "Flips": 300, "Airtime": 300, "Smashed": 300, "Style": 500, "Carnage": 900, "Skips": 700, "Targets": 900, "Ricochets": 400, "Explosions": 300},
	}
	var runs := {}
	for pn in profiles.keys():
		var score := 0
		for k in profiles[pn].keys():
			score += int(profiles[pn][k])
		var credit: int = Rules.bank_credit(profiles[pn])
		runs[pn] = float(total) / float(maxi(credit, 1))
		print("      %-9s score %5d -> credits %5d -> %.1f runs to max all 8 upgrades (%d cr)" % [pn, score, credit, runs[pn], total])
	check(runs["good"] >= 20.0 and runs["good"] <= 30.0, "a GOOD run maxes the 8 upgrades in 20-30 runs (%.1f)" % runs["good"])
	check(runs["excellent"] >= 10.0, "an EXCELLENT run cannot trivialise progression (>= 10 runs, %.1f)" % runs["excellent"])
	check(runs["weak"] > runs["average"] and runs["average"] > runs["good"] and runs["good"] > runs["excellent"], "progression is monotonic: weak > average > good > excellent runs needed")
	check(Rules.bank_credit(profiles["weak"]) >= 150, "weak players still bank something meaningful each run (%d)" % Rules.bank_credit(profiles["weak"]))
	check(int(Rules.UPGRADES["power"]["costs"][0]) <= 300 and Rules.bank_credit(profiles["weak"]) * 3 >= 250, "first upgrade is reachable within ~2-3 weak runs")
	var huge := {"Skips": 99999, "Distance": 99999, "Carnage": 99999}
	check(Rules.bank_credit(huge) == Rules.CREDIT_RUN_CAP, "no single run can bank more than %d credits (%d)" % [Rules.CREDIT_RUN_CAP, Rules.bank_credit(huge)])
	check(float(Rules.CREDIT_RUN_CAP) / float(total) < 0.08, "the per-run cap is < 8%% of the whole tree (%.1f%%)" % [100.0 * Rules.CREDIT_RUN_CAP / total])
	check(Rules.bank_credit({"Skips": 1000}) < 1000 and Rules.bank_credit({"Skips": 1000}) != 1000, "score and bank are different currencies (1000 skip score -> %d credits)" % Rules.bank_credit({"Skips": 1000}))
	# credits are monotone in score
	var last := -1
	var okm := true
	for sc in range(0, 8000, 100):
		var c: int = Rules.bank_credit({"Distance": sc})
		if c < last:
			okm = false
		last = c
	check(okm, "credits never decrease as score rises")
	check(int(Rules.upgrade_cost("power", 0)) == 250 and int(Rules.upgrade_cost("explosive", 3)) == 4500, "upgrade prices unchanged from v12 (the earning rate was fixed, not the prices)")

	# ============================================================ SKIP SCORING
	var seven := 0
	for n in range(1, 8):
		seven += Rules.skip_points(n)
	check(seven <= 500 and seven >= 280, "7 skips pay %d base points (v12 paid 2394 with combo compounding)" % seven)
	check(Rules.skip_points(20) == Rules.skip_points(6) and Rules.skip_points(2) > Rules.skip_points(1), "skip pay grows gently and is capped (n=1: %d, n=6+: %d)" % [Rules.skip_points(1), Rules.skip_points(6)])
	var cm := 1.0
	for i in 40:
		cm = Rules.combo_mult(i)
	check(Rules.combo_mult(40) <= 1.0 + 0.06 * Rules.COMBO_MAX_LINKS + 0.001 and Rules.combo_mult(40) < 2.0 and Rules.combo_mult(3) > Rules.combo_mult(1), "combo multiplier is capped at x%.2f (v12: x2.9)" % Rules.combo_mult(40))
	var chain := 0
	for n in range(1, 11):
		chain += int(Rules.skip_points(n) * Rules.combo_mult(n))
	check(chain < 1200 and chain > 450, "a 10-skip chain still feels big but bounded: %d pts" % chain)

	# ============================================================ UPGRADES + CHARACTERS
	var base := Rules.empty_levels()
	var mx := Rules.empty_levels()
	for k in mx.keys():
		mx[k] = int(Rules.UPGRADES[k]["max"])
	var f0: Dictionary = Rules.effective(Rules.CHARACTERS[0]["stats"], base)
	var f1: Dictionary = Rules.effective(Rules.CHARACTERS[0]["stats"], mx)
	check(float(f1["launch_mult"]) > float(f0["launch_mult"]) and float(f1["restitution"]) > float(f0["restitution"]) and float(f1["explode_chance"]) > float(f0["explode_chance"]) and int(f1["ignition"]) > int(f0["ignition"]),
		"max upgrades strengthen power, bounce, explosions and ignition")
	var pow_only := _levels(0)
	pow_only["power"] = 5
	check(float(Rules.effective(Rules.CHARACTERS[0]["stats"], pow_only)["launch_mult"]) > float(f0["launch_mult"]), "single-upgrade changes the stat it names")
	var by_name := {}
	for i in Rules.CHARACTERS.size():
		by_name[str(Rules.CHARACTERS[i]["name"])] = i
	check(Rules.CHARACTERS.size() == 18 and Rules.UPGRADE_ORDER.size() == 8, "18 characters and 8 upgrades preserved")
	var names := ["RAGNAR", "CAPTAIN OOPS", "BIG RED"]
	var prof := {}
	var all_found := true
	for nm in names:
		if not by_name.has(nm):
			all_found = false
			continue
		prof[nm] = Rules.effective(Rules.CHARACTERS[by_name[nm]]["stats"], base)
	check(all_found, "Ragnar, Captain Oops and Big Red exist")
	if all_found:
		var differ := 0
		for key in ["launch_mult", "restitution", "extra_mass", "durability", "spin_mult"]:
			var a := float(prof["RAGNAR"].get(key, 0.0))
			var b := float(prof["CAPTAIN OOPS"].get(key, 0.0))
			var c := float(prof["BIG RED"].get(key, 0.0))
			if absf(a - b) > 0.005 or absf(b - c) > 0.005:
				differ += 1
		check(differ >= 3, "stat differences matter: %d of 5 effective stats differ across Ragnar / Captain Oops / Big Red" % differ)
	for i in Rules.CHARACTERS.size():
		var tot := 0
		for sv in (Rules.CHARACTERS[i]["stats"] as Dictionary).values():
			tot += int(sv)
		if tot != Rules.STAT_TOTAL:
			check(false, "character %s spends %d stat points" % [Rules.CHARACTERS[i]["name"], tot])
	# stacking: the strongest possible combination remains governed
	var worst_stack := 0.0
	for ci in Rules.CHARACTERS.size():
		var fxs: Dictionary = Rules.effective(Rules.CHARACTERS[ci]["stats"], mx)
		var gv: float = Rules.governed_speed(Main.speed_for_power(Main.OVERDRIVE_MAX) * float(fxs["launch_mult"]), deg_to_rad(35.0), fxs)
		worst_stack = maxf(worst_stack, Rules.ideal_range(gv, deg_to_rad(35.0)))
	check(worst_stack <= 181.0, "all 18 characters at max upgrades stay inside the range cap (worst %.0f m)" % worst_stack)

	# ============================================================ RELEASE GATE: no economy test controls in player UI
	var src := FileAccess.get_file_as_string("res://scripts/main.gd")
	check(not src.contains("\"+10,000 (TEST)\"") and not src.contains("+10,000 (TEST)"), "'+10,000 (TEST)' string is gone from the game code")
	check(src.contains("dev_tools") and src.contains("RR_DEV_ECONOMY"), "the only credit grant is behind the developer gate (cmdline --dev-economy / RR_DEV_ECONOMY=1)")
	var flags := FileAccess.get_file_as_string("res://release_flags.json") if FileAccess.file_exists("res://release_flags.json") else "{}"
	var jf: Variant = JSON.parse_string(flags)
	check(jf is Dictionary and not bool((jf as Dictionary).get("dev_economy", false)), "release flags: dev economy is off")

	# ============================================================ SCENES: boundary + skips
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.skip_select = true
	root.add_child(main)
	await frames(5)
	check(not main.dev_tools, "dev tools are OFF in a normal run")
	main.dev_grant(10000)
	check(main.bank == 0 or main.bank == int(main.bank) and main.bank < 10000, "dev_grant does nothing in a normal build (bank %d)" % main.bank)
	for envid in ["downtown", "suburbia"]:
		main.start_game(0, Rules.env_index(envid))
		await frames(3)
		var xmax: float = main.town.WORLD_X_MAX
		check(main.town.boundary_bodies.size() >= 5, "%s: the world edge is built from %d tagged boundary colliders" % [envid, main.town.boundary_bodies.size()])
		var all_tagged := true
		for bb in main.town.boundary_bodies:
			if not bb.has_meta("boundary") or str(bb.get_meta("mat", "")) != "ground":
				all_tagged = false
		check(all_tagged, "%s: every perimeter collider is tagged boundary and is not a destructible material" % envid)
		main.aim_dir = Vector3(1, 0.3, 0).normalized()
		main.fire()
		await frames(3)
		var limbs0: int = main.limbs_lost
		var carn0: int = int(main.scoring.lines.get("Carnage", 0))
		var wall: Node = main.town.boundary_bodies[0]
		var part: RigidBody3D = main.ragdoll.torso
		for hit in 4:   # repeated, violent contacts with the wall (v12: this is where the player "exploded")
			main._on_impact(part, wall, 70.0, Vector3(xmax, 8.0, 0.0))
		check(main._oob_at >= 0.0, "%s: a 70 m/s hit on the boundary arms the graceful end" % envid)
		check(main.limbs_lost == limbs0 and int(main.scoring.lines.get("Carnage", 0)) == carn0 and not main.scoring.lines.has("Explosions"), "%s: the boundary never dismembers, scores carnage or explodes the player" % envid)
		var n := 0
		while main.state == 1 and n < 60 * 4:
			await physics_frame
			n += 1
		check(main.state != 1 and n < 60 * 3, "%s: the run ends cleanly within a second or two of the boundary contact (%d frames)" % [envid, n])
	main.queue_free()
	await frames(2)
	print("---- V13 %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
