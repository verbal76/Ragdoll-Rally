extends Control
## Graphics options screen (desktop). Every row is one button that cycles its choices (works with mouse, keyboard and controller).
## Use with:  const GraphicsPanel := preload("res://scripts/graphics_panel.gd")

signal closed

var g: Node
var _info: Label
var _rows := {}
var _first: Control

func setup(gfx: Node) -> void:
	g = gfx
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.06, 1.0)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var pc := PanelContainer.new()
	pc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pc.offset_left = 40
	pc.offset_right = -40
	pc.offset_top = 28
	pc.offset_bottom = -28
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.09, 0.15, 1.0)
	sb.set_corner_radius_all(20)
	sb.set_content_margin_all(18)
	pc.add_theme_stylebox_override("panel", sb)
	add_child(pc)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pc.add_child(sc)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 8)
	sc.add_child(vb)
	var t := _label("GRAPHICS", 38)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	_info = _label("", 20)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_info)
	_row(vb, "preset", "Quality preset", func(): return str(g.s["preset"]).to_upper() if g.s["preset"] != "auto" else "AUTO (%s)" % g.recommend().to_upper(),
		func(): g.choose_preset(_next((["auto", "deck", "low", "medium", "high", "ultra"] if bool(g.info.get("deck", false)) else ["auto", "low", "medium", "high", "ultra"]), str(g.s["preset"]) if g.s["preset"] != "custom" else "auto")))
	_row(vb, "mode", "Display mode", func(): return {"fullscreen": "Fullscreen (borderless)", "exclusive": "Fullscreen (exclusive)", "windowed": "Windowed"}[str(g.s["mode"])],
		func(): g.set_opt("mode", _next((["fullscreen", "windowed"] if bool(g.info.get("deck", false)) else g.MODES), str(g.s["mode"]))))
	_row(vb, "res", "Window size (windowed)", func(): return "As is" if (g.s["res"] as Vector2i).x == 0 else "%dx%d" % [(g.s["res"] as Vector2i).x, (g.s["res"] as Vector2i).y],
		func(): g.set_opt("res", _next(g.resolution_options(), g.s["res"])))
	_row(vb, "scale", "Render resolution", func(): return "%d%%" % int(round(float(g.s["scale"]) * 100.0)),
		func(): g.set_opt("scale", _next([0.5, 0.67, 0.75, 0.85, 1.0], _near([0.5, 0.67, 0.75, 0.85, 1.0], float(g.s["scale"])))))
	_row(vb, "ink", "Comic-ink quality", func(): return {"full": "Full", "lite": "Lite (faster)", "off": "Off"}[str(g.s.get("ink", "full"))],
		func(): g.set_opt("ink", _next(["full", "lite", "off"], str(g.s.get("ink", "full")))))
	_row(vb, "msaa", "Anti-aliasing", func(): return "Off" if int(g.s["msaa"]) == 0 else "MSAA %dx" % int(g.s["msaa"]),
		func(): g.set_opt("msaa", _next([0, 2, 4], int(g.s["msaa"]))))
	_row(vb, "shadows", "Shadows", func(): return "On" if bool(g.s["shadows"]) else "Off", func(): g.set_opt("shadows", not bool(g.s["shadows"])))
	_row(vb, "vsync", "V-Sync", func(): return "On" if bool(g.s["vsync"]) else "Off", func(): g.set_opt("vsync", not bool(g.s["vsync"])))
	_row(vb, "fps", "Frame rate limit", func(): return "Unlimited" if int(g.s["fps"]) == 0 else "%d fps" % int(g.s["fps"]),
		func(): g.set_opt("fps", _next(g.FPS_CAPS, int(g.s["fps"]))))
	var hint := _label("Press a row to change it. Auto picks the settings that suit your screen and graphics chip.", 18)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(0.75, 0.8, 0.9)
	vb.add_child(hint)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	vb.add_child(row)
	var det := Button.new()
	det.text = "Re-detect"
	det.custom_minimum_size = Vector2(220, 52)
	det.pressed.connect(func():
		g.info = g.detect()
		g.choose_preset("auto")
		refresh())
	row.add_child(det)
	var cl := Button.new()
	cl.text = "Close"
	cl.custom_minimum_size = Vector2(220, 52)
	cl.pressed.connect(close)
	row.add_child(cl)
	g.changed.connect(refresh)
	visible = false

func _label(txt: String, sz: int) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", sz)
	return l

func _row(parent: Node, key: String, title: String, getter: Callable, act: Callable) -> void:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 54)
	b.add_theme_font_size_override("font_size", 24)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func():
		act.call()
		refresh())
	parent.add_child(b)
	_rows[key] = {"btn": b, "title": title, "get": getter}
	if _first == null:
		_first = b

static func _next(list: Array, cur: Variant) -> Variant:
	var i: int = list.find(cur)
	return list[(i + 1) % list.size()]

static func _near(list: Array, v: float) -> float:
	var best: float = list[0]
	for x in list:
		if absf(float(x) - v) < absf(best - v):
			best = x
	return best

func refresh() -> void:
	if g == null:
		return
	_info.text = ("First start: we picked these settings for your machine. Change anything you like.\n" if g.first_run else "") + g.describe()
	for k in _rows.keys():
		var r: Dictionary = _rows[k]
		(r["btn"] as Button).text = "%s:   %s" % [r["title"], (r["get"] as Callable).call()]

func open() -> void:
	refresh()
	visible = true
	if _first and (Input.get_connected_joypads().size() > 0):
		_first.grab_focus()

func close() -> void:
	g.first_run = false
	visible = false
	closed.emit()
