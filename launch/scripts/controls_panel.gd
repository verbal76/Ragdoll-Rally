extends Control
## Controls menu: every action with its two keyboard/mouse and two gamepad bindings. Click a slot, press the new input; right-click
## (or the X button) clears it. Gamepad menu navigation works (D-pad / stick + A). Sliders for aim sensitivity, dead zone, invert Y.
## Use with:  const ControlsPanel := preload("res://scripts/controls_panel.gd")

signal closed
signal quit_requested

var controls: Node
var _grid: GridContainer
var _status: Label
var _sliders := {}
var _slot_btns := {}          # "action|device|slot" -> Button
var _fs_btn: Button
var _hdr: Array = []
var _hint: Label
var _kbm_btn: Button
var _force_kbm := false
var _first: Control

func setup(c: Node) -> void:
	controls = c
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var pc := PanelContainer.new()
	pc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)      # fills the window with a margin: never wider than the screen
	pc.offset_left = 50
	pc.offset_right = -50
	pc.offset_top = 36
	pc.offset_bottom = -36
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.12, 0.97)
	sb.set_corner_radius_all(20)
	sb.set_content_margin_all(14)
	pc.add_theme_stylebox_override("panel", sb)
	add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	pc.add_child(vb)
	var title := _label("CONTROLS", 38)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	_status = _label("", 22)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_status)
	# sliders
	var sl := HBoxContainer.new()
	sl.add_theme_constant_override("separation", 18)
	vb.add_child(sl)
	_add_slider(sl, "Stick sensitivity", "pad_sensitivity", 0.3, 2.5, 0.05)
	_add_slider(sl, "Stick dead zone", "pad_deadzone", 0.05, 0.6, 0.01)
	_add_slider(sl, "Mouse sensitivity", "mouse_sensitivity", 0.3, 3.0, 0.05)
	var inv := CheckButton.new()
	inv.text = "Invert Y"
	inv.button_pressed = bool(controls.settings["invert_y"])
	inv.toggled.connect(func(on): controls.set_setting("invert_y", on))
	sl.add_child(inv)
	# bindings
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.custom_minimum_size = Vector2(300, 200)
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	_grid = GridContainer.new()
	_grid.columns = 6
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 4)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_grid)
	for h in ["Action", "Keyboard / mouse", "Alternate", "Gamepad", "Alternate", ""]:
		var hl := _label(h, 20)
		hl.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
		_grid.add_child(hl)
		_hdr.append(hl)
	for a in controls.actions:
		var id: String = str(a["id"])
		var nl := _label(str(a["label"]), 20)
		nl.custom_minimum_size = Vector2(300, 0)
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_grid.add_child(nl)
		for d in ["kbm", "pad"]:
			for i in controls.SLOTS:
				var b := Button.new()
				b.custom_minimum_size = Vector2(130, 40)
				b.clip_text = true
				b.add_theme_font_size_override("font_size", 18)
				b.focus_mode = Control.FOCUS_ALL
				var did: String = d
				var sid: int = i
				b.pressed.connect(func(): _listen(id, did, sid))
				b.gui_input.connect(func(ev):
					if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
						controls.clear(id, did, sid))
				_grid.add_child(b)
				_slot_btns["%s|%s|%d" % [id, d, i]] = b
				if _first == null:
					_first = b
		var xb := Button.new()
		xb.text = "X"
		xb.tooltip_text = "Clear this action's bindings"
		xb.focus_mode = Control.FOCUS_ALL
		xb.pressed.connect(func():
			for dd in ["kbm", "pad"]:
				for ii in controls.SLOTS:
					controls.clear(id, dd, ii))
		_grid.add_child(xb)
	_hint = _label("", 18)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
	vb.add_child(_hint)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	vb.add_child(row)
	row.add_child(_btn("Reset to defaults", func(): controls.reset_defaults()))
	_kbm_btn = _btn("Keyboard bindings", func():
		_force_kbm = not _force_kbm
		refresh())
	row.add_child(_kbm_btn)
	_fs_btn = _btn("Fullscreen", _toggle_fullscreen)
	row.add_child(_fs_btn)
	if OS.get_name() == "Windows" or OS.get_name() == "Linux" or OS.get_name() == "macOS":
		row.add_child(_btn("Quit game", func(): quit_requested.emit()))
	row.add_child(_btn("Close", close))
	controls.binding_changed.connect(refresh)
	controls.listen_finished.connect(func(_ok): refresh())
	controls.device_changed.connect(func(_k): refresh())
	controls.pad_connected.connect(func(_n, _c): refresh())
	refresh()
	visible = false

func _label(t: String, sz: int) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	return l

func _btn(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(200, 48)
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(cb)
	return b

func _add_slider(parent: Node, text: String, key: String, lo: float, hi: float, step: float) -> void:
	var box := VBoxContainer.new()
	var l := _label(text, 18)
	box.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(controls.settings[key])
	s.custom_minimum_size = Vector2(230, 28)
	s.focus_mode = Control.FOCUS_ALL
	s.value_changed.connect(func(v): controls.set_setting(key, v))
	box.add_child(s)
	parent.add_child(box)
	_sliders[key] = s

func _listen(id: String, device: String, slot: int) -> void:
	controls.begin_listen(id, device, slot)
	refresh()

func _toggle_fullscreen() -> void:
	var m: int = DisplayServer.window_get_mode()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if m == DisplayServer.WINDOW_MODE_FULLSCREEN or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
	refresh()

func refresh() -> void:
	if controls == null:
		return
	var pads: PackedInt32Array = Input.get_connected_joypads()
	if pads.size() > 0:
		_status.text = "Controller detected: %s   (using %s)" % [controls.pad_name if controls.pad_name != "" else Input.get_joy_name(pads[0]), "gamepad" if controls.last_device == "pad" else "keyboard / mouse"]
	else:
		_status.text = "No controller detected - plug one in or pair one, it is picked up automatically.  Using keyboard / mouse."
	var pad_mode: bool = controls.last_device == "pad" and not _force_kbm
	_grid.columns = 4 if pad_mode else 6
	for i in _hdr.size():
		(_hdr[i] as Control).visible = not (pad_mode and (i == 1 or i == 2))
	for k in _slot_btns.keys():
		if str(k).contains("|kbm|"):
			(_slot_btns[k] as Control).visible = not pad_mode
	if _kbm_btn:
		_kbm_btn.text = "Show keyboard bindings" if pad_mode else ("Hide keyboard bindings" if controls.last_device == "pad" else "Keyboard bindings")
		_kbm_btn.visible = controls.last_device == "pad" or _force_kbm
	_hint.text = "Select a slot, then press a gamepad button or push a stick. Reset to defaults undoes every change." if pad_mode else "Click a slot, then press the key, mouse button, gamepad button or stick direction. Esc cancels. Right-click clears a slot."
	var lst: Dictionary = controls.listening_for()
	for a in controls.actions:
		var id: String = str(a["id"])
		for d in ["kbm", "pad"]:
			for i in controls.SLOTS:
				var b: Button = _slot_btns["%s|%s|%d" % [id, d, i]]
				if not lst.is_empty() and str(lst["action"]) == id and str(lst["device"]) == d and int(lst["slot"]) == i:
					b.text = "Press..."
				else:
					b.text = controls.label_of((a[d] as Array)[i])
	if _fs_btn:
		var m: int = DisplayServer.window_get_mode()
		_fs_btn.text = "Windowed" if (m == DisplayServer.WINDOW_MODE_FULLSCREEN or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN) else "Fullscreen"

func open() -> void:
	refresh()
	visible = true
	if _first and controls.last_device == "pad":
		_first.grab_focus()

func close() -> void:
	controls.cancel_listen()
	visible = false
	closed.emit()
