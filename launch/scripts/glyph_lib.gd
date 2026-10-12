extends RefCounted
## Controller button glyphs (owner-supplied set, see assets/glyphs/NOTICE.md). Looks a glyph up from the button label that
## Controls.label_of() produces; returns null when there is no matching art, so callers always keep the text label as fallback.
## Keyboard / mouse art (Dark set) lives in assets/glyphs/kbm. No class_name on purpose (the OTA runtime fingerprint includes class names). Families: "xbox" (also Steam Deck / Steam Controller),
## "ps", "switch". Switch pads report positional (Xbox-layout) buttons, so A/B and X/Y art is swapped to match the printed legends.
const DIR := "res://assets/glyphs/%s/%s.png"
const SIZE := 40
static var _cache: Dictionary = {}

const LABEL_TO_KEY := {
	"A": "a", "B": "b", "X": "x", "Y": "y", "Cross": "a", "Circle": "b", "Square": "x", "Triangle": "y",
	"LB": "lb", "RB": "rb", "L1": "lb", "R1": "rb", "LT": "lt", "RT": "rt", "L2": "lt", "R2": "rt", "L": "lb", "R": "rb", "ZL": "lt", "ZR": "rt",
	"L-Stick": "l3", "R-Stick": "r3", "L3": "l3", "R3": "r3",
	"Back": "back", "Share": "back", "Start": "start", "Options": "start", "-": "back", "+": "start",
	"D-Pad Up": "dpad_up", "D-Pad Down": "dpad_down", "D-Pad Left": "dpad_left", "D-Pad Right": "dpad_right",
}
const SWITCH_SWAP := {"a": "b", "b": "a", "x": "y", "y": "x"}      # positional (Xbox-layout) button -> the legend printed on a Nintendo pad
const IMG := 36                                                       # inline size (px) of a glyph inside a hint / toast
const KBM_KEYS := {KEY_SPACE: "space", KEY_ENTER: "enter", KEY_KP_ENTER: "enter", KEY_ESCAPE: "esc", KEY_SHIFT: "shift", KEY_CTRL: "ctrl", KEY_ALT: "alt",
	KEY_TAB: "tab", KEY_UP: "up", KEY_DOWN: "down", KEY_LEFT: "left", KEY_RIGHT: "right", KEY_PAGEUP: "pageup", KEY_PAGEDOWN: "pagedown",
	KEY_BACKSPACE: "backspace", KEY_F1: "f1", KEY_F2: "f2", KEY_F11: "f11", KEY_F12: "f12"}
const MOUSE_BTNS := {MOUSE_BUTTON_LEFT: "mouse_left", MOUSE_BUTTON_RIGHT: "mouse_right", MOUSE_BUTTON_MIDDLE: "mouse_middle"}

static func family_of(pad_kind: String) -> String:
	return "ps" if pad_kind == "ps" else ("switch" if pad_kind == "nintendo" else "xbox")

static func key_of(label: String) -> String:
	return str(LABEL_TO_KEY.get(label, ""))

static func path_for(pad_kind: String, label: String) -> String:
	var k := key_of(label)
	if k == "":
		return ""
	var fam := family_of(pad_kind)          # labels are the legends printed on that pad (Controls.label_of), so no swapping here
	var p := DIR % [fam, k]
	if ResourceLoader.exists(p):
		return p
	return ""

## Small icon texture (SIZE px) for a button, or null (no art for it: keep the text).
static func texture_for(pad_kind: String, label: String) -> Texture2D:
	var p := path_for(pad_kind, label)
	if p == "":
		return null
	if _cache.has(p):
		return _cache[p]
	var src: Texture2D = load(p) as Texture2D
	if src == null:
		return null
	var img: Image = src.get_image()
	if img == null:
		return null
	img.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
	var t := ImageTexture.create_from_image(img)
	_cache[p] = t
	return t

## The legend printed on a pad for a positional (Xbox-layout) logical key: bottom face button "a" is Switch "B", and so on.
static func legend_key(pad_kind: String, key: String) -> String:
	return str(SWITCH_SWAP.get(key, key)) if family_of(pad_kind) == "switch" else key

static func pad_path(pad_kind: String, key: String) -> String:
	var p := DIR % [family_of(pad_kind), legend_key(pad_kind, key)]
	return p if ResourceLoader.exists(p) else ""

static func kbm_path(spec: Variant) -> String:
	if not (spec is Dictionary):
		return ""
	var s: Dictionary = spec
	var c: int = int(s.get("c", 0))
	var k := ""
	match str(s.get("t", "")):
		"key":
			if c >= KEY_A and c <= KEY_Z:
				k = String.chr(c).to_lower()
			elif c >= KEY_0 and c <= KEY_9:
				k = String.chr(c)
			else:
				k = str(KBM_KEYS.get(c, ""))
		"mouse":
			k = str(MOUSE_BTNS.get(c, ""))
	if k == "":
		return ""
	var p := "res://assets/glyphs/kbm/%s.png" % k
	return p if ResourceLoader.exists(p) else ""

## BBCode for an inline glyph (RichTextLabel), or the (escaped) fallback text when there is no art.
static func bb(path: String, fallback: String) -> String:
	if path == "":
		return esc(fallback)
	return "[img=%dx%d]%s[/img]" % [IMG, IMG, path]

static func esc(t: String) -> String:
	return t.replace("[", "[lb]")
