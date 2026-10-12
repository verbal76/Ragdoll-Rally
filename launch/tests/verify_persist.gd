extends SceneTree
## The city keeps its damage between onslaughts; it is rebuilt only by RESET CITY or when it was (nearly) flattened.
## Also: sprawl adds districts, energy fatigue limits one flight, EXIT asks twice.
##   godot --headless --path launch -s tests/verify_persist.gd
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
	for id in ["downtown", "suburbia", "hill_rolling"]:
		main.start_game(0, Rules.env_index(id))
		await frames(10)
		var T = main.town
		var sp := 0
		for p in T.pieces:
			if str(p.get_meta("group", "")).begins_with("sp_"):
				sp += 1
		check(sp >= 25, "%s: sprawl added extra districts (%d pieces)" % [id, sp])
		check(T.demolished_fraction() < 0.01, "%s: a new city starts at 0%% demolished" % id)
	main.start_game(0, Rules.env_index("downtown"))
	await frames(10)
	var T = main.town
	var n := 0
	for p in T.pieces.duplicate():
		if main.Destruction.is_shell(p) and n < 80:
			T.release(p, Vector3(8, 3, 0))
			n += 1
	await frames(30)
	var f1: float = T.demolished_fraction()
	check(f1 > 0.05, "breaking buildings raises the demolished share (%.0f%%)" % (f1 * 100.0))
	main._retry()
	await frames(20)
	var f2: float = T.demolished_fraction()
	check(f2 >= f1 * 0.85, "the next onslaught starts on the damaged city (%.0f%% -> %.0f%%)" % [f1 * 100.0, f2 * 100.0])
	check(main.state == main.State.AIM, "ready to fire again")
	main.reset_city()
	await frames(10)
	check(T.demolished_fraction() < 0.01, "RESET CITY rebuilds it (%.0f%%)" % (T.demolished_fraction() * 100.0))
	# flattened city is rebuilt automatically
	main.city_wiped = true
	main._retry()
	await frames(10)
	check(not main.city_wiped, "a flattened city is rebuilt for the next onslaught")
	main._punched = 0
	var f0: float = main._punch_fatigue()
	main._punched = 120
	check(f0 == 1.0 and main._punch_fatigue() < 0.25, "one flight loses energy as it breaks more (x%.2f after 120 pieces)" % main._punch_fatigue())
	main._exit_press()
	check(main.btn_exit != null and main.btn_exit.text.begins_with("EXIT?"), "EXIT asks for a second press")
	print("---- PERSIST %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
