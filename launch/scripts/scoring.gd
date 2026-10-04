class_name Scoring
extends RefCounted
## Tiny score ledger. Every award has an optional unique key so the same
## object/event can never score twice.

signal awarded(label: String, pts: int, world_pos: Vector3)
signal claimed(key: String)

var lines: Dictionary = {}   # category -> points
var keys: Dictionary = {}    # unique keys already paid out
var smashed: int = 0
var flips: int = 0
var combo_enabled: bool = false     # pivot: chained events within a short window multiply points
var combo: int = 0
var best_combo: int = 0
var combo_t: float = -99.0
var clock: float = 0.0              # seconds since launch (set by the game each physics frame)
const Rules := preload("res://scripts/rules.gd")
const COMBO_WINDOW := 1.6
const NO_COMBO := ["Distance", "Airtime"]

func total() -> int:
	var t: int = 0
	for v in lines.values():
		t += int(v)
	return t

func award(key: String, label: String, pts: int, category: String, world_pos: Vector3 = Vector3.ZERO) -> bool:
	if key != "":
		if keys.has(key):
			return false
		keys[key] = true
	if combo_enabled and not NO_COMBO.has(category):
		if clock - combo_t > COMBO_WINDOW:
			combo = 0
		combo += 1
		combo_t = clock
		best_combo = maxi(best_combo, combo)
		pts = int(round(float(pts) * Rules.combo_mult(combo)))
	lines[category] = int(lines.get(category, 0)) + pts
	if key != "":
		claimed.emit(key)
	awarded.emit(label, pts, world_pos)
	return true

## Distance is a running maximum, not an accumulation (cannot be farmed).
func set_distance(meters: float) -> void:
	var pts: int = int(maxf(meters, 0.0) * 3.0)
	if pts > int(lines.get("Distance", 0)):
		lines["Distance"] = pts

func add_smash(piece_id: int, pts: int, pos: Vector3) -> bool:
	if award("smash_%d" % piece_id, "", pts, "Smashed", pos):
		smashed += 1
		return true
	return false

func summary_lines() -> Array[String]:
	var out: Array[String] = []
	for k in lines.keys():
		var extra: String = ""
		if k == "Smashed":
			extra = " x%d" % smashed
		elif k == "Flips":
			extra = " x%d" % flips
		out.append("%s%s  +%d" % [k, extra, int(lines[k])])
	return out
