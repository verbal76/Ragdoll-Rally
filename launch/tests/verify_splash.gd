extends SceneTree
## Hot Attic Games studio-splash tests (standing studio requirement).
##   godot --headless --path launch -s tests/verify_splash.gd

const CANONICAL_NAME := "Hot_Attic_Games_Master_Logo_ALPHA_FINAL.png"
const CANONICAL_SHA256 := "e3d9bb5653eafb783eede827606e7ac73a4e45564a1c25b1ed13ad1429f48c4e"
var fails := 0
var B: GDScript

func check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		fails += 1

func _init() -> void:
	_run.call_deferred()

func _free_game() -> void:
	if current_scene and is_instance_valid(current_scene):
		current_scene.queue_free()
	current_scene = null

## Runs a boot scene; returns {stages, t_ms (ready -> game_starting), alpha samples, node}.
func _boot_run(setup: Callable, sample_times: Array = []) -> Dictionary:
	var b: Control = (load("res://scenes/boot.tscn") as PackedScene).instantiate()
	setup.call(b)
	var log: Array = []
	var t0: int = Time.get_ticks_msec()
	b.stage.connect(func(n: String): log.append([n, Time.get_ticks_msec() - t0]))
	root.add_child(b)
	current_scene = b
	var samples: Dictionary = {}
	var started_at: float = -1.0
	var limit: int = Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < limit:
		await process_frame
		var el: float = float(Time.get_ticks_msec() - t0) / 1000.0
		if is_instance_valid(b) and b.logo_node:
			for st in sample_times:
				if not samples.has(st) and el >= float(st):
					samples[st] = b.logo_node.modulate.a
		var names: Array = log.map(func(e): return e[0])
		if names.has("game_starting") or names.has("game_failed"):
			break
	await process_frame
	await process_frame
	var names2: Array = log.map(func(e): return e[0])
	var t_start := -1
	var t_go := -1
	for e in log:
		if e[0] == "splash_visible" or e[0] == "splash_skipped":
			t_start = e[1]
		if e[0] == "game_starting":
			t_go = e[1]
	return {"log": log, "names": names2, "t_ms": t_go, "t_card_ms": t_go - t_start if t_go >= 0 and t_start >= 0 else -1, "samples": samples, "boot": b if is_instance_valid(b) else null}

func _run() -> void:
	B = load("res://scripts/boot.gd")
	var LOGO: String = B.LOGO
	# ---------------------------------------------------------------- the asset
	check(LOGO.get_file() == CANONICAL_NAME, "boot uses the canonical filename (%s)" % LOGO.get_file())
	check(not LOGO.ends_with("Hot_Attic_Games_Master_Logo.png"), "the obsolete logo path is not referenced")
	check(ResourceLoader.exists(LOGO), "canonical artwork resolves (%s)" % LOGO)
	check(not FileAccess.file_exists("res://branding/Hot_Attic_Games_Master_Logo.png"), "the obsolete duplicate logo file is gone")
	check(FileAccess.get_sha256(LOGO) == CANONICAL_SHA256, "the shipped file is byte-identical to the owner-supplied canonical PNG (SHA-256 pinned)")
	var img := Image.load_from_file(LOGO)
	check(img != null and img.get_size() == Vector2i(1536, 1024), "artwork is 1536 x 1024")
	check(img != null and img.detect_alpha() != Image.ALPHA_NONE, "artwork has an alpha channel")
	check(img.get_pixel(0, 0).a == 0.0 and img.get_pixel(1535, 1023).a == 0.0 and img.get_pixel(768, 512).a == 1.0, "corners are transparent, the artwork itself is opaque")
	# ---------------------------------------------------------------- fit (aspect + no crop) on many screens
	var tex_sz := Vector2(1536, 1024)
	var fit_ok := true
	var fills := true
	for sz in [Vector2(2400, 1080), Vector2(1080, 2400), Vector2(1280, 720), Vector2(720, 1280), Vector2(1000, 1000), Vector2(3000, 800), Vector2(300, 200)]:
		var r: Rect2 = B.fit_rect(sz, tex_sz)
		var inside: bool = r.position.x >= -0.01 and r.position.y >= -0.01 and r.end.x <= sz.x + 0.01 and r.end.y <= sz.y + 0.01
		var aspect_ok: bool = absf(r.size.x / r.size.y - tex_sz.x / tex_sz.y) < 0.001
		if not (inside and aspect_ok):
			fit_ok = false
		if not (is_equal_approx(r.size.x, sz.x) or is_equal_approx(r.size.y, sz.y)):
			fills = false
	check(fit_ok, "complete artwork fits every screen shape inside bounds with the original aspect ratio (no crop, no stretch)")
	check(fills, "it is scaled as large as possible (touches the limiting edge)")
	# ---------------------------------------------------------------- cold launch: order, timing, transparency
	var res: Dictionary = await _boot_run(func(_b): pass, [0.1, 1.0, 2.25])
	check(res.names == ["boot_started", "splash_visible", "splash_done", "game_starting"], "cold-launch order: boot -> studio card -> game (%s)" % ", ".join(res.names))
	var card_s: float = float(res.t_card_ms) / 1000.0
	check(card_s >= 2.0 and card_s <= 3.0, "studio card is on screen for 2-3 s (%.2f s)" % card_s)
	check(res.samples.get(0.1, 1.0) < 0.9 and res.samples.get(1.0, 0.0) > 0.98 and res.samples.get(2.25, 1.0) < 0.9, "fade in -> full -> fade out (alpha %.2f / %.2f / %.2f)" % [res.samples.get(0.1, -1.0), res.samples.get(1.0, -1.0), res.samples.get(2.25, -1.0)])
	# the card as built: exact artwork, aspect-preserving, whole, inside the screen
	var b2: Control = (load("res://scenes/boot.tscn") as PackedScene).instantiate()
	root.add_child(b2)
	await process_frame
	var ln: TextureRect = b2.logo_node
	check(ln != null and ln.texture.resource_path == LOGO, "the card displays the canonical artwork")
	check(ln.texture.get_size() == tex_sz and ln.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED and ln.expand_mode == TextureRect.EXPAND_IGNORE_SIZE, "aspect-preserving 'contain' layout, no stretch")
	var vp: Rect2 = b2.get_viewport_rect()
	var gr: Rect2 = ln.get_global_rect()
	check(vp.encloses(gr), "the card sits inside the (safe) viewport")
	var drawn: Rect2 = B.fit_rect(ln.size, tex_sz)
	check(absf(drawn.size.x / drawn.size.y - 1.5) < 0.001 and drawn.size.x <= ln.size.x + 0.01 and drawn.size.y <= ln.size.y + 0.01, "the drawn artwork keeps 3:2 and is not cropped")
	check(b2._bg.color == B.BG_COLOR and ProjectSettings.get_setting("application/boot_splash/bg_color") == B.BG_COLOR, "native splash colour == studio card background (no flash)")
	check(not ProjectSettings.get_setting("application/boot_splash/show_image", true), "no second native splash image (no duplicate splash)")
	b2.queue_free()
	await process_frame
	# ---------------------------------------------------------------- the game follows; initialisation intact
	await create_timer(0.3).timeout
	var game: Node = current_scene
	check(game != null and game.scene_file_path == "res://scenes/main.tscn", "navigation continues into the game scene after the card")
	check(game.get("select_ui") != null and game.select_ui.visible and int(game.state) == game.State.SELECT, "the game's own opening (selector) follows the studio card")
	check(get_root().get_node_or_null("Ota") != null and game.get("sfx") != null and game.get("town") == null, "autoloads + game systems initialised (OTA client present, selector waiting)")
	# ---------------------------------------------------------------- resume / background never replays the card
	var before: int = res.names.size()
	for n in [Node.NOTIFICATION_APPLICATION_PAUSED, Node.NOTIFICATION_APPLICATION_RESUMED, Node.NOTIFICATION_APPLICATION_FOCUS_OUT, Node.NOTIFICATION_APPLICATION_FOCUS_IN, Node.NOTIFICATION_WM_WINDOW_FOCUS_IN]:
		root.propagate_notification(n)
	await create_timer(0.3).timeout
	var boots := 0
	for c in root.find_children("*", "Control", true, false):
		if c.get_script() == B:
			boots += 1
	check(boots == 0 and current_scene == game and res.names.size() == before, "background/resume does not re-enter the studio card")
	_free_game()
	await process_frame
	# ---------------------------------------------------------------- failures cannot strand the user
	var miss: Dictionary = await _boot_run(func(bb): bb.logo_path = "res://branding/does_not_exist.png")
	check(miss.names.has("splash_skipped") and miss.names.has("game_starting") and miss.t_ms < 1500, "missing artwork: card is skipped and the game starts at once (%d ms)" % miss.t_ms)
	_free_game()
	await process_frame
	var sync_run: Dictionary = await _boot_run(func(bb): bb.force_sync_load = true; bb.hold_seconds = 0.2)
	check(sync_run.names.has("game_starting") and current_scene != null and current_scene.scene_file_path == "res://scenes/main.tscn", "threaded preload unavailable: falls back to a direct load and still starts")
	_free_game()
	await process_frame
	var bad: Dictionary = await _boot_run(func(bb): bb.game_scene = "res://scenes/nope.tscn"; bb.hold_seconds = 0.1)
	var bad_b: Control = bad.boot
	var has_msg: bool = false
	if is_instance_valid(bad_b):
		for c in bad_b.get_children():
			if c is Label:
				has_msg = true
	check(bad.names.has("game_failed") and has_msg and is_instance_valid(bad_b), "a broken game scene shows a clear message instead of a stuck/blank splash")
	if is_instance_valid(bad_b):
		bad_b.queue_free()
	await process_frame
	print("---- SPLASH %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
