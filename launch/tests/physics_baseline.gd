extends SceneTree
## Deterministic physics fingerprint for engine-migration comparison.
##   godot --headless --path launch -s tests/physics_baseline.gd -- out.json
## Dumps (1) every registered physics/* project setting and (2) metrics for a fixed
## set of seeded shots. Run on the old and new engine and diff.
const SHOTS := [
	{"dir": Vector3(1.0, 0.12, 0.0), "power": 0.7},    # flat into the house
	{"dir": Vector3(1.0, 0.5, 0.0), "power": 0.6},     # medium arc
	{"dir": Vector3(1.0, 0.9, 0.0), "power": 1.0},     # max power high lob
	{"dir": Vector3(1.0, 0.3, -0.35), "power": 0.8},   # left
	{"dir": Vector3(1.0, 0.3, 0.35), "power": 0.8},    # right
	{"dir": Vector3(1.0, 0.15, 0.1), "power": 0.45},   # short and low
]

func _init() -> void:
	Engine.max_fps = 0
	var out_path: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://physics_baseline.json"
	var result := {"engine": Engine.get_version_info().get("string", "?"), "settings": {}, "shots": []}
	for p in ProjectSettings.get_property_list():
		var n: String = p["name"]
		if n.begins_with("physics/"):
			result["settings"][n] = str(ProjectSettings.get_setting(n))
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.skip_select = true
	main.env_idx = 1                 # the b9 city map (these tests are about it)
	root.add_child(main)
	main.classic = true          # G1/G2 speeds/materials/no skid so the 4.4.1 comparison stays meaningful
	main.legacy_world = true     # original small village: comparable with the 4.4.1 reference
	main.force_rebuild = OS.get_cmdline_user_args().size() > 1 and OS.get_cmdline_user_args()[1] == "rebuild"
	for i in 4:
		await physics_frame
	result["launch_consts"] = {"MIN_SPEED": main.CLASSIC_MIN_SPEED, "MAX_SPEED": main.CLASSIC_MAX_SPEED, "gravity": ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)}
	var idx := 0
	for s in SHOTS:
		seed(1000 + idx)
		main.reset()
		await physics_frame
		await physics_frame
		main.aim_dir = (s["dir"] as Vector3).normalized()
		main.aim_power = s["power"]
		main.fire()
		var frames := 0
		var max_speed := 0.0
		var max_stretch := 0.0
		var sane := true
		while main.state == 1 and frames < 60 * 25:
			await physics_frame
			frames += 1
			max_speed = maxf(max_speed, main.ragdoll.max_speed())
			for b in main.ragdoll.bodies:
				max_stretch = maxf(max_stretch, b.global_position.distance_to(main.ragdoll.torso.global_position))
			if not main.ragdoll.is_finite_and_sane():
				sane = false
				break
		var c: Vector3 = main.ragdoll.centre()
		var limbs := {}
		for b in main.ragdoll.bodies:
			limbs[b.name] = _r(b.global_position - c)
		result["shots"].append({
			"i": idx, "frames": frames, "sane": sane, "torso_end": _r(c), "max_speed": snappedf(max_speed, 0.01),
			"max_limb_dist": snappedf(max_stretch, 0.01), "released": main.town.pieces.size() - main.town.frozen_count(),
			"score": main.scoring.total(), "lines": main.scoring.lines.duplicate(), "limbs": limbs})
		idx += 1
	var fa := FileAccess.open(out_path, FileAccess.WRITE)
	fa.store_string(JSON.stringify(result, "  "))
	fa.close()
	print("physics baseline written: ", out_path)
	quit()

func _r(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]
