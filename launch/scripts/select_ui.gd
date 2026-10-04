extends Control
## Start flow: CHOOSE YOUR RAGDOLL  ->  CHOOSE YOUR CITY  ->  launch. Two pages, arrows + horizontal swipe.
## Use with:  const SelectUI := preload("res://scripts/select_ui.gd")

const Rules := preload("res://scripts/rules.gd")

signal chosen(char_idx: int, env_idx: int)

var char_idx: int = 0
var env_idx: int = 0
var page: int = 0                       # 0 = character, 1 = city
var _pages: Array[Control] = []
var _name: Label
var _kind: Label
var _desc: Label
var _pips: Dictionary = {}
var _env_name: Label
var _env_desc: Label
var _env_state: Label
var _go: Button
var _next: Button
var _viewport: SubViewport
var _model_root: Node3D
var _cam: Camera3D
var _model: Node3D
var _swipe_from: float = -1.0
var margins: Vector4 = Vector4(40, 30, 40, 30)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.08, 0.14, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_pages.append(_build_character_page())
	_pages.append(_build_city_page())
	for p in _pages:
		add_child(p)
	_show_page(0)
	_refresh()

func _label(sz: int, align: int, col: Color = Color(1, 1, 1)) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 8)
	l.horizontal_alignment = align as HorizontalAlignment
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _btn(text: String, sz: int, w: float, h: float, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", sz)
	b.custom_minimum_size = Vector2(w, h)
	b.pressed.connect(cb)
	return b

func _page_root() -> Control:
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

# ------------------------------------------------------------------ page 0: characters
func _build_character_page() -> Control:
	var root := _page_root()
	var title := _label(46, HORIZONTAL_ALIGNMENT_CENTER, Color(1.0, 0.85, 0.25))
	title.text = "RAGDOLL RALLY LAUNCH\\nCHOOSE YOUR RAGDOLL".replace("\\n", "\n")
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	title.offset_left = -500
	title.offset_right = 500
	title.offset_top = 14
	root.add_child(title)
	# preview (own 3D world so it never touches the game world)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	svc.anchor_left = 0.5
	svc.anchor_right = 0.5
	svc.anchor_top = 0.5
	svc.anchor_bottom = 0.5
	svc.offset_left = -480
	svc.offset_right = -100
	svc.offset_top = -190
	svc.offset_bottom = 190
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.size = Vector2i(380, 380)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svc.add_child(_viewport)
	_model_root = Node3D.new()
	_viewport.add_child(_model_root)
	var cam := Camera3D.new()
	cam.fov = 34.0
	_viewport.add_child(cam)
	_cam = cam
	cam.look_at_from_position(Vector3(0, 0, 6.0), Vector3.ZERO, Vector3.UP)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, 25, 0)
	_viewport.add_child(light)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.72, 0.8)
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	_viewport.add_child(we)
	root.add_child(svc)
	var left := _btn("<", 80, 120, 200, func(): _step_char(-1))
	left.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	left.offset_left = 60
	left.offset_right = 180
	left.offset_top = -100
	left.offset_bottom = 100
	root.add_child(left)
	var right := _btn(">", 80, 120, 200, func(): _step_char(1))
	right.anchor_left = 0.5
	right.anchor_right = 0.5
	right.anchor_top = 0.5
	right.anchor_bottom = 0.5
	right.offset_left = -80
	right.offset_right = 40
	right.offset_top = -100
	right.offset_bottom = 100
	root.add_child(right)
	# info column
	var info := VBoxContainer.new()
	info.anchor_left = 0.5
	info.anchor_right = 1.0
	info.anchor_top = 0.5
	info.anchor_bottom = 0.5
	info.offset_left = 80
	info.offset_right = -50
	info.offset_top = -200
	info.offset_bottom = 200
	info.add_theme_constant_override("separation", 6)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name = _label(54, HORIZONTAL_ALIGNMENT_LEFT)
	info.add_child(_name)
	_kind = _label(26, HORIZONTAL_ALIGNMENT_LEFT, Color(0.6, 0.85, 1.0))
	info.add_child(_kind)
	for st in Rules.STATS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var nm := _label(28, HORIZONTAL_ALIGNMENT_LEFT, Color(1.0, 0.95, 0.8))
		nm.text = str(st).to_upper()
		nm.custom_minimum_size = Vector2(230, 0)
		row.add_child(nm)
		var boxes: Array[ColorRect] = []
		for i in Rules.MAX_STAT:
			var cr := ColorRect.new()
			cr.custom_minimum_size = Vector2(40, 24)
			cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(cr)
			boxes.append(cr)
		_pips[st] = boxes
		info.add_child(row)
	_desc = _label(26, HORIZONTAL_ALIGNMENT_LEFT, Color(0.9, 0.9, 0.95))
	_desc.custom_minimum_size = Vector2(0, 70)
	info.add_child(_desc)
	root.add_child(info)
	_next = _btn("NEXT", 48, 280, 90, func(): _show_page(1))
	_next.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_next.offset_left = -450
	_next.offset_right = -170
	_next.offset_top = -120
	_next.offset_bottom = -30
	root.add_child(_next)
	return root

# ------------------------------------------------------------------ page 1: cities
func _build_city_page() -> Control:
	var root := _page_root()
	var title := _label(46, HORIZONTAL_ALIGNMENT_CENTER, Color(1.0, 0.85, 0.25))
	title.text = "CHOOSE YOUR CITY"
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	title.offset_left = -500
	title.offset_right = 500
	title.offset_top = 24
	root.add_child(title)
	var left := _btn("<", 80, 120, 200, func(): _step_env(-1))
	left.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	left.offset_left = 60
	left.offset_right = 180
	left.offset_top = -100
	left.offset_bottom = 100
	root.add_child(left)
	var right := _btn(">", 80, 120, 200, func(): _step_env(1))
	right.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	right.offset_left = -180
	right.offset_right = -60
	right.offset_top = -100
	right.offset_bottom = 100
	root.add_child(right)
	var mid := VBoxContainer.new()
	mid.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	mid.offset_left = -380
	mid.offset_right = 380
	mid.offset_top = -150
	mid.offset_bottom = 150
	mid.add_theme_constant_override("separation", 14)
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_env_name = _label(58, HORIZONTAL_ALIGNMENT_CENTER)
	mid.add_child(_env_name)
	_env_desc = _label(30, HORIZONTAL_ALIGNMENT_CENTER, Color(0.9, 0.9, 0.95))
	_env_desc.custom_minimum_size = Vector2(0, 120)
	mid.add_child(_env_desc)
	_env_state = _label(28, HORIZONTAL_ALIGNMENT_CENTER, Color(1.0, 0.6, 0.3))
	mid.add_child(_env_state)
	root.add_child(mid)
	_go = _btn("LAUNCH", 56, 340, 100, _on_go)
	_go.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_go.offset_left = -510
	_go.offset_right = -170
	_go.offset_top = -130
	_go.offset_bottom = -30
	root.add_child(_go)
	var back := _btn("BACK", 40, 220, 80, func(): _show_page(0))
	back.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	back.offset_left = 50
	back.offset_right = 270
	back.offset_top = -120
	back.offset_bottom = -40
	root.add_child(back)
	return root

# ------------------------------------------------------------------ logic
func _show_page(p: int) -> void:
	page = p
	for i in _pages.size():
		_pages[i].visible = (i == p)
	_refresh()

func _step_char(d: int) -> void:
	char_idx = posmod(char_idx + d, Rules.CHARACTERS.size())
	_refresh()

func _step_env(d: int) -> void:
	env_idx = posmod(env_idx + d, Rules.ENVIRONMENTS.size())
	_refresh()

func _on_go() -> void:
	if bool(Rules.ENVIRONMENTS[env_idx]["playable"]):
		chosen.emit(char_idx, env_idx)

func _refresh() -> void:
	if _name == null:
		return
	var c: Dictionary = Rules.CHARACTERS[char_idx]
	_name.text = str(c["name"])
	_kind.text = str(c["kind"])
	_desc.text = "\"%s\"" % str(c["desc"])
	for st in Rules.STATS:
		var v: int = int((c["stats"] as Dictionary)[st])
		var boxes: Array = _pips[st]
		for i in boxes.size():
			(boxes[i] as ColorRect).color = Color(1.0, 0.78, 0.2) if i < v else Color(0.22, 0.25, 0.32)
	var e: Dictionary = Rules.ENVIRONMENTS[env_idx]
	_env_name.text = str(e["name"]) + (("   [%s]" % str(e["tag"])) if str(e.get("tag", "")) != "" else "")
	_env_desc.text = str(e["desc"])
	var ok: bool = bool(e["playable"])
	_env_state.text = "" if ok else "LOCKED - not built yet"
	_go.disabled = not ok
	if page == 0:
		_load_model(str(c["letter"]))

func _load_model(letter: String) -> void:
	if _model:
		_model.queue_free()
		_model = null
	var path := "res://assets/kenney/blocky-characters/character-%s.glb" % letter
	if ResourceLoader.exists(path):
		_model = (load(path) as PackedScene).instantiate() as Node3D
		_model_root.add_child(_model)
		_model.rotation_degrees = Vector3(0, 25, 0)
		# frame the whole body regardless of the model's size
		var box := AABB()
		var first := true
		for mi in _model.find_children("*", "MeshInstance3D", true, false):
			var bb: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
			box = bb if first else box.merge(bb)
			first = false
		if not first and _cam:
			var h: float = maxf(box.size.y, 0.5)
			var dist: float = h * 0.62 / tan(deg_to_rad(_cam.fov * 0.5)) + box.size.z
			_model.position = Vector3(-box.get_center().x, -box.get_center().y, -box.get_center().z)
			_cam.look_at_from_position(Vector3(0, 0, dist * 1.12), Vector3.ZERO, Vector3.UP)

func _process(dt: float) -> void:
	if _model and is_instance_valid(_model) and visible and page == 0:
		_model.rotate_y(dt * 1.1)

## Horizontal swipe changes the selection on whichever page is showing.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_swipe_from = event.position.x
		elif _swipe_from >= 0.0:
			var dx: float = event.position.x - _swipe_from
			_swipe_from = -1.0
			if absf(dx) > 120.0:
				if page == 0:
					_step_char(-1 if dx > 0.0 else 1)
				else:
					_step_env(-1 if dx > 0.0 else 1)

func relayout(m: Vector4) -> void:
	margins = m
