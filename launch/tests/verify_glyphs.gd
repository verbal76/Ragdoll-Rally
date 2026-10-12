extends SceneTree
## Controller glyph library: every mapped label resolves to real art in each family, unknown labels fall back to text (null).
##   godot --headless --path launch -s tests/verify_glyphs.gd
const GlyphLib := preload("res://scripts/glyph_lib.gd")
var fails := 0

func check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		fails += 1

func _init() -> void:
	for kind in ["xbox", "ps", "nintendo"]:
		var fam: String = GlyphLib.family_of(kind)
		var missing: Array = []
		for k in ["a", "b", "x", "y", "lb", "rb", "lt", "rt", "lstick", "rstick", "dpad_up", "dpad_down", "dpad_left", "dpad_right", "back"]:
			if not ResourceLoader.exists("res://assets/glyphs/%s/%s.png" % [fam, k]):
				missing.append(k)
		check(missing.is_empty(), "%s family has the core buttons (missing: %s)" % [fam, str(missing)])
	check(GlyphLib.path_for("xbox", "A").ends_with("xbox/a.png"), "Xbox/Deck A -> xbox/a")
	check(GlyphLib.path_for("ps", "Cross").ends_with("ps/a.png"), "PS Cross -> ps/a (bottom face button)")
	check(GlyphLib.path_for("nintendo", "A").ends_with("switch/a.png"), "a label printed on a Nintendo pad maps straight to that legend's art")
	check(GlyphLib.legend_key("nintendo", "a") == "b" and GlyphLib.legend_key("xbox", "a") == "a" and GlyphLib.legend_key("ps", "a") == "a", "positional bottom button = Switch B legend, Xbox A, PS Cross")
	check(GlyphLib.path_for("xbox", "LB").ends_with("xbox/lb.png") and GlyphLib.path_for("ps", "L1").ends_with("ps/lb.png"), "bumpers map across families")
	check(GlyphLib.path_for("xbox", "L-Stick Right") == "", "stick direction has no glyph -> text fallback")
	check(GlyphLib.path_for("xbox", "Start") == "", "Xbox Start has no art in the set -> text fallback")
	check(GlyphLib.path_for("ps", "Start").ends_with("ps/start.png"), "PS Options art present")
	var t: Texture2D = GlyphLib.texture_for("xbox", "A")
	check(t != null and t.get_width() == GlyphLib.SIZE, "texture built at UI size")
	check(GlyphLib.texture_for("xbox", "nonsense") == null, "unknown label returns null")
	# keyboard / mouse art
	check(GlyphLib.kbm_path({"t": "key", "c": KEY_W}).ends_with("kbm/w.png"), "W key art")
	check(GlyphLib.kbm_path({"t": "key", "c": KEY_SPACE}).ends_with("kbm/space.png") and GlyphLib.kbm_path({"t": "key", "c": KEY_ESCAPE}).ends_with("kbm/esc.png"), "Space / Esc key art")
	check(GlyphLib.kbm_path({"t": "mouse", "c": MOUSE_BUTTON_LEFT}).ends_with("kbm/mouse_left.png"), "left mouse button art")
	check(GlyphLib.kbm_path({"t": "key", "c": KEY_4}) == "" and GlyphLib.kbm_path({"t": "key", "c": KEY_F5}) == "", "keys the supplied set lacks fall back to text (nothing invented)")
	var every := true
	for k in GlyphLib.KBM_KEYS.values():
		every = every and ResourceLoader.exists("res://assets/glyphs/kbm/%s.png" % k)
	check(every, "every mapped keyboard key has art on disk")
	# prompts per input family
	var P: Node = load("res://scripts/controls.gd").new()
	P.pad_override = true
	P.reset_defaults()
	P.last_device = "pad"
	P.pad_name = "Xbox Controller"
	check(P.prompt_bb("fire").contains("glyphs/xbox/a.png"), "Xbox/Deck: fire shows the A button art")
	check(P.glyph_bb("lstick").contains("glyphs/xbox/lstick.png"), "left stick art")
	P.pad_name = "PS5 Controller"
	check(P.prompt_bb("fire").contains("glyphs/ps/a.png") and P.label_of({"t": "jbtn", "c": 0}) == "Cross", "PlayStation: fire shows the Cross art, text says Cross")
	P.pad_name = "Nintendo Switch Pro Controller"
	check(P.glyph_bb("a").contains("glyphs/switch/b.png") and P.label_of({"t": "jbtn", "c": 0}) == "B", "Nintendo: bottom button is the B legend (art and text agree)")
	check(P.label_of({"t": "jaxis", "c": JOY_AXIS_TRIGGER_RIGHT, "s": 1}) == "ZR", "Nintendo trigger is ZR")
	P.last_device = "kbm"
	check(P.prompt_bb("fire").contains("glyphs/kbm/space.png"), "keyboard: fire shows the Space key art")
	check(P.prompt_bb("aim_up").contains("kbm/w.png"), "keyboard: aim up shows W")
	P.last_device = "pad"
	P.pad_name = "Xbox Controller"
	var ex: String = P.expand_prompts("AIM: {lstick}    FIRE: {fire} [x]")
	check(ex.contains("lstick.png") and ex.contains("xbox/a.png") and ex.contains("[lb]x]"), "hint templates expand tokens and escape BBCode")
	check(P.expand_prompts("{dpad} choose {select} select {b} back").contains("xbox/dpad.png"), "controller legend expands")
	P.settings["pad_style"] = "nintendo"
	check(P.expand_prompts("{b} back").contains("switch/a.png") and P.glyph_bb("b").contains("switch/a.png"), "manual Nintendo style: positional right button shows the A legend")
	P.settings["pad_style"] = "auto"
	# mixed input: the prompts must not flicker between devices
	P.clock_ms = 10000
	P.last_device = "pad"
	P._last_switch_ms = 10000
	var kev := InputEventKey.new()
	kev.pressed = true
	kev.physical_keycode = KEY_W
	P.clock_ms = 10100
	P._input(kev)
	check(P.last_device == "pad", "mixed input: a key press 100 ms after a prompt switch does not flip the prompts")
	P.clock_ms = 10700
	P._input(kev)
	check(P.last_device == "kbm", "after the hold time the keyboard takes over")
	var jev := InputEventJoypadButton.new()
	jev.pressed = true
	P.clock_ms = 10800
	P._input(jev)
	check(P.last_device == "kbm", "and the controller cannot flip it straight back")
	P.clock_ms = 11400
	P._input(jev)
	check(P.last_device == "pad", "controller wins again after the hold time")
	P.free()
	# manual prompt style override (detection unreliable): forced style wins, "auto" restores detection
	var C: Node = load("res://scripts/controls.gd").new()
	C.pad_name = "Xbox Controller"
	check(C.pad_kind() == "xbox", "auto: Xbox pad detected as xbox")
	C.settings["pad_style"] = "ps"
	check(C.pad_kind() == "ps" and C.label_of({"t": "jbtn", "c": 0}) == "Cross", "forced PlayStation style relabels A as Cross")
	C.settings["pad_style"] = "auto"
	check(C.pad_kind() == "xbox", "auto restores detection")
	C.free()
	print("---- GLYPHS %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
