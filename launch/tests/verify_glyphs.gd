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
	check(GlyphLib.path_for("nintendo", "A").ends_with("switch/b.png"), "Switch positional A (bottom) shows the Switch B legend")
	check(GlyphLib.path_for("xbox", "LB").ends_with("xbox/lb.png") and GlyphLib.path_for("ps", "L1").ends_with("ps/lb.png"), "bumpers map across families")
	check(GlyphLib.path_for("xbox", "L-Stick Right") == "", "stick direction has no glyph -> text fallback")
	check(GlyphLib.path_for("xbox", "Start") == "", "Xbox Start has no art in the set -> text fallback")
	check(GlyphLib.path_for("ps", "Start").ends_with("ps/start.png"), "PS Options art present")
	var t: Texture2D = GlyphLib.texture_for("xbox", "A")
	check(t != null and t.get_width() == GlyphLib.SIZE, "texture built at UI size")
	check(GlyphLib.texture_for("xbox", "nonsense") == null, "unknown label returns null")
	print("---- GLYPHS %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
