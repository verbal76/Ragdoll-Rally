extends RefCounted
## Controller button glyphs (owner-supplied set, see assets/glyphs/NOTICE.md). Looks a glyph up from the button label that
## Controls.label_of() produces; returns null when there is no matching art, so callers always keep the text label as fallback.
## No class_name on purpose (the OTA runtime fingerprint includes class names). Families: "xbox" (also Steam Deck / Steam Controller),
## "ps", "switch". Switch pads report positional (Xbox-layout) buttons, so A/B and X/Y art is swapped to match the printed legends.
const DIR := "res://assets/glyphs/%s/%s.png"
const SIZE := 40
static var _cache: Dictionary = {}

const LABEL_TO_KEY := {
	"A": "a", "B": "b", "X": "x", "Y": "y", "Cross": "a", "Circle": "b", "Square": "x", "Triangle": "y",
	"LB": "lb", "RB": "rb", "L1": "lb", "R1": "rb", "LT": "lt", "RT": "rt", "L2": "lt", "R2": "rt",
	"L-Stick": "l3", "R-Stick": "r3", "L3": "l3", "R3": "r3",
	"Back": "back", "Share": "back", "Start": "start", "Options": "start",
	"D-Pad Up": "dpad_up", "D-Pad Down": "dpad_down", "D-Pad Left": "dpad_left", "D-Pad Right": "dpad_right",
}
const SWITCH_SWAP := {"a": "b", "b": "a", "x": "y", "y": "x"}

static func family_of(pad_kind: String) -> String:
	return "ps" if pad_kind == "ps" else ("switch" if pad_kind == "nintendo" else "xbox")

static func key_of(label: String) -> String:
	return str(LABEL_TO_KEY.get(label, ""))

static func path_for(pad_kind: String, label: String) -> String:
	var k := key_of(label)
	if k == "":
		return ""
	var fam := family_of(pad_kind)
	if fam == "switch":
		k = str(SWITCH_SWAP.get(k, k))
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
