extends SceneTree
## MOCKUP (xvfb): comic-book menus drawn with Godot UI primitives on top of the inked Downtown scene. Not wired into the game.
const Rules := preload("res://scripts/rules.gd")
var ui: CanvasLayer
const INK := Color(0.02, 0.02, 0.07)
const CYAN := Color(0.62, 0.93, 1.0)
const PINK := Color(1.0, 0.18, 0.42)
const YEL := Color(1.0, 0.9, 0.2)
const LIME := Color(0.7, 1.0, 0.3)
const PURP := Color(0.62, 0.45, 1.0)

func poly(pts: PackedVector2Array, fill: Color, width: float = 6.0, ink: Color = INK, shadow: Vector2 = Vector2(10, 10), shadow_col: Color = Color(0.2, 0.75, 1.0)) -> Node2D:
	var root := Node2D.new()
	if shadow != Vector2.ZERO:
		var sh := Polygon2D.new()
		var sp := PackedVector2Array()
		for p in pts:
			sp.append(p + shadow)
		sh.polygon = sp
		sh.color = shadow_col
		root.add_child(sh)
		var shl := Line2D.new()
		shl.points = sp
		shl.closed = true
		shl.width = width
		shl.default_color = ink
		root.add_child(shl)
	var f := Polygon2D.new()
	f.polygon = pts
	f.color = fill
	root.add_child(f)
	var l := Line2D.new()
	l.points = pts
	l.closed = true
	l.width = width
	l.default_color = ink
	l.joint_mode = Line2D.LINE_JOINT_SHARP
	root.add_child(l)
	return root

func text(s: String, pos: Vector2, size: int, col: Color, rot: float = 0.0, outline: int = 14, outcol: Color = INK) -> Label:
	var l := Label.new()
	l.text = s
	l.position = pos
	l.rotation = rot
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", outcol)
	l.add_theme_constant_override("outline_size", outline)
	if outline > 0:
		l.add_theme_color_override("font_shadow_color", Color(0.2, 0.75, 1.0))
		l.add_theme_constant_override("shadow_offset_x", 6)
		l.add_theme_constant_override("shadow_offset_y", 6)
	ui.add_child(l)
	return l

func rect_skew(x: float, y: float, w: float, h: float, skew: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x + skew, y), Vector2(x + w + skew, y), Vector2(x + w, y + h), Vector2(x, y + h)])

func halftone(rect: Rect2, col: Color, falloff: float) -> void:
	var cr := ColorRect.new()
	cr.position = rect.position
	cr.size = rect.size
	var m := ShaderMaterial.new()
	m.shader = load("res://tests/_toon/halftone.gdshader")
	m.set_shader_parameter("dot_col", col)
	m.set_shader_parameter("falloff_y", falloff)
	cr.material = m
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(cr)

func rank_badge(c: Vector2, letter: String, col: Color, r: float = 70.0) -> void:
	var pts := PackedVector2Array()
	for i in 16:
		var a: float = float(i) / 16.0 * TAU
		var rr: float = r * (1.0 if i % 2 == 0 else 0.72)
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	ui.add_child(poly(pts, col, 6.0, INK, Vector2(6, 6)))
	var hex := PackedVector2Array()
	for i in 6:
		var a2: float = float(i) / 6.0 * TAU + 0.3
		hex.append(c + Vector2(cos(a2), sin(a2)) * r * 0.55)
	ui.add_child(poly(hex, Color(0.1, 0.3, 0.2) if col == LIME else Color(0.15, 0.15, 0.4), 5.0, INK, Vector2.ZERO))
	text(letter, c - Vector2(24, 40), 72, CYAN, 0.0, 10)

func clear_ui() -> void:
	for ch in ui.get_children():
		ch.queue_free()

func shot(name: String, out: String) -> void:
	for i in 4:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("RENDER ", name)

func _r():
	var out := "/tmp/claude-0/s/mock"
	DirAccess.make_dir_recursive_absolute(out)
	var main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.skip_select = true
	root.add_child(main)
	for i in 5: await process_frame
	main.start_game(0, Rules.env_index("downtown"))
	for i in 6: await process_frame
	main.set_process(false)
	main.ui.visible = false
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(2, 2)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://tests/_toon/ink_post.gdshader")
	qm.material = mat
	q.mesh = qm
	q.extra_cull_margin = 16384.0
	main.cam.add_child(q)
	main.cam.global_position = Vector3(20, 45, -60)
	main.cam.look_at(Vector3(110, 12, 0), Vector3.UP)
	main.cam.far = 900.0
	ui = CanvasLayer.new()
	ui.layer = 50
	root.add_child(ui)
	# ---------------- A: RESULT SCREEN
	var veil := ColorRect.new()
	veil.color = Color(1.0, 0.82, 0.55, 0.88)
	veil.size = Vector2(1280, 720)
	ui.add_child(veil)
	halftone(Rect2(0, 360, 1280, 360), Color(0.9, 0.45, 0.2, 0.35), 1.0)
	ui.add_child(poly(PackedVector2Array([Vector2(-30, 120), Vector2(520, 20), Vector2(560, 110), Vector2(-30, 230)]), Color(0.98, 0.55, 0.45), 0.0, INK, Vector2.ZERO))
	ui.add_child(poly(PackedVector2Array([Vector2(-10, 150), Vector2(560, 40), Vector2(570, 150), Vector2(-10, 260)]), Color(0.1, 0.1, 0.1, 0.0), 8.0, INK, Vector2(8, 8)))
	text("LEVEL", Vector2(20, 80), 96, CYAN, -0.2)
	text("COMPLETE!", Vector2(100, 140), 90, CYAN, -0.2)
	text("THAT'S TOTALLY RADICAL!", Vector2(600, 80), 46, CYAN, -0.03)
	text("PUNCHES PUNCHED: 317", Vector2(520, 170), 36, CYAN, -0.02, 10)
	text("BUILDINGS DOWN: 9   CRATERS: 3", Vector2(520, 220), 28, YEL, -0.02, 10)
	rank_badge(Vector2(1180, 230), "B", LIME, 62.0)
	text("x1", Vector2(1100, 300), 56, YEL, -0.25, 12)
	ui.add_child(poly(PackedVector2Array([Vector2(700, 330), Vector2(1100, 360), Vector2(1080, 520), Vector2(1180, 560), Vector2(1250, 640), Vector2(1130, 650), Vector2(1000, 560), Vector2(690, 590)]), PINK, 8.0))
	text("NEXT", Vector2(780, 380), 70, CYAN, 0.0)
	text("LEVEL", Vector2(780, 460), 70, CYAN, 0.0)
	ui.add_child(poly(rect_skew(70, 520, 400, 70, 20), PURP, 5.0, INK, Vector2(6, 6)))
	text("Restart", Vector2(200, 530), 44, INK, 0.0, 0)
	ui.add_child(poly(rect_skew(70, 610, 400, 70, 20), PURP, 5.0, INK, Vector2(6, 6)))
	text("Main Menu", Vector2(170, 620), 44, INK, 0.0, 0)
	await shot("A_result_screen", out)
	# ---------------- B: LAUNCHER PANEL
	clear_ui()
	var v2 := ColorRect.new()
	v2.color = Color(0.03, 0.04, 0.2, 0.82)
	v2.size = Vector2(1280, 720)
	ui.add_child(v2)
	halftone(Rect2(0, 0, 1280, 720), Color(0.3, 0.6, 1.0, 0.2), 1.0)
	ui.add_child(poly(rect_skew(40, 24, 780, 86, 40), YEL, 8.0))
	text("LAUNCHERS", Vector2(120, 22), 74, INK, 0.0, 0)
	text("Credits 18,450", Vector2(900, 40), 44, CYAN, 0.0, 10)
	var names := ["SLINGSHOT", "CATAPULT", "CANNON", "ARTILLERY", "RAILGUN"]
	var tags := ["MEDIUM RANGE CHAOS", "DEEP-MAP HIGH ARCS", "DIRECT FIRE", "INDIRECT PRECISION", "ENDGAME PENETRATION"]
	var cols := [LIME, Color(1.0, 0.75, 0.3), PINK, PURP, Color(0.3, 0.9, 1.0)]
	var lvls := [5, 3, 1, 0, 0]
	for i in 5:
		var y: float = 140.0 + float(i) * 110.0
		ui.add_child(poly(rect_skew(40, y, 880, 96, 26), Color(0.95, 0.97, 1.0) if lvls[i] > 0 else Color(0.55, 0.6, 0.75), 6.0))
		ui.add_child(poly(rect_skew(40, y, 190, 96, 26), cols[i], 6.0, INK, Vector2.ZERO))
		text(names[i], Vector2(74, y + 26), 26, INK, 0.0, 0)
		text(tags[i], Vector2(270, y + 8), 24, Color(0.1, 0.1, 0.3), 0.0, 0)
		for k in 5:
			var pip := poly(rect_skew(280 + k * 44, y + 52, 36, 26, 8), cols[i] if k < lvls[i] else Color(0.8, 0.82, 0.9), 4.0, INK, Vector2.ZERO)
			ui.add_child(pip)
		var lab: String = ("IN USE" if i == 0 else "USE") if lvls[i] > 0 else "LOCKED"
		var cost: String = ["MAX", "UPGRADE 6,500", "UPGRADE 3,200", "UNLOCK 12,000", "UNLOCK 25,000"][i]
		ui.add_child(poly(rect_skew(950, y, 270, 96, 26), PINK if i in [3, 4] else Color(0.3, 0.95, 0.5), 6.0))
		text(cost, Vector2(985, y + 28), 30, INK, 0.0, 0)
	rank_badge(Vector2(1210, 80), "20", YEL, 48)
	await shot("B_launcher_panel", out)
	# ---------------- C: IN-FLIGHT HUD
	clear_ui()
	text("x15", Vector2(1040, 300), 110, YEL, -0.15, 16)
	text("+ BUILDING DOWN!", Vector2(760, 470), 38, CYAN, -0.05, 10)
	text("+ WENT THROUGH!", Vector2(790, 520), 38, CYAN, -0.05, 10)
	text("+ CRATER!!", Vector2(870, 570), 38, CYAN, -0.05, 10)
	rank_badge(Vector2(1150, 110), "S", PINK)
	ui.add_child(poly(PackedVector2Array([Vector2(30, 600), Vector2(500, 590), Vector2(480, 640), Vector2(20, 650)]), Color(0.1, 0.1, 0.25), 7.0))
	ui.add_child(poly(PackedVector2Array([Vector2(40, 604), Vector2(380, 598), Vector2(364, 636), Vector2(30, 642)]), LIME, 0.0, INK, Vector2.ZERO))
	text("RAGNAR", Vector2(40, 540), 44, CYAN, -0.03, 12)
	text("SLOW-MO", Vector2(560, 60), 54, CYAN, 0.0, 14)
	text("DISTANCE 284 m", Vector2(30, 40), 40, YEL, 0.0, 10)
	text("CHARGING 87%", Vector2(470, 300), 52, PINK, 0.0, 14)
	ui.add_child(poly(rect_skew(380, 380, 520, 36, 16), Color(0.1, 0.1, 0.25), 6.0))
	ui.add_child(poly(rect_skew(384, 384, 440, 28, 14), Color(0.3, 0.9, 1.0), 0.0, INK, Vector2.ZERO))
	await shot("C_flight_hud", out)
	quit()
func _init():
	_r.call_deferred()
