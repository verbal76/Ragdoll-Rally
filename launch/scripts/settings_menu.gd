class_name SettingsMenu
extends Control
## OTA-safe UI: gear button -> Settings -> About (release diagnostics + copy).
## Uses only the stable OtaClient surface: info, running, update_status(),
## last_status, last_check_unix, check_for_update().

var _settings: PanelContainer
var _about: PanelContainer
var _about_label: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gear := Button.new()
	gear.text = "⚙"
	gear.focus_mode = Control.FOCUS_NONE
	gear.add_theme_font_size_override("font_size", 40)
	gear.custom_minimum_size = Vector2(90, 80)
	gear.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	gear.offset_left = -106
	gear.offset_top = -96
	gear.offset_right = -16
	gear.offset_bottom = -16
	gear.pressed.connect(func(): _settings.visible = true)
	add_child(gear)
	_settings = _panel("SETTINGS", 520, 300)
	var vb: VBoxContainer = _settings.get_child(0)
	vb.add_child(_button("About", _open_about))
	vb.add_child(_button("Close", func(): _settings.visible = false))
	_about = _panel("ABOUT", 980, 640)
	var avb: VBoxContainer = _about.get_child(0)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.custom_minimum_size = Vector2(900, 420)
	_about_label = Label.new()
	_about_label.add_theme_font_size_override("font_size", 22)
	_about_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	sc.add_child(_about_label)
	avb.add_child(sc)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	row.add_child(_button("Copy Diagnostics", _copy))
	row.add_child(_button("Check for update", _check))
	row.add_child(_button("Close", func(): _about.visible = false))
	avb.add_child(row)

func _panel(title: String, w: int, h: int) -> PanelContainer:
	var p := PanelContainer.new()
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.anchor_top = 0.5
	p.anchor_bottom = 0.5
	p.offset_left = -w / 2
	p.offset_right = w / 2
	p.offset_top = -h / 2
	p.offset_bottom = h / 2
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.12, 0.92)
	sb.set_corner_radius_all(24)
	sb.set_content_margin_all(18)
	p.add_theme_stylebox_override("panel", sb)
	p.visible = false
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	var t := Label.new()
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 40)
	t.add_theme_color_override("font_color", Color(1, 1, 1))
	t.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	t.add_theme_constant_override("outline_size", 8)
	vb.add_child(t)
	p.add_child(vb)
	add_child(p)
	return p

func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(240, 80)
	b.add_theme_font_size_override("font_size", 30)
	b.pressed.connect(cb)
	return b

func _ota() -> Node:
	return get_node_or_null("/root/Ota")

func _open_about() -> void:
	_settings.visible = false
	_about.visible = true
	_about_label.text = diagnostics_text(_ota())

func _copy() -> void:
	DisplayServer.clipboard_set(diagnostics_text(_ota()))

func _check() -> void:
	var o := _ota()
	if o:
		_about_label.text = diagnostics_text(o) + "\n\n(checking for update...)"
		await o.check_for_update()
		_about_label.text = diagnostics_text(o)

## Plain-text release identity. No secrets, no save data, no personal data.
static func diagnostics_text(ota: Node) -> String:
	var info: Dictionary = ota.info if ota else BuildInfo.load_info()
	var L: Array[String] = []
	L.append("HOT ATTIC GAMES — DIAGNOSTICS")
	L.append("APPLICATION")
	L.append("  Name: %s" % str(info.get("app_name")))
	L.append("DEVICE")
	for s in BuildInfo.device_lines():
		L.append("  " + s)
	L.append("  Captured: %s" % Time.get_datetime_string_from_system(true))
	L.append("INSTALL")
	L.append("  Package: %s" % str(info.get("package_id")))
	L.append("  Version: %s" % str(info.get("version_name")))
	L.append("  Version code (native build): %s" % str(info.get("version_code")))
	L.append("  Native/runtime: Godot %s ; runtime-compat %s ; native generation %s" % [Engine.get_version_info().get("string", "?"), str(info.get("runtime_compat")), str(info.get("generation", "?"))])
	L.append("  Source commit: %s" % str(info.get("source_sha")))
	L.append("  Build: %s ; CI run %s ; built %s" % [str(info.get("build_type")), str(info.get("run_number")), str(info.get("built_at"))])
	L.append("OTA")
	L.append("  Updates enabled: %s" % ("yes" if bool(info.get("ota_enabled", false)) else "no"))
	L.append("  Channel: %s" % str(info.get("channel")))
	var run: Dictionary = ota.running if ota else {}
	if run.is_empty():
		L.append("  Running: EMBEDDED NATIVE BASELINE (no OTA applied)")
	else:
		L.append("  Running: OTA '%s' (id %s, sequence %s)" % [str(run.get("name")), str(run.get("id")), str(run.get("sequence"))])
		L.append("  OTA published: %s" % str(run.get("published_at")))
		L.append("  OTA source commit: %s" % str(run.get("source_sha")))
		L.append("  OTA SHA-256: %s" % str(run.get("sha256")))
	if ota:
		L.append("  Update status: %s" % ota.update_status())
		var lc: int = ota.last_check_unix
		L.append("  Last check: %s" % (Time.get_datetime_string_from_unix_time(lc, true) if lc > 0 else "never"))
		L.append("  Last result: %s" % ota.last_status)
	L.append("GOOGLE PLAY / ANDROID")
	L.append("  Target SDK: %s ; Min SDK: %s ; Compile SDK: %s" % [str(info.get("target_sdk")), str(info.get("min_sdk")), str(info.get("compile_sdk"))])
	L.append("  Play required target API: %s (verified %s)" % [str(info.get("play_required_target_api")), str(info.get("play_required_verified"))])
	L.append("  Play API compliant: %s" % BuildInfo.play_compliance(info))
	L.append("  Signing: %s" % str(info.get("signing")))
	return "\n".join(L)
