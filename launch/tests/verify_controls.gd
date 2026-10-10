extends SceneTree
## Desktop controls: every action has defaults, bindings are remappable (keyboard/mouse and gamepad), saved and reloaded, reflected in
## the InputMap, drive the real game (virtual aim, fire, retry), and the controller prompts follow the detected device.
##   godot --headless --path launch -s tests/verify_controls.gd
const Controls := preload("res://scripts/controls.gd")
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

func _key(code: int, pressed: bool = true) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code as Key
	e.keycode = code as Key
	e.pressed = pressed
	return e

func _run() -> void:
	DirAccess.remove_absolute("user://controls.cfg")
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.skip_select = true
	root.add_child(main)
	await frames(5)
	var c: Node = main.controls
	check(c != null, "controls layer exists")
	for a in c.actions:
		var id: String = str(a["id"])
		check(InputMap.has_action(id), "action registered: %s" % id)
		check((a["kbm"] as Array).size() == 2 and (a["pad"] as Array).size() == 2, "%s has 2 keyboard + 2 gamepad slots" % id)
	for id in ["fire", "aim_up", "aim_down", "aim_left", "aim_right", "spin_left", "spin_right", "retry", "pause", "launcher_next", "launcher_prev"]:
		var a: Dictionary = c.entry(id)
		check(a["kbm"][0] != null, "%s has a default key" % id)
		check(a["pad"][0] != null or a["pad"][1] != null, "%s has a default pad binding" % id)
	# remap
	var ev := _key(KEY_F)
	check(not InputMap.action_has_event("retry", ev), "F is not retry by default")
	c.rebind("retry", "kbm", 0, c.spec_of(ev))
	check(InputMap.action_has_event("retry", ev), "retry rebound to F in the InputMap")
	check(not InputMap.action_has_event("retry", _key(KEY_R)), "old key R no longer retries")
	# conflict inside a group: bind retry to Q (launcher_prev) -> launcher_prev loses it
	c.rebind("retry", "kbm", 1, c.spec_of(_key(KEY_Q)))
	check(c.entry("launcher_prev")["kbm"][0] == null, "binding Q to retry unbinds it from launcher_prev (same group)")
	# pad rebinding
	var jb := InputEventJoypadButton.new()
	jb.button_index = JOY_BUTTON_B
	jb.pressed = true
	jb.device = -1
	c.rebind("fire", "pad", 0, c.spec_of(jb))
	check(InputMap.action_has_event("fire", jb), "fire rebound to gamepad B")
	check(c.label_of(c.spec_of(jb)) != "", "gamepad button has a readable label (%s)" % c.label_of(c.spec_of(jb)))
	# stick direction bind
	var jm := InputEventJoypadMotion.new()
	jm.axis = JOY_AXIS_RIGHT_X
	jm.axis_value = 1.0
	c.rebind("aim_right", "pad", 0, c.spec_of(jm))
	check(c.entry("aim_right")["pad"][0] != null and "Right" in c.label_of(c.entry("aim_right")["pad"][0]), "stick axis binding labelled (%s)" % c.label_of(c.entry("aim_right")["pad"][0]))
	# clear
	c.clear("fire", "pad", 1)
	check(c.entry("fire")["pad"][1] == null, "slot can be cleared")
	# settings
	c.set_setting("pad_sensitivity", 1.7)
	c.set_setting("invert_y", true)
	# save -> reload into a fresh instance
	c.save_config()
	var c2: Node = Controls.new()
	root.add_child(c2)
	c2.load_config()
	check(c2.entry("retry")["kbm"][0] != null and c2.label_of(c2.entry("retry")["kbm"][0]) == c.label_of(c.entry("retry")["kbm"][0]), "bindings survive save/load")
	check(c2.entry("fire")["pad"][1] == null and c2.entry("fire")["pad"][0] != null, "cleared and rebound pad slots survive save/load")
	check(is_equal_approx(float(c2.settings["pad_sensitivity"]), 1.7) and bool(c2.settings["invert_y"]), "sensitivity / invert persist")
	c2.queue_free()
	# reset
	c.reset_defaults()
	check(InputMap.action_has_event("retry", _key(KEY_R)) and not InputMap.action_has_event("retry", _key(KEY_F)), "reset to defaults restores the keys")
	# listening captures the next input
	c.begin_listen("retry", "kbm", 0)
	check(c.is_listening(), "listening state on")
	c.cancel_listen()
	check(not c.is_listening(), "listening cancelled")
	# gameplay: virtual aim with the keyboard raises power, fire launches
	await frames(3)
	main.select_launcher("slingshot")
	main.reset()
	await frames(5)
	check(main.state == main.State.AIM, "in AIM")
	Input.action_press("aim_down", 1.0)
	await frames(30)
	Input.action_release("aim_down")
	check(main.aim_power > 0.5, "holding aim_down pulls back (power %.2f)" % main.aim_power)
	var p0: float = main.aim_power
	Input.action_press("aim_down", 1.0)
	await frames(60)
	Input.action_release("aim_down")
	check(main.aim_power > p0, "more pull with more time (%.2f -> %.2f)" % [p0, main.aim_power])
	var fe := InputEventAction.new()
	fe.action = "fire"
	fe.pressed = true
	Input.parse_input_event(fe)
	await frames(10)
	check(main.state == main.State.FLIGHT, "fire action launches (state %d)" % main.state)
	await frames(30)
	Input.action_press("spin_right", 1.0)
	await frames(3)
	check(main.air_input > 0.5, "spin_right drives air control (%.2f)" % main.air_input)
	Input.action_release("spin_right")
	# the controls panel opens with pause and lists every action
	main.state = main.State.AIM
	var pe := InputEventAction.new()
	pe.action = "pause"
	pe.pressed = true
	Input.parse_input_event(pe)
	await frames(3)
	check(main.controls_panel.visible, "pause opens the controls panel")
	check(main.controls_panel._slot_btns.size() == c.actions.size() * 4, "panel has a button for every slot (%d)" % main.controls_panel._slot_btns.size())
	main.controls_panel.close()
	check(not main.controls_panel.visible, "panel closes")
	# prompts follow the device
	c.last_device = "pad"
	check(c.prompt("fire") != "", "pad prompt: %s" % c.prompt("fire"))
	c.last_device = "kbm"
	check(c.prompt("fire") != "", "kbm prompt: %s" % c.prompt("fire"))
	DirAccess.remove_absolute("user://controls.cfg")
	print("---- CONTROLS %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
