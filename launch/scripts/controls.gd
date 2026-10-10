extends Node
## Input layer: every control is a remappable action with up to two keyboard/mouse bindings and two gamepad bindings, stored in
## user://controls.cfg. Gamepads are detected automatically (connect/disconnect at any time); the game follows whichever device was
## used last, so on-screen prompts show the right keys or buttons. Touch (Android) is unaffected: emulated mouse events always aim.
## Actions are registered in Godot's InputMap at runtime (project.godot is untouched).
## Use with:  const Controls := preload("res://scripts/controls.gd")      (main.gd creates one node)

signal binding_changed
signal device_changed(kind: String)                  # "kbm" or "pad": the device the player used last
signal pad_connected(pad_name: String, connected: bool)
signal listen_finished(ok: bool)

const CFG_PATH := "user://controls.cfg"
const SLOTS := 2

## id, label, group (conflicts are only checked inside a group), kbm defaults, pad defaults
## binding spec: {"t": "key"|"mouse"|"jbtn"|"jaxis", "c": code, "s": sign (axes)}
static func K(code: int) -> Dictionary:
	return {"t": "key", "c": code}
static func M(btn: int) -> Dictionary:
	return {"t": "mouse", "c": btn}
static func B(btn: int) -> Dictionary:
	return {"t": "jbtn", "c": btn}
static func A(axis: int, sign: int) -> Dictionary:
	return {"t": "jaxis", "c": axis, "s": sign}

static func default_actions() -> Array:
	return [
		{"id": "aim_drag", "label": "Aim / pull back (hold, drag, release)", "group": "aim", "kbm": [M(MOUSE_BUTTON_LEFT)], "pad": []},
		{"id": "fire", "label": "Fire / charge / confirm shot", "group": "aim", "kbm": [K(KEY_SPACE), K(KEY_ENTER)], "pad": [B(JOY_BUTTON_A), A(JOY_AXIS_TRIGGER_RIGHT, 1)]},
		{"id": "aim_up", "label": "Aim up / less pull", "group": "aim", "kbm": [K(KEY_W), K(KEY_UP)], "pad": [A(JOY_AXIS_LEFT_Y, -1), B(JOY_BUTTON_DPAD_UP)]},
		{"id": "aim_down", "label": "Aim down / more pull", "group": "aim", "kbm": [K(KEY_S), K(KEY_DOWN)], "pad": [A(JOY_AXIS_LEFT_Y, 1), B(JOY_BUTTON_DPAD_DOWN)]},
		{"id": "aim_left", "label": "Aim left", "group": "aim", "kbm": [K(KEY_A), K(KEY_LEFT)], "pad": [A(JOY_AXIS_LEFT_X, -1), B(JOY_BUTTON_DPAD_LEFT)]},
		{"id": "aim_right", "label": "Aim right", "group": "aim", "kbm": [K(KEY_D), K(KEY_RIGHT)], "pad": [A(JOY_AXIS_LEFT_X, 1), B(JOY_BUTTON_DPAD_RIGHT)]},
		{"id": "precision", "label": "Fine aim (hold)", "group": "aim", "kbm": [K(KEY_SHIFT)], "pad": [A(JOY_AXIS_TRIGGER_LEFT, 1)]},
		{"id": "spin_left", "label": "Spin / flip left (in flight)", "group": "flight", "kbm": [K(KEY_A), K(KEY_LEFT)], "pad": [B(JOY_BUTTON_LEFT_SHOULDER), A(JOY_AXIS_LEFT_X, -1)]},
		{"id": "spin_right", "label": "Spin / flip right (in flight)", "group": "flight", "kbm": [K(KEY_D), K(KEY_RIGHT)], "pad": [B(JOY_BUTTON_RIGHT_SHOULDER), A(JOY_AXIS_LEFT_X, 1)]},
		{"id": "retry", "label": "Retry", "group": "global", "kbm": [K(KEY_R)], "pad": [B(JOY_BUTTON_Y)]},
		{"id": "launcher_prev", "label": "Previous launcher", "group": "global", "kbm": [K(KEY_Q)], "pad": [B(JOY_BUTTON_LEFT_SHOULDER)]},
		{"id": "launcher_next", "label": "Next launcher", "group": "global", "kbm": [K(KEY_E)], "pad": [B(JOY_BUTTON_RIGHT_SHOULDER)]},
		{"id": "open_launchers", "label": "Launcher shop", "group": "global", "kbm": [K(KEY_L)], "pad": [B(JOY_BUTTON_X)]},
		{"id": "open_upgrades", "label": "Upgrades", "group": "global", "kbm": [K(KEY_U)], "pad": [B(JOY_BUTTON_BACK)]},
		{"id": "toggle_ink", "label": "Comic-ink look on/off", "group": "global", "kbm": [K(KEY_F2)], "pad": []},
		{"id": "fullscreen", "label": "Fullscreen on/off", "group": "global", "kbm": [K(KEY_F11)], "pad": []},
		{"id": "pause", "label": "Menu / controls", "group": "global", "kbm": [K(KEY_ESCAPE)], "pad": [B(JOY_BUTTON_START)]},
	]

var actions: Array = []                  # [{id, label, group, kbm: [spec|null x2], pad: [spec|null x2]}]
var settings := {"pad_deadzone": 0.25, "pad_sensitivity": 1.0, "mouse_sensitivity": 1.0, "invert_y": false}
var last_device: String = "kbm"
var pad_name: String = ""
var _listening: Dictionary = {}          # {action, device, slot} while waiting for the next input

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_config()
	Input.joy_connection_changed.connect(_on_joy_changed)
	var pads: PackedInt32Array = Input.get_connected_joypads()
	if pads.size() > 0:
		pad_name = Input.get_joy_name(pads[0])

# ------------------------------------------------------------------------------------------------ specs <-> events
static func event_of(spec: Variant) -> InputEvent:
	if spec == null or not (spec is Dictionary):
		return null
	var s: Dictionary = spec
	match str(s.get("t", "")):
		"key":
			var e := InputEventKey.new()
			e.physical_keycode = int(s["c"]) as Key
			e.device = -1
			return e
		"mouse":
			var m := InputEventMouseButton.new()
			m.button_index = int(s["c"]) as MouseButton
			m.device = -1
			return m
		"jbtn":
			var b := InputEventJoypadButton.new()
			b.button_index = int(s["c"]) as JoyButton
			b.device = -1
			return b
		"jaxis":
			var a := InputEventJoypadMotion.new()
			a.axis = int(s["c"]) as JoyAxis
			a.axis_value = float(int(s.get("s", 1)))
			a.device = -1
			return a
	return null

## The binding an incoming event represents (null if it is not bindable: key release, tiny stick motion, ...).
static func spec_of(ev: InputEvent) -> Variant:
	if ev is InputEventKey and (ev as InputEventKey).pressed and not (ev as InputEventKey).echo:
		var k := ev as InputEventKey
		var code: int = int(k.physical_keycode) if int(k.physical_keycode) != 0 else int(k.keycode)
		return K(code)
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
		return M(int((ev as InputEventMouseButton).button_index))
	if ev is InputEventJoypadButton and (ev as InputEventJoypadButton).pressed:
		return B(int((ev as InputEventJoypadButton).button_index))
	if ev is InputEventJoypadMotion and absf((ev as InputEventJoypadMotion).axis_value) > 0.65:
		var j := ev as InputEventJoypadMotion
		return A(int(j.axis), 1 if j.axis_value > 0.0 else -1)
	return null

static func same(a: Variant, b: Variant) -> bool:
	if a == null or b == null:
		return false
	return str((a as Dictionary).get("t")) == str((b as Dictionary).get("t")) and int((a as Dictionary).get("c", -1)) == int((b as Dictionary).get("c", -2)) \
		and int((a as Dictionary).get("s", 0)) == int((b as Dictionary).get("s", 0))

func pad_kind() -> String:
	var n: String = pad_name.to_lower()
	if n.contains("playstation") or n.contains("ps4") or n.contains("ps5") or n.contains("dualsense") or n.contains("dualshock") or n.contains("sony"):
		return "ps"
	if n.contains("nintendo") or n.contains("switch") or n.contains("joy-con"):
		return "nintendo"
	return "xbox"

func label_of(spec: Variant) -> String:
	if spec == null or not (spec is Dictionary):
		return "-"
	var s: Dictionary = spec
	var c: int = int(s.get("c", 0))
	match str(s.get("t", "")):
		"key":
			return OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(c as Key)) if DisplayServer.get_name() != "headless" else str(c)
		"mouse":
			return {MOUSE_BUTTON_LEFT: "Mouse Left", MOUSE_BUTTON_RIGHT: "Mouse Right", MOUSE_BUTTON_MIDDLE: "Mouse Middle", MOUSE_BUTTON_XBUTTON1: "Mouse 4", MOUSE_BUTTON_XBUTTON2: "Mouse 5", MOUSE_BUTTON_WHEEL_UP: "Wheel Up", MOUSE_BUTTON_WHEEL_DOWN: "Wheel Down"}.get(c, "Mouse %d" % c)
		"jbtn":
			var ps: bool = pad_kind() == "ps"
			var names_x: Array = ["A", "B", "X", "Y", "Back", "Guide", "Start", "L-Stick", "R-Stick", "LB", "RB", "D-Pad Up", "D-Pad Down", "D-Pad Left", "D-Pad Right"]
			var names_p: Array = ["Cross", "Circle", "Square", "Triangle", "Share", "PS", "Options", "L3", "R3", "L1", "R1", "D-Pad Up", "D-Pad Down", "D-Pad Left", "D-Pad Right"]
			var arr: Array = names_p if ps else names_x
			return str(arr[c]) if c >= 0 and c < arr.size() else "Pad %d" % c
		"jaxis":
			var sg: int = int(s.get("s", 1))
			var ps2: bool = pad_kind() == "ps"
			match c:
				JOY_AXIS_LEFT_X:
					return "L-Stick Right" if sg > 0 else "L-Stick Left"
				JOY_AXIS_LEFT_Y:
					return "L-Stick Down" if sg > 0 else "L-Stick Up"
				JOY_AXIS_RIGHT_X:
					return "R-Stick Right" if sg > 0 else "R-Stick Left"
				JOY_AXIS_RIGHT_Y:
					return "R-Stick Down" if sg > 0 else "R-Stick Up"
				JOY_AXIS_TRIGGER_LEFT:
					return "L2" if ps2 else "LT"
				JOY_AXIS_TRIGGER_RIGHT:
					return "R2" if ps2 else "RT"
			return "Axis %d%s" % [c, "+" if sg > 0 else "-"]
	return "-"

# ------------------------------------------------------------------------------------------------ registry
func _fresh() -> Array:
	var out: Array = []
	for a in default_actions():
		var e := {"id": a["id"], "label": a["label"], "group": a["group"], "kbm": [], "pad": []}
		for d in ["kbm", "pad"]:
			for i in SLOTS:
				(e[d] as Array).append((a[d] as Array)[i] if i < (a[d] as Array).size() else null)
		out.append(e)
	return out

func entry(id: String) -> Dictionary:
	for a in actions:
		if str(a["id"]) == id:
			return a
	return {}

func reset_defaults() -> void:
	actions = _fresh()
	settings = {"pad_deadzone": 0.25, "pad_sensitivity": 1.0, "mouse_sensitivity": 1.0, "invert_y": false}
	apply_to_inputmap()
	save_config()
	binding_changed.emit()

## Registers every action (with its current bindings) in Godot's InputMap.
func apply_to_inputmap() -> void:
	for a in actions:
		var id: String = str(a["id"])
		if InputMap.has_action(id):
			InputMap.erase_action(id)
		InputMap.add_action(id, float(settings["pad_deadzone"]))
		for d in ["kbm", "pad"]:
			for sp in (a[d] as Array):
				var ev: InputEvent = event_of(sp)
				if ev != null:
					InputMap.action_add_event(id, ev)

func load_config() -> void:
	actions = _fresh()
	var cf := ConfigFile.new()
	if cf.load(CFG_PATH) == OK:
		for a in actions:
			for d in ["kbm", "pad"]:
				for i in SLOTS:
					var key: String = "%s_%s_%d" % [a["id"], d, i]
					if cf.has_section_key("bindings", key):
						var v = cf.get_value("bindings", key)
						(a[d] as Array)[i] = v if (v is Dictionary and (v as Dictionary).has("t")) else null
		for k in settings.keys():
			settings[k] = cf.get_value("settings", k, settings[k])
	apply_to_inputmap()

func save_config() -> void:
	var cf := ConfigFile.new()
	for a in actions:
		for d in ["kbm", "pad"]:
			for i in SLOTS:
				var v = (a[d] as Array)[i]
				cf.set_value("bindings", "%s_%s_%d" % [a["id"], d, i], v if v != null else 0)
	for k in settings.keys():
		cf.set_value("settings", k, settings[k])
	cf.save(CFG_PATH)

func set_setting(key: String, value: Variant) -> void:
	settings[key] = value
	if key == "pad_deadzone":
		apply_to_inputmap()
	save_config()

## Bind `spec` to action slot. The same input is removed from other actions of the same group (no double bindings inside a context).
func rebind(id: String, device: String, slot: int, spec: Variant) -> void:
	var a: Dictionary = entry(id)
	if a.is_empty() or slot < 0 or slot >= SLOTS:
		return
	if spec != null:
		for o in actions:
			if str(o["group"]) != str(a["group"]):
				continue
			for i in SLOTS:
				if same((o[device] as Array)[i], spec) and not (str(o["id"]) == id and i == slot):
					(o[device] as Array)[i] = null
	(a[device] as Array)[slot] = spec
	apply_to_inputmap()
	save_config()
	binding_changed.emit()

func clear(id: String, device: String, slot: int) -> void:
	rebind(id, device, slot, null)

# ------------------------------------------------------------------------------------------------ listening (rebind UI)
func begin_listen(id: String, device: String, slot: int) -> void:
	_listening = {"action": id, "device": device, "slot": slot}

func cancel_listen() -> void:
	if not _listening.is_empty():
		_listening = {}
		listen_finished.emit(false)

func is_listening() -> bool:
	return not _listening.is_empty()

func listening_for() -> Dictionary:
	return _listening

func _input(event: InputEvent) -> void:
	# which device is the player using right now (drives the prompts)
	if event is InputEventKey or (event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION):
		_set_device("kbm")
	elif event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5):
		_set_device("pad")
	if _listening.is_empty():
		return
	if event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).physical_keycode == KEY_ESCAPE and str(_listening["device"]) == "kbm":
		get_viewport().set_input_as_handled()
		cancel_listen()
		return
	var spec: Variant = spec_of(event)
	if spec == null:
		return
	var dev: String = "kbm" if (spec as Dictionary)["t"] in ["key", "mouse"] else "pad"
	if dev != str(_listening["device"]):
		return                                    # keyboard slots take keys/mouse, pad slots take buttons/sticks
	get_viewport().set_input_as_handled()
	rebind(str(_listening["action"]), dev, int(_listening["slot"]), spec)
	_listening = {}
	listen_finished.emit(true)

func _set_device(kind: String) -> void:
	if kind != last_device:
		last_device = kind
		device_changed.emit(kind)

func _on_joy_changed(device: int, connected: bool) -> void:
	if connected:
		pad_name = Input.get_joy_name(device)
	else:
		var pads: PackedInt32Array = Input.get_connected_joypads()
		pad_name = Input.get_joy_name(pads[0]) if pads.size() > 0 else ""
		if pads.size() == 0 and last_device == "pad":
			_set_device("kbm")
	pad_connected.emit(Input.get_joy_name(device) if connected else "Controller", connected)

# ------------------------------------------------------------------------------------------------ queries
func has_pad() -> bool:
	return Input.get_connected_joypads().size() > 0

## "SPACE / A" style prompt for the active device: the first bound input of an action.
func prompt(id: String) -> String:
	var a: Dictionary = entry(id)
	if a.is_empty():
		return id
	var dev: String = "pad" if (last_device == "pad" and has_pad()) else "kbm"
	for sp in (a[dev] as Array):
		if sp != null:
			return label_of(sp)
	for sp in (a["kbm" if dev == "pad" else "pad"] as Array):
		if sp != null:
			return label_of(sp)
	return "(unbound)"

## 2D aim vector from the aim actions (x right, y down), deadzone and sensitivity applied. `fine` slows it while the precision action is held.
func aim_vector() -> Vector2:
	var v: Vector2 = Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down", float(settings["pad_deadzone"]))
	if bool(settings["invert_y"]):
		v.y = -v.y
	v *= float(settings["pad_sensitivity"])
	if Input.is_action_pressed("precision"):
		v *= 0.3
	return v
