extends SceneTree
## Cars and pedestrians: placed on open ground in every playable town, cars are explosive props, pedestrians flee the projectile
## and die when it reaches them, and a reset brings everyone back.
##   godot --headless --path launch -s tests/verify_traffic.gd
const Rules := preload("res://scripts/rules.gd")
var fails := 0
func check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		fails += 1
func _init() -> void:
	_run.call_deferred()
func frames(n: int) -> void:
	for i in n:
		await physics_frame
func _run() -> void:
	var main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.skip_select = true
	root.add_child(main)
	await frames(5)
	for e in Rules.ENVIRONMENTS:
		if not bool(e["playable"]):
			continue
		main.start_game(0, Rules.env_index(str(e["id"])))
		await frames(12)
		var T = main.traffic
		check(T.cars.size() >= 5 and T.peds.size() >= 10, "%s: %d cars, %d pedestrians placed" % [e["id"], T.cars.size(), T.peds.size()])
		var c = T.cars[0]["body"] if T.cars.size() > 0 else null
		if c != null:
			check(c.get_meta("explosive", false) and float(c.get_meta("blast_r", 0.0)) > 3.0, "%s: cars are explosive" % e["id"])
	# behaviour on the last board
	var T = main.traffic
	var ped: Dictionary = T.peds[0]
	var root3: Node3D = ped["root"]
	var fake := RigidBody3D.new()
	fake.gravity_scale = 0.0
	main.add_child(fake)
	fake.global_position = root3.global_position + Vector3(-22.0, 1.0, 0.0)
	T.ragdoll_fn = func(): return fake
	# freezing zeroes velocity reads: use a script-side velocity by making it non-frozen but massless drift
	fake.linear_velocity = Vector3(30.0, 0.0, 0.0)
	var start: Vector3 = root3.global_position
	await frames(30)
	var moved: float = (root3.global_position - start).length()
	check(String(ped["state"]) == "flee" or ped["state"] == "dead", "a pedestrian notices the projectile (state %s)" % ped["state"])
	check(moved > 2.0 or ped["state"] == "dead", "and runs (moved %.1f m)" % moved)
	# kill
	var killed := [0]
	T.ped_killed.connect(func(_p, _d, _n): killed[0] += 1)
	var ped2: Dictionary = T.peds[1]
	fake.global_position = (ped2["root"] as Node3D).global_position + Vector3(0.5, 1.0, 0.0)
	fake.linear_velocity = Vector3(25.0, 0.0, 0.0)
	await frames(3)
	check(ped2["state"] == "dead" and killed[0] >= 1, "the projectile kills a pedestrian it reaches (killed %d)" % killed[0])
	# blast kills those in range
	var ped3: Dictionary = T.peds[2]
	T.blast((ped3["root"] as Node3D).global_position + Vector3(2, 0, 0), 6.0)
	check(ped3["state"] == "dead", "an explosion kills pedestrians in its radius")
	# cars swerve away from the projectile's path
	var car: RigidBody3D = T.cars[0]["body"]
	var cstart: Vector3 = car.global_position
	fake.global_position = cstart + Vector3(-26.0, 1.0, 0.0)
	fake.linear_velocity = Vector3(30.0, 0.0, 0.0)
	await frames(40)
	var cmoved: float = Vector2(car.global_position.x - cstart.x, car.global_position.z - cstart.z).length()
	check(cmoved > 2.0 or not car.visible, "a car in the projectile's path drives away (moved %.1f m)" % cmoved)
	# reset
	T.reset()
	check(T.peds.all(func(p): return p["state"] != "dead"), "reset brings everyone back")
	print("---- TRAFFIC %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
