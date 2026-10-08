extends RefCounted
## Explosive hazard structures: a gas company, a fuel depot, a tank farm. They are ordinary destruction shells with a readable look
## (red / yellow hazard colours, striped tanks, a floating HAZARD label) and a fuse: a catastrophic hit, being set on fire for a few
## seconds, a big blast nearby or a hard-flying chunk detonates them, and their blast chains into the next hazard. Town owns the
## detonation queue (so chains have delays and are bounded); this file only builds the structures.
## Use with:  const Hazards := preload("res://scripts/hazards.gd")

const KINDS := {
	"gas": {"label": "GAS CO.", "radius": 22.0, "power": 34.0, "color": Color(0.88, 0.22, 0.16), "tank": Color(0.95, 0.95, 0.9), "pts": 900, "tanks": 3},
	"fuel": {"label": "FUEL DEPOT", "radius": 18.0, "power": 30.0, "color": Color(0.95, 0.62, 0.12), "tank": Color(0.85, 0.85, 0.88), "pts": 700, "tanks": 2},
	"tanks": {"label": "TANK FARM", "radius": 26.0, "power": 38.0, "color": Color(0.7, 0.72, 0.76), "tank": Color(0.95, 0.8, 0.2), "pts": 1100, "tanks": 4},
}
const MAX_CHAIN := 12                    # detonations per run (a bounded chain, never a runaway)

## Builds one hazard structure with its ground centre at `pos` (x, ground y, z). Returns the hazard record (already added to the Town).
static func build(t, kind: String, pos: Vector3, name_key: String) -> Dictionary:
	var k: Dictionary = KINDS[kind]
	var body_col: Color = k["color"]
	var tank_col: Color = k["tank"]
	var shells: Array = []
	var main_shell: RigidBody3D = t.shell_box(pos + Vector3(0, 3.5, 0), Vector3(14.0, 7.0, 10.0), body_col, "metal", "%s_main" % name_key, 6.0, false)
	shells.append(main_shell)
	var n: int = int(k["tanks"])
	for i in n:
		var tx: float = pos.x - 5.0 + float(i % 2) * 9.0
		var tz: float = pos.z + (9.5 if i < 2 else -9.5)
		var tank: RigidBody3D = t.shell_box(Vector3(tx, pos.y + 4.0, tz), Vector3(5.0, 8.0, 5.0), tank_col, "metal", "%s_tank%d" % [name_key, i], 5.5, false)
		shells.append(tank)
		var band: RigidBody3D = t.shell_box(Vector3(tx, pos.y + 5.2, tz), Vector3(5.2, 1.2, 5.2), Color(0.85, 0.12, 0.1), "metal", "%s_band%d" % [name_key, i], 5.0, false)
		shells.append(band)
	var lab := Label3D.new()
	lab.text = "%s  - EXPLOSIVE" % str(k["label"])
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.fixed_size = true
	lab.pixel_size = 0.0011
	lab.font_size = 40
	lab.outline_size = 12
	lab.no_depth_test = true
	lab.modulate = Color(1.0, 0.35, 0.2)
	lab.position = pos + Vector3(0, 12.5, 0)
	t.add_child(lab)
	var h := {"kind": kind, "label": str(k["label"]), "pos": pos + Vector3(0, 3.0, 0), "radius": float(k["radius"]), "power": float(k["power"]), "shells": shells,
		"armed": true, "size": 9.0, "pts": int(k["pts"]), "key": name_key, "node": lab}
	t.add_hazard(h)
	return h
