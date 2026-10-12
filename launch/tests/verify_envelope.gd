extends SceneTree
## Launch-envelope audit: every board, every breakable structure -> the lowest Launch Power level whose envelope can reach it.
## Fails if anything a player is meant to hit is out of reach even at Lv20, or if a board has no easy-to-reach content.
##   godot --headless --path launch -s tests/verify_envelope.gd
const Rules := preload("res://scripts/rules.gd")
const Destruction := preload("res://scripts/destruction.gd")
var fails := 0

func check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		fails += 1


## Every building on every board takes part in destruction: no solid static box/tower larger than a person-sized prop remains
## unless it is on the short, legitimate exceptions list (terrain, boundaries, launch infrastructure, water, springy surfaces,
## ricochet pads, trees).
const EXEMPT_MATS := ["water", "trampoline", "ground", "canvas"]
func _static_audit(main, id: String) -> void:
	var T = main.town
	var offenders: Array = []
	var total_buildings := 0
	for ch in T.get_children():
		if ch is StaticBody3D:
			if ch.has_meta("boundary") or ch.has_meta("ground") or ch.name == "Terrain" or ch.has_meta("glass") or ch.has_meta("decor"):
				continue
			var sz := Vector3.ZERO
			for c2 in ch.get_children():
				if c2 is CollisionShape3D and c2.shape is BoxShape3D:
					sz = c2.shape.size
				elif c2 is CollisionShape3D and c2.shape is CylinderShape3D:
					sz = Vector3(c2.shape.radius * 2.0, c2.shape.height, c2.shape.radius * 2.0)
			var mat: String = str(ch.get_meta("mat", "?"))
			if EXEMPT_MATS.has(mat) or ch.get_meta("pad", false):
				continue
			# building-scale = at least 5 m on one horizontal axis and 4 m tall; trees (cylinders) and metal sign/ricochet pads are exempt
			if sz.y >= 4.0 and maxf(sz.x, sz.z) >= 5.0 and not (ch.get_child(0) is CollisionShape3D and (ch.get_child(0) as CollisionShape3D).shape is CylinderShape3D):
				offenders.append("%s %s mat %s at (%.0f,%.0f)" % [ch.name, str(sz), mat, ch.global_position.x, ch.global_position.z])
	for p in T.pieces:
		if Destruction.is_shell(p):
			total_buildings += 1
	check(offenders.is_empty(), "%s: no indestructible building-scale static solids remain %s" % [id, str(offenders.slice(0, 3))])

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.skip_select = true
	main.force_rebuild = true
	root.add_child(main)
	for i in 5:
		await process_frame
	var summary: Array = []
	for en in Rules.ENVIRONMENTS:
		var id: String = str(en["id"])
		main.start_game(0, Rules.env_index(id))
		for i in 3:
			await process_frame
		_static_audit(main, id)
		var T = main.town
		var bands := [0, 0, 0, 0, 0, 0]          # Lv0-4, 5-8, 9-12, 13-16, 17-20, out of reach
		var n := 0
		var worst_x := 0.0
		var out_list: Array = []
		for p in T.pieces:
			var half := Vector3.ONE
			for ch in p.get_children():
				if ch is CollisionShape3D and (ch as CollisionShape3D).shape is BoxShape3D:
					half = ((ch as CollisionShape3D).shape as BoxShape3D).size * 0.5
			var top: float = p.global_position.y + half.y
			var near_x: float = p.global_position.x - half.x
			# a piece is "reachable" when some approach to its nearest face and its top clears the envelope
			var lvl: int = Rules.min_level_to_reach(maxf(near_x, 10.0), top * 0.55)       # hit anywhere on the lower 55% of the height
			var b: int = 5 if lvl > Rules.MAYHEM_MAX else mini(lvl / 5 if lvl > 0 else 0, 4)
			if lvl >= 17 and lvl <= 20:
				b = 4
			elif lvl >= 13:
				b = 3
			elif lvl >= 9:
				b = 2
			elif lvl >= 5:
				b = 1
			else:
				b = 0
			if lvl > Rules.MAYHEM_MAX:
				b = 5
				if out_list.size() < 4:
					out_list.append("%s@x%.0f,y%.0f" % [p.name, near_x, top])
			bands[b] += 1
			n += 1
			worst_x = maxf(worst_x, p.global_position.x)
		print("      %-13s pieces %4d  by min level Lv0-4:%4d  5-8:%4d  9-12:%4d  13-16:%4d  17-20:%4d  unreachable:%3d  deepest x %.0f  %s" % [id, n, bands[0], bands[1], bands[2], bands[3], bands[4], bands[5], worst_x, str(out_list)])
		summary.append({"id": id, "n": n, "bands": bands, "deepest": worst_x})
		check(float(bands[5]) / float(maxi(n, 1)) < 0.03, "%s: at most 3%% of structures are beyond the Lv20 envelope (%d of %d)" % [id, bands[5], n])
		check(bands[0] + bands[1] >= int(0.15 * n) or id == "yard", "%s: a real share of the board is hittable early (Lv0-8: %d of %d)" % [id, bands[0] + bands[1], n])
		check(bands[3] + bands[4] >= 3, "%s: deep / tall content that only high levels reach exists (%d pieces at Lv13+)" % [id, bands[3] + bands[4]])
		check(worst_x > 200.0, "%s: structures extend past 200 m (deepest %.0f)" % [id, worst_x])
	print("---- ENVELOPE %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
