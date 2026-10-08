extends RefCounted
## Deep districts for the flat boards: the city does not end where the old content did. Past the original skyline a ring of
## kit buildings (destruction shells, same system as the hillside cities) continues out to ~330 m, each building no taller than
## the Lv20 launch envelope can actually reach at its distance, so the whole world is hittable by *some* upgrade level and the
## tallest, deepest buildings are what a maxed Ragnar flies for.
## Use with:  const Outskirts := preload("res://scripts/outskirts.gd")

const Rules := preload("res://scripts/rules.gd")
const Hillside := preload("res://scripts/hillside.gd")
const Destruction := preload("res://scripts/destruction.gd")

const X_END := 318.0
const FLOOR_H := 3.1
const SEG_FLOORS := 5
const LANE := 7.0                          # clear avenue along the launch line (z = 0)

## Per board identity: where the district starts, palette, how tall it likes to be (0 low-rise .. 1 skyline), roof, material.
const STYLES := {
	"downtown": {"x0": 158.0, "tall": 1.0, "roof": 1, "mat": "masonry", "pitch": 24.0, "dens": 0.92,
		"pal": [Color(0.72, 0.78, 0.86), Color(0.86, 0.80, 0.70), Color(0.66, 0.72, 0.80), Color(0.80, 0.84, 0.88), Color(0.90, 0.86, 0.76)]},
	"oldtown": {"x0": 116.0, "tall": 0.35, "roof": 0, "mat": "masonry", "pitch": 22.0, "dens": 0.9,
		"pal": [Color(0.86, 0.72, 0.58), Color(0.80, 0.62, 0.50), Color(0.92, 0.82, 0.66), Color(0.74, 0.60, 0.48), Color(0.88, 0.78, 0.60)]},
	"suburbia": {"x0": 140.0, "tall": 0.2, "roof": 0, "mat": "wood", "pitch": 20.0, "dens": 0.85,
		"pal": [Color(0.96, 0.84, 0.70), Color(0.78, 0.88, 0.80), Color(0.86, 0.80, 0.92), Color(0.98, 0.92, 0.72), Color(0.76, 0.84, 0.94)]},
	"industrial": {"x0": 138.0, "tall": 0.55, "roof": 1, "mat": "masonry", "pitch": 26.0, "dens": 0.8,
		"pal": [Color(0.62, 0.40, 0.32), Color(0.58, 0.58, 0.60), Color(0.70, 0.50, 0.36), Color(0.50, 0.54, 0.58), Color(0.66, 0.46, 0.34)]},
	"resort": {"x0": 150.0, "tall": 0.7, "roof": 1, "mat": "masonry", "pitch": 24.0, "dens": 0.85,
		"pal": [Color(1.0, 0.72, 0.78), Color(0.62, 0.90, 0.90), Color(1.0, 0.92, 0.78), Color(0.94, 0.78, 0.94), Color(0.80, 0.94, 0.78)]},
	"city": {"x0": 192.0, "tall": 0.6, "roof": 1, "mat": "masonry", "pitch": 24.0, "dens": 0.85,
		"pal": [Color(0.86, 0.82, 0.72), Color(0.74, 0.80, 0.86), Color(0.90, 0.74, 0.66), Color(0.78, 0.86, 0.74), Color(0.92, 0.88, 0.80)]},
	"hill_steep": {"x0": 206.0, "tall": 0.15, "roof": 0, "mat": "wood", "pitch": 22.0, "dens": 0.8,
		"pal": [Color(0.92, 0.78, 0.62), Color(0.86, 0.66, 0.54), Color(0.78, 0.84, 0.74), Color(0.94, 0.88, 0.72), Color(0.82, 0.72, 0.64)]},
	"hill_valley": {"x0": 206.0, "tall": 0.12, "roof": 0, "mat": "wood", "pitch": 22.0, "dens": 0.75,
		"pal": [Color(0.90, 0.80, 0.66), Color(0.80, 0.86, 0.78), Color(0.94, 0.84, 0.70), Color(0.84, 0.74, 0.64), Color(0.88, 0.90, 0.80)]},
	"hill_rolling": {"x0": 206.0, "tall": 0.1, "roof": 0, "mat": "wood", "pitch": 24.0, "dens": 0.6,
		"pal": [Color(0.92, 0.84, 0.68), Color(0.78, 0.86, 0.72), Color(0.88, 0.74, 0.62), Color(0.94, 0.90, 0.76), Color(0.82, 0.80, 0.70)]},
	"hill_skyline": {"x0": 206.0, "tall": 0.55, "roof": 1, "mat": "masonry", "pitch": 24.0, "dens": 0.85,
		"pal": [Color(0.76, 0.80, 0.86), Color(0.86, 0.82, 0.72), Color(0.70, 0.76, 0.84), Color(0.84, 0.86, 0.88), Color(0.90, 0.84, 0.74)]},
	"yard": {"x0": 100.0, "tall": 0.6, "roof": 1, "mat": "masonry", "pitch": 26.0, "dens": 0.8,
		"pal": [Color(0.95, 0.55, 0.40), Color(0.45, 0.75, 0.95), Color(0.98, 0.85, 0.35), Color(0.60, 0.90, 0.55), Color(0.85, 0.60, 0.90)]},
}

static func has_style(env_id: String) -> bool:
	return STYLES.has(env_id)

## Tallest building top (m above ground) allowed at distance x: 88% of what a maxed launch can reach there, less the launcher height.
static func height_cap(x: float) -> float:
	return maxf(0.88 * Rules.reach_height(x, Rules.MAYHEM_MAX) - 3.0, 0.0)

static func _hf(i: int, j: int, s: int) -> float:
	return Hillside._hf(i, j, s)

## Builds the district into Town `t`. Deterministic per env id. Returns {"buildings": n, "tallest": m, "landmarks": [bodies]}.
static func build(t, env_id: String) -> Dictionary:
	if not STYLES.has(env_id) or t.legacy:
		return {"buildings": 0, "tallest": 0.0, "landmarks": []}
	var st: Dictionary = STYLES[env_id]
	var c := Hillside.Ctx.new()
	c.t = t
	var seed: int = 4171 + env_id.hash() % 977
	var pal: Array = st["pal"]
	var pitch: float = float(st["pitch"])
	var tall: float = float(st["tall"])
	var x0: float = float(st["x0"])
	var count := 0
	var tallest := 0.0
	var landmarks: Array = []
	var cands: Array = []
	var ix := 0
	var x: float = x0
	while x < X_END - pitch * 0.5:
		var iz := 0
		var z: float = -108.0
		while z <= 108.0:
			var hv: float = _hf(ix, iz, seed)
			if absf(z) > LANE and hv < float(st["dens"]):
				var jx: float = (_hf(ix, iz, seed + 1) - 0.5) * pitch * 0.25
				var jz: float = (_hf(ix, iz, seed + 2) - 0.5) * pitch * 0.25
				var px: float = x + jx
				var pz: float = z + jz
				var gl: float = 1e9
				var gh: float = -1e9
				for q in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1), Vector2(0, 0)]:
					var gq: float = t.ground_y(px + q.x * 10.0, pz + q.y * 10.0)
					gl = minf(gl, gq)
					gh = maxf(gh, gq)
				if gh - gl > 7.5:
					iz += 1
					z += pitch
					continue                                    # too steep for a building pad
				var cap: float = height_cap(px) - gl - 2.7           # less the roof
				if cap < 2.0 * FLOOR_H:
					iz += 1
					z += pitch
					continue                                    # the ground here is already above what a launch can reach
				# lower buildings near the avenue edges and the district start; tall ones cluster toward the middle band
				var core: float = 1.0 - clampf(absf(pz) / 110.0, 0.0, 1.0) * 0.6
				var want: float = lerpf(5.0, cap, pow(_hf(ix, iz, seed + 3), lerpf(2.2, 0.8, tall)) * core)
				if _hf(ix, iz, seed + 4) < 0.07 * tall:
					want = cap                                   # the odd building right at the envelope: a trophy for a maxed launch
				var floors: int = clampi(int(round(want / FLOOR_H)), 2, 34)
				if floors * FLOOR_H > cap + 0.5:
					floors = maxi(int(floor(cap / FLOOR_H)), 1)
				var w: float = 9.0 + 9.0 * _hf(ix, iz, seed + 5)
				var d: float = 9.0 + 8.0 * _hf(ix, iz, seed + 6)
				var col: Color = pal[int(_hf(ix, iz, seed + 7) * float(pal.size())) % pal.size()]
				var body: RigidBody3D = tower(c, Vector3(px, gl - 0.4, pz), w, d, floors, (PI * 0.5 if _hf(ix, iz, seed + 8) > 0.5 else 0.0), col, str(st["mat"]), int(st["roof"]), int(_hf(ix, iz, seed + 9) * 1000.0), "os_%d_%d" % [ix, iz])
				count += 1
				var top: float = float(floors) * FLOOR_H
				if top > tallest:
					tallest = top
				if floors >= 4:
					landmarks.append(body)
					cands.append({"x": px, "top": top, "body": body})
			iz += 1
			z += pitch
		ix += 1
		x += pitch
	# three deep landmark targets (bands 190-240 / 240-280 / 280+): the tallest building in each is worth a trophy score
	var names: Array = LANDMARK_NAMES.get(env_id, ["FAR TOWER", "OUTER SPIRE", "DISTANT CROWN"])
	var pts: Array[int] = [900, 1800, 3500]
	var band_lo: Array[float] = [x0, 240.0, 280.0]
	var band_hi: Array[float] = [240.0, 280.0, 400.0]
	for b in 3:
		var best: Dictionary = {}
		for cd in cands:
			if float(cd["x"]) >= band_lo[b] and float(cd["x"]) < band_hi[b] and (best.is_empty() or float(cd["top"]) > float(best["top"])):
				best = cd
		if not best.is_empty():
			t._bonus(best["body"], "os_land_%d" % b, str(names[b]), pts[b])
	return {"buildings": count, "tallest": tallest, "landmarks": landmarks}

const LANDMARK_NAMES := {
	"downtown": ["MIDTOWN TOWER", "SKYLINE SPIRE", "APEX TOWER"], "oldtown": ["FAR BELFRY", "OUTER KEEP", "DISTANT MINARET"],
	"suburbia": ["WATER TOWER", "RIDGE HOUSE", "FAR ESTATE"], "industrial": ["FAR REFINERY", "OUTER SILO", "DISTANT STACK"],
	"resort": ["OUTER HOTEL", "SUNSET TOWER", "FAR FLAMINGO"], "city": ["OUTER KEEP", "FAR TOWER", "DISTANT CITADEL"],
	"yard": ["TEST TOWER", "FAR TOWER", "LONG SHOT"],
	"hill_steep": ["RIDGE HOUSE", "CREST MANOR", "SUMMIT VILLA"], "hill_valley": ["VALLEY TOWER", "FAR VILLA", "HILLTOP HALL"],
	"hill_rolling": ["KNOLL HOUSE", "FAR FARM", "HEIGHTS HALL"], "hill_skyline": ["RIDGE TOWER", "CREST SPIRE", "SUMMIT TOWER"],
}

## One kit building as a stack of destruction shells (<= SEG_FLOORS floors each), linked so the upper segments fall when the
## storey under them is destroyed. Returns the top segment's body.
static func tower(c, base: Vector3, w: float, d: float, floors: int, yaw: float, col: Color, mat_name: String, roof_kind: int, vs: int, grp: String) -> RigidBody3D:
	var nwc: int = clampi(int(round(w / Hillside.CELL_W)), 1, 3)
	var ndc: int = clampi(int(round(d / Hillside.CELL_W)), 1, 3)
	var tint := Color(minf(col.r / 0.72, 1.5), minf(col.g / 0.74, 1.5), minf(col.b / 0.92, 1.5)).lerp(Color(1, 1, 1), 0.2)
	var kmat: StandardMaterial3D = Hillside._kit_mat(c, tint, 1 if _hf(vs, 5, 11) < 0.3 else 0)
	var segs: int = int(ceil(float(floors) / float(SEG_FLOORS)))
	var sy: float = FLOOR_H / (Hillside.CELL_H)
	var roof_unit: float = 0.52 if roof_kind == 0 else 0.215
	var y: float = base.y
	var f_done := 0
	var prev: RigidBody3D = null
	var top: RigidBody3D = null
	for sgi in segs:
		var f_seg: int = mini(SEG_FLOORS, floors - f_done)
		var is_top: bool = sgi == segs - 1
		var seg_floors_h: float = float(f_seg) * Hillside.CELL_H * sy
		var roof_h: float = roof_unit * sy
		var seg_h: float = seg_floors_h + (roof_h if is_top else 0.0)
		var seg_roof: int = roof_kind if is_top else 2
		var um: Mesh = Hillside._unit_mesh(nwc, ndc, f_seg, seg_roof, vs)
		var scl := Vector3(w / float(nwc), sy, d / float(ndc))
		var kit: Dictionary = {"mesh": um, "mat": kmat, "scale": scl}
		var pos := Vector3(base.x, y + seg_h * 0.5, base.z)
		var tough: float = 6.0 if mat_name == "masonry" else 4.2
		var b: RigidBody3D = Hillside._hblock(c, pos, Vector3(w, seg_h, d), yaw, col, mat_name, grp, 3.0 + seg_h * w * d * 0.012, tough, true, false, kit)
		Destruction.register_shell(b, Hillside._kit_cells.bind(nwc, ndc, f_seg, seg_roof, vs, scl, Vector3(w, seg_h, d), kmat, roof_unit, is_top), nwc * ndc * (f_seg + (1 if seg_roof < 2 else 0)))
		if prev != null:
			Destruction.link_stack(prev, b)
		prev = b
		top = b
		y += seg_h
		f_done += f_seg
	return top
