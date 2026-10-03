extends SceneTree
## Headless POC checks:  godot --headless --path launch -s tests/verify.gd
var fails: int = 0

func check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		fails += 1

func _init() -> void:
	Engine.max_fps = 0
	Engine.physics_ticks_per_second = 60
	await _run()
	print("---- %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)

func frames(n: int) -> void:
	for i in n:
		await physics_frame

func _run() -> void:
	var ps: PackedScene = load("res://scenes/main.tscn")
	check(ps != null, "main scene loads")
	var main: Node = ps.instantiate()
	root.add_child(main)
	await frames(5)
	check(main.state == 0, "starts in AIM")
	check(main.town != null and main.town.band_l != null, "launcher exists")
	check(main.ragdoll.bodies.size() == 6 and main.ragdoll.joint_count == 5, "ragdoll has 6 bodies / 5 joints")
	var missing: Array = []
	for p in main.town.used_assets:
		if not ResourceLoader.exists(p):
			missing.append(p)
	check(missing.is_empty(), "no missing kit resources %s" % str(missing))
	var n_pieces: int = main.town.pieces.size()
	var n_props: int = main.town.props.size()
	check(n_pieces > 30 and main.town.frozen_count() == n_pieces, "breakables start frozen (%d)" % n_pieces)
	# scoring dedupe
	var sc := Scoring.new()
	sc.award("k", "x", 100, "A")
	sc.award("k", "x", 100, "A")
	sc.set_distance(10.0)
	sc.set_distance(5.0)
	check(sc.total() == 130, "scoring: unique keys + monotonic distance (%d)" % sc.total())
	# launch deterministic shot at the house window
	main.aim_dir = Vector3(1.0, 0.12, 0.0).normalized()
	main.aim_power = 0.7
	var start: Vector3 = main.ragdoll.centre()
	main.fire()
	check(main.state == 1, "fire enters FLIGHT")
	await frames(3)
	check(main.ragdoll.max_speed() > 10.0, "launch impulse applied (speed %.1f)" % main.ragdoll.max_speed())
	var sane: bool = true
	var maxf_: float = 0.0
	var t0: int = Time.get_ticks_msec()
	var i: int = 0
	while main.state == 1 and i < 60 * 25:
		await physics_frame
		i += 1
		if not main.ragdoll.is_finite_and_sane():
			sane = false
			print("insane at frame ", i, " ", main.ragdoll.centre())
			break
	print("sim: %d physics frames in %d ms; torso end %s" % [i, Time.get_ticks_msec() - t0, str(main.ragdoll.centre())])
	check(sane, "ragdoll stays numerically sane")
	check(main.ragdoll.centre().x > start.x + 8.0, "ragdoll travelled downrange")
	check(main.state == 2, "flight settles into RESULT")
	check(main.scoring.total() > 0, "score > 0 (%d) %s" % [main.scoring.total(), str(main.scoring.lines)])
	var released: int = n_pieces - main.town.frozen_count()
	check(released > 0, "something broke (%d pieces released)" % released)
	# reset
	main.reset()
	await frames(3)
	check(main.state == 0, "reset returns to AIM")
	check(main.town.pieces.size() == n_pieces and main.town.frozen_count() == n_pieces, "breakables restored")
	check(main.town.props.size() == n_props, "props restored")
	check(main.scoring.total() == 0, "score reset")
	check(main.ragdoll.is_finite_and_sane() and main.ragdoll.centre().distance_to(start) < 0.5, "ragdoll back at launcher")
	# repeat 3 fast cycles for stability
	for k in 3:
		main.aim_dir = Vector3(1.0, 0.8, randf_range(-0.3, 0.3)).normalized()
		main.aim_power = randf_range(0.4, 1.0)
		main.fire()
		var j: int = 0
		while main.state == 1 and j < 60 * 25:
			await physics_frame
			j += 1
		check(main.state == 2 and main.ragdoll.is_finite_and_sane(), "repeat launch %d completed (%d frames)" % [k, j])
		main.reset()
		await frames(2)
	# android export config
	var cfg := FileAccess.get_file_as_string("res://export_presets.cfg")
	check(cfg.contains('platform="Android"') and cfg.contains("architectures/arm64-v8a=true") and cfg.contains("unique_name="), "android export preset present")
