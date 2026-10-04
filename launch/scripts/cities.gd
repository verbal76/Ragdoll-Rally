extends RefCounted
## The five authored cities. Each builds into a Town using its city kit (_block, _prop_box, _glass_wall, _palm, _tank ...).
## Everything is deterministic (Town.hsh, no randomness) so a city always loads identically.
## Layout rule: the launcher is at the origin facing +X; nothing solid within 18 m of it; content runs x 22..145, z -45..45.
## Use with:  const Cities := preload("res://scripts/cities.gd")   (t is the Town being built)

const IDS: Array[String] = ["downtown", "oldtown", "suburbia", "industrial", "resort"]

static func build(t, id: String) -> void:
	match id:
		"downtown": downtown(t)
		"oldtown": oldtown(t)
		"suburbia": suburbia(t)
		"industrial": industrial(t)
		"resort": resort(t)

# ============================================================================ DOWNTOWN: verticality
const DT_COLORS: Array[Color] = [Color(0.55, 0.62, 0.72), Color(0.42, 0.48, 0.58), Color(0.65, 0.58, 0.52), Color(0.35, 0.40, 0.46), Color(0.70, 0.72, 0.76)]

static func _scaffold(t, x: float, z: float, levels: int, group: String) -> void:
	var brown := Color(0.55, 0.38, 0.2)
	for lv in levels:
		var y0: float = float(lv) * 2.6
		for dx in [-1.4, 1.4]:
			for dz in [-1.4, 1.4]:
				t._block(Vector3(x + dx, y0 + 1.3, z + dz), Vector3(0.35, 2.6, 0.35), brown, "wood", 1.0, 3.0, group)
		t._block(Vector3(x, y0 + 2.75, z), Vector3(3.4, 0.3, 3.4), brown.lightened(0.15), "wood", 1.5, 3.0, group)

static func downtown(t) -> void:
	var xs: Array[float] = [26.0, 44.0, 62.0, 80.0, 98.0, 116.0, 134.0]
	var sign_target = null
	for band in [-1, 1]:
		for k in xs.size():
			var x: float = xs[k]
			var hv: int = t.hsh(k, band + 3)
			var h: float = 22.0 + float(hv % 8) * 5.0                 # 22 .. 57 m
			if k == 3 and band == 1:
				h = 58.0
			var zc: float = float(band) * 18.0
			var col: Color = DT_COLORS[hv % DT_COLORS.size()]
			var mat: String = "metal" if hv % 3 == 0 else "masonry"
			t._yard_box(Vector3(x, h * 0.5, zc), Vector3(13.0, h, 14.0), col, mat)
			# avenue-facing glass curtain wall, 0.9 m proud of the wall (smash through into the gap)
			var panes: Array = t._glass_wall(Vector3(x, 0.0, zc - float(band) * 7.9), Vector3.RIGHT, Vector3(0, 0, -band), 13.0, h - 2.0, 4.3, 5.0)
			if k == 0:                                                 # lobby glass on the front face
				t._glass_wall(Vector3(x - 7.9, 0.0, zc), Vector3(0, 0, 1), Vector3(-1, 0, 0), 14.0, h - 2.0, 4.6, 5.0)
				if band == -1:
					t._bonus(panes[panes.size() / 2], "dt_office", "Corner Office", 250)
			# rooftop wooden water tank (falls, burns)
			var tank = t._prop_box(Vector3(x + float(hv % 3 - 1) * 2.0, h, zc), Vector3(3.0, 3.2, 3.0), Color(0.55, 0.45, 0.36), "wood", 14.0)
			if k == 2 and band == -1:
				t._bonus(tank, "dt_tank", "Rooftop Tank", 400)
			# billboards on every other tower: tilted metal, strong ricochets
			if k % 2 == 1:
				var bb = t._yard_box(Vector3(x, h + 3.5, zc), Vector3(0.4, 6.0, 10.0), Color(0.9, 0.35, 0.3).lerp(col, 0.3), "metal", Basis(Vector3.BACK, deg_to_rad(-25.0)))
				t._sign_label(["CITY BANK", "NEON", "HOTEL", "METRO"][hv % 4], Vector3(x - 0.9, h + 3.6, zc), Color(1, 0.95, 0.7), 0.06)
				if k == 3 and band == 1:
					sign_target = bb
			# awning over the street + ledges (bounce / ricochet shelves)
			t._yard_box(Vector3(x, 5.5, zc - float(band) * 9.2), Vector3(11.0, 0.3, 3.2), Color(0.85, 0.2, 0.25) if hv % 2 == 0 else Color(0.2, 0.55, 0.8), "canvas", Basis(Vector3.RIGHT, float(band) * 0.5))
			t._yard_box(Vector3(x, 14.0, zc - float(band) * 7.9), Vector3(12.0, 0.5, 1.6), Color(0.6, 0.6, 0.62), "masonry")
			if h > 34.0:
				t._yard_box(Vector3(x, 30.0, zc - float(band) * 7.9), Vector3(12.0, 0.5, 1.6), Color(0.6, 0.6, 0.62), "masonry")
			# street furniture
			t._prop_box(Vector3(x + 9.0, 0.0, zc - float(band) * 10.5), Vector3(3.0, 1.5, 1.6), Color(0.2, 0.45, 0.25), "metal", 25.0)
			# rear tower band (taller backdrop that can still be hit)
			var h2: float = 36.0 + float(t.hsh(k, band + 9) % 6) * 5.0
			t._yard_box(Vector3(x + 9.0, h2 * 0.5, float(band) * 37.0), Vector3(14.0, h2, 14.0), DT_COLORS[(hv + 2) % DT_COLORS.size()], "masonry")
			t._glass_wall(Vector3(x + 9.0, 0.0, float(band) * 37.0 - float(band) * 7.9), Vector3.RIGHT, Vector3(0, 0, -band), 14.0, h2 * 0.5, 4.6, 5.0)
	# yellow cabs in the avenue (props: ricochet + points)
	for k in 6:
		var cab = t._prop_box(Vector3(xs[k] + 4.0, 0.0, -3.0 + 6.0 * float(k % 2)), Vector3(4.2, 1.4, 1.9), Color(0.95, 0.8, 0.15), "metal", 14.0)
		if k == 1:
			t._bonus(cab, "dt_taxi", "Taxi", 150)
	# scaffolding in the alleys between towers (wood: collapses, burns)
	_scaffold(t, 53.0, -18.0, 4, "scaf_a")
	_scaffold(t, 89.0, 18.0, 4, "scaf_b")
	_scaffold(t, 125.0, -18.0, 3, "scaf_c")
	if sign_target != null:
		t._bonus(sign_target, "dt_sign", "Skyline Sign", 900)

# ============================================================================ OLD TOWN: density + fire
static func _stall(t, x: float, z: float, g: String, col: Color) -> void:
	var wood := Color(0.5, 0.34, 0.2)
	for dx in [-1.2, 1.2]:
		for dz in [-0.9, 0.9]:
			t._block(Vector3(x + dx, 1.2, z + dz), Vector3(0.3, 2.4, 0.3), wood, "wood", 1.0, 3.0, g)
	t._block(Vector3(x, 2.55, z), Vector3(3.0, 0.25, 2.4), col, "canvas", 1.5, 3.0, g)
	t._block(Vector3(x, 0.45, z), Vector3(2.6, 0.9, 0.8), wood.lightened(0.1), "wood", 3.0, 4.0, g)
	for i in 3:
		t._prop("detail-crate", Vector3(x - 1.4 + float(i) * 1.2, 0.0, z + 1.3), Vector3(0.75, 0.75, 0.75), 1.6)

static func oldtown(t) -> void:
	var d: int = 2
	var canal_lo: float = 56.0
	var canal_hi: float = 64.0
	for r in [-1, 1]:
		for lane in 2:
			var oz: int = (3 + lane * 5) if r == 1 else (-(3 + d) - lane * 5)
			var tx: int = 14 if lane == 0 else 22
			var tx_end: int = 70 if lane == 0 else 62
			var idx: int = 0
			while tx < tx_end:
				var hv: int = t.hsh(tx, oz)
				var w: int = 3 + (hv % 2)
				if float(tx) * 1.5 + float(w) * 1.5 > canal_lo and float(tx) * 1.5 < canal_hi:
					tx = int(canal_hi / 1.5) + 1
					continue
				var floors: int = 2 if hv % 4 == 0 else 1
				var group: String = "ot_%d_%d" % [tx, oz]
				if hv % 3 != 0:
					t._wood_house(tx, oz, w, d, floors, group)
				else:
					t._building(tx, oz, w, d, floors, group, false, true, -1)
				if hv % 4 == 1:
					t._chimney_stack(float(tx) + 1.0, float(floors) + 1.0, float(oz) + 0.5, 3, group + "_ch")
				tx += w + (1 if idx % 2 == 0 else 0)
				idx += 1
	# market stalls down the main street + powder kegs
	var cols: Array[Color] = [Color(0.85, 0.25, 0.25), Color(0.25, 0.55, 0.85), Color(0.9, 0.75, 0.2), Color(0.3, 0.7, 0.4)]
	var stall_target = null
	for k in 7:
		var sx: float = 28.0 + float(k) * 9.0
		if sx > canal_lo - 3.0 and sx < canal_hi + 3.0:
			continue
		_stall(t, sx, 1.7 if k % 2 == 0 else -1.7, "stall_%d" % k, cols[k % 4])
		if k == 2:
			stall_target = t.groups["stall_2"][0]
	for kx in [46.0, 48.0]:
		t._tnt_barrel(kx, 0.0)
		t._tnt_barrel(kx, 1.2)
	for i in 14:
		t._prop("detail-barrel", Vector3(24.0 + float(i) * 6.5, 0.0, 6.0 if i % 2 == 0 else -6.0), Vector3(0.62, 0.75, 0.62), 2.0)
	# canal with a wooden bridge (water skips fast)
	t._yard_box(Vector3((canal_lo + canal_hi) * 0.5, 0.025, 0.0), Vector3(canal_hi - canal_lo - 2.0, 0.05, 70.0), Color(0.2, 0.45, 0.7), "water")
	var bridge = t._block(Vector3((canal_lo + canal_hi) * 0.5, 0.4, 0.0), Vector3(canal_hi - canal_lo, 0.3, 4.6), Color(0.5, 0.34, 0.2), "wood", 6.0, 5.0, "bridge", true)
	t._bonus(bridge, "ot_bridge", "Old Bridge", 150)
	# bell tower at the end of the street
	var tower = t._tower_stack(67, -1, 9, "belltower")
	t._bonus(tower, "ot_bell", "Bell Tower", 900)
	t._building(64, 2, 2, 2, 1, "chapel", false, true, -1)
	if stall_target != null:
		t._bonus(stall_target, "ot_stall", "Market Stall", 250)

# ============================================================================ SUBURBIA: lower heights, long skips
static func suburbia(t) -> void:
	var xs: Array[float] = [24.0, 40.0, 56.0, 72.0, 88.0, 104.0, 120.0]
	var car_cols: Array[Color] = [Color(0.8, 0.15, 0.15), Color(0.2, 0.35, 0.8), Color(0.85, 0.85, 0.85), Color(0.15, 0.15, 0.17), Color(0.2, 0.6, 0.3)]
	var pool_target = null
	var tramp_target = null
	var garage_target = null
	for side in [-1, 1]:
		for k in xs.size():
			var x: float = xs[k]
			var hv: int = t.hsh(k, side + 5)
			var tx: int = int(x / 1.5)
			var tz: int = 9 if side == 1 else -12
			var group: String = "sub_%d_%d" % [k, side]
			if hv % 2 == 0:
				t._wood_house(tx, tz, 3, 2, 1 + (hv / 5) % 2, group)
			else:
				t._building(tx, tz, 3, 2, 1, group, false, true, -1)
			if k % 2 == 0:                                            # attached garage
				t._building(tx + 4, tz, 2, 2, 1, group + "_g", false, true, -1)
				if garage_target == null:
					garage_target = t.groups[group + "_g"][0]
			# front fence line + mailbox + hedge + car
			for f in 6:
				t._prop("fence-wood", Vector3(x - 5.0 + float(f) * 1.6, 0.0, float(side) * 10.0), Vector3(1.5, 0.9, 0.2), 1.2)
			t._prop_box(Vector3(x - 6.0, 0.0, float(side) * 6.5), Vector3(0.4, 1.1, 0.4), Color(0.2, 0.3, 0.7), "metal", 2.0)
			t._prop("tree-shrub", Vector3(x + 4.0, 0.0, float(side) * 11.0), Vector3(1.2, 1.0, 1.2), 2.0)
			t._prop_box(Vector3(x + 6.0, 0.0, float(side) * 7.5), Vector3(4.4, 1.4, 2.0), car_cols[hv % car_cols.size()], "metal", 16.0)
			# backyard: pool / trampoline / swing set / shed
			var bz: float = float(side) * 26.0
			match hv % 4:
				0:
					t._yard_box(Vector3(x, 0.03, bz), Vector3(11.0, 0.06, 8.0), Color(0.85, 0.8, 0.7), "ground")
					var pool = t._yard_box(Vector3(x, 0.1, bz), Vector3(9.0, 0.12, 6.0), Color(0.3, 0.7, 0.95), "water")
					if pool_target == null:
						pool_target = pool
				1:
					var tr = t._yard_box(Vector3(x, 0.3, bz), Vector3(5.0, 0.6, 5.0), Color(0.25, 0.25, 0.3), "trampoline")
					if tramp_target == null:
						tramp_target = tr
				2:
					for sx in [-2.2, 2.2]:
						t._yard_box(Vector3(x + sx, 1.6, bz), Vector3(0.3, 3.2, 3.0), Color(0.75, 0.2, 0.2), "metal", Basis(Vector3.BACK, deg_to_rad(8.0) * signf(sx)))
					t._yard_box(Vector3(x, 3.1, bz), Vector3(5.0, 0.3, 0.3), Color(0.75, 0.2, 0.2), "metal")
				_:
					t._wood_house(int(x / 1.5), int(bz / 1.5), 2, 2, 1, group + "_shed")
	# utility poles along the road (tall wood, cross arms)
	for i in 5:
		var px: float = 30.0 + float(i) * 22.0
		t._yard_box(Vector3(px, 5.0, 5.2), Vector3(0.4, 10.0, 0.4), Color(0.45, 0.32, 0.2), "wood")
		t._yard_box(Vector3(px, 9.4, 5.2), Vector3(0.3, 0.3, 3.0), Color(0.45, 0.32, 0.2), "wood")
	# playground slide in the cul-de-sac end
	t._yard_box(Vector3(136.0, 1.6, 0.0), Vector3(8.0, 0.3, 2.4), Color(0.9, 0.7, 0.1), "water", Basis(Vector3.BACK, deg_to_rad(-22.0)))
	if pool_target != null:
		t._bonus(pool_target, "sub_pool", "Cannonball", 300)
	if tramp_target != null:
		t._bonus(tramp_target, "sub_tramp", "Trampoline Bonus", 150)
	if garage_target != null:
		t._bonus(garage_target, "sub_garage", "Garage Door", 200)

# ============================================================================ INDUSTRIAL: heavy destruction + chains
static func _warehouse(t, cx: float, cz: float, w: float, d: float, h: float, col: Color, g: String) -> void:
	var wall_col: Color = col.darkened(0.1)
	t._yard_box(Vector3(cx, h, cz), Vector3(w + 0.6, 0.6, d + 0.6), wall_col.darkened(0.2), "metal")         # roof
	t._yard_box(Vector3(cx + w * 0.5, h * 0.5, cz), Vector3(0.7, h, d), wall_col, "metal")                   # back wall
	t._yard_box(Vector3(cx, h * 0.5, cz - d * 0.5), Vector3(w, h, 0.7), wall_col, "metal")                   # side walls
	t._yard_box(Vector3(cx, h * 0.5, cz + d * 0.5), Vector3(w, h, 0.7), wall_col, "metal")
	var cols: int = int(d / 3.0)
	var rows: int = int(h / 3.5)
	for r in rows:                                                                                           # breakable front panels
		for c in cols:
			t._block(Vector3(cx - w * 0.5, (float(r) + 0.5) * 3.5, cz - d * 0.5 + (float(c) + 0.5) * 3.0 + 0.0), Vector3(0.7, 3.5, 3.0), col, "metal", 6.0, 11.0, g)
	for i in 4:                                                                                              # pallets (burn) and drums inside
		for j in 2:
			t._block(Vector3(cx - w * 0.25 + float(i) * 3.2, 0.7, cz - 3.0 + float(j) * 6.0), Vector3(1.4, 1.4, 1.4), Color(0.6, 0.45, 0.28), "wood", 2.0, 3.0, g + "_in")
	t._tnt_barrel(cx - w * 0.3, cz + d * 0.25)
	t._tnt_barrel(cx - w * 0.3 + 1.2, cz + d * 0.25)

static func industrial(t) -> void:
	_warehouse(t, 46.0, -20.0, 22.0, 18.0, 10.0, Color(0.55, 0.62, 0.7), "wh_a")
	_warehouse(t, 46.0, 20.0, 22.0, 18.0, 10.0, Color(0.7, 0.55, 0.45), "wh_b")
	_warehouse(t, 100.0, 0.0, 24.0, 30.0, 12.0, Color(0.5, 0.6, 0.55), "wh_c")
	t._bonus(t.groups["wh_c"][0], "ind_roofhall", "Main Hall", 300)
	# shipping-container stacks (heavy, tough)
	var ccols: Array[Color] = [Color(0.75, 0.2, 0.15), Color(0.15, 0.4, 0.7), Color(0.85, 0.65, 0.1), Color(0.2, 0.55, 0.35)]
	for xi in [70.0, 82.0]:
		for zi in [-34.0, -26.0, -14.0, 14.0, 26.0, 34.0]:
			var hv: int = t.hsh(int(xi), int(zi))
			for lvl in 1 + hv % 3:
				t._block(Vector3(xi, 1.3 + 2.6 * float(lvl), zi), Vector3(10.0, 2.6, 2.5), ccols[(hv + lvl) % 4], "metal", 8.0, 12.0, "cont_%d_%d" % [int(xi), int(zi)])
	# tank farm: big tanks, explosive fuel tanks, drum rings, pipes
	var farm_x: float = 118.0
	for zi in [-36.0, -22.0, -8.0]:
		t._tank(Vector3(farm_x, 0.0, zi), 5.0, 9.0, Color(0.8, 0.8, 0.82))
		t._tnt_barrel(farm_x - 7.5, zi + 3.0)
		t._tnt_barrel(farm_x - 8.7, zi + 3.0)
	var fuel1 = t._prop_box(Vector3(farm_x - 6.0, 0.0, -29.0), Vector3(3.6, 3.6, 3.6), Color(0.85, 0.2, 0.15), "metal", 40.0, 12.0)
	t._prop_box(Vector3(farm_x - 6.0, 0.0, -15.0), Vector3(3.6, 3.6, 3.6), Color(0.85, 0.2, 0.15), "metal", 40.0, 12.0)
	t._prop_box(Vector3(farm_x + 8.0, 0.0, -22.0), Vector3(3.6, 3.6, 3.6), Color(0.85, 0.2, 0.15), "metal", 40.0, 12.0)
	t._bonus(fuel1, "ind_fuel", "Fuel Depot", 800)
	for k in 3:                                                                                              # pipe rack (elevated ricochet bars)
		t._yard_box(Vector3(farm_x - 10.0, 3.4, -30.0 + float(k) * 14.0), Vector3(0.9, 0.9, 12.0), Color(0.7, 0.45, 0.2), "metal")
		t._yard_box(Vector3(farm_x - 10.0, 1.7, -30.0 + float(k) * 14.0), Vector3(0.5, 3.4, 0.5), Color(0.4, 0.4, 0.42), "metal")
	# cranes
	var crane_cols := Color(0.95, 0.75, 0.1)
	for cz in [-40.0, 38.0]:
		t._yard_box(Vector3(78.0, 17.0, cz), Vector3(2.5, 34.0, 2.5), crane_cols, "metal")
		t._yard_box(Vector3(64.0, 34.0, cz), Vector3(30.0, 1.6, 1.6), crane_cols, "metal")
		var hook = t._yard_box(Vector3(56.0, 28.0, cz), Vector3(1.4, 1.4, 1.4), Color(0.3, 0.3, 0.32), "metal")
		if cz > 0.0:
			t._bonus(hook, "ind_hook", "Crane Hook", 700)
	# smokestacks: static base + three breakable top blocks that topple
	for sp in [Vector3(112.0, 0.0, 30.0), Vector3(126.0, 0.0, 34.0)]:
		t._yard_box(Vector3(sp.x, 13.0, sp.z), Vector3(4.5, 26.0, 4.5), Color(0.55, 0.3, 0.25), "masonry")
		var top = null
		for lv in 3:
			top = t._block(Vector3(sp.x, 28.25 + 4.5 * float(lv), sp.z), Vector3(4.5, 4.5, 4.5), Color(0.55, 0.3, 0.25), "masonry", 6.0, 7.0, "stack_%d" % int(sp.x), true)
		if sp.x < 120.0:
			t._bonus(top, "ind_stack", "Smokestack", 900)
	# pallet + barrel kindling between the buildings (the fuse of the chain)
	for i in 8:
		t._block(Vector3(60.0 + float(i % 4) * 1.6, 0.7 + float(i / 4) * 1.4, -6.0 + float(i % 2) * 1.6), Vector3(1.4, 1.4, 1.4), Color(0.6, 0.45, 0.28), "wood", 2.0, 3.0, "pallets")
	t._tnt_barrel(64.5, -4.0)
	t._tnt_barrel(64.5, 4.0)
	for i in 6:                                                                                              # machinery
		t._yard_box(Vector3(30.0 + float(i) * 5.0, 1.2, 0.0 if i % 2 == 0 else 8.0), Vector3(3.0, 2.4, 2.2), Color(0.4, 0.5, 0.55), "metal")

# ============================================================================ RESORT STRIP: spectacle + weird rebounds
static func _hotel(t, cx: float, cz: float, w: float, h: float, d: float, col: Color, toward: int, label: String) -> Object:
	var body = t._yard_box(Vector3(cx, h * 0.5, cz), Vector3(w, h, d), col, "masonry")
	var face_z: float = cz + float(toward) * (d * 0.5 + 0.9)
	t._glass_wall(Vector3(cx, 0.0, face_z), Vector3.RIGHT, Vector3(0, 0, toward), w, h - 2.0, w / float(maxi(int(w / 4.6), 1)), 4.0)
	for y in [8.0, 16.0, 24.0]:
		if y < h - 4.0:
			t._yard_box(Vector3(cx, y, cz + float(toward) * (d * 0.5 + 1.4)), Vector3(w - 2.0, 0.4, 2.2), Color(0.95, 0.95, 0.95), "masonry")
	t._yard_box(Vector3(cx, 5.2, cz + float(toward) * (d * 0.5 + 3.0)), Vector3(9.0, 0.3, 4.0), Color(1.0, 0.5, 0.7), "canvas", Basis(Vector3.RIGHT, -float(toward) * 0.4))
	var sign_b = t._yard_box(Vector3(cx, h + 3.0, cz), Vector3(0.4, 5.0, w * 0.7), Color(1.0, 0.85, 0.3), "metal", Basis(Vector3.BACK, deg_to_rad(-20.0)))
	t._sign_label(label, Vector3(cx - 0.9, h + 3.2, cz), Color(1.0, 0.2, 0.6), 0.08)
	return sign_b

static func resort(t) -> void:
	var sign_a = _hotel(t, 52.0, -22.0, 22.0, 34.0, 18.0, Color(1.0, 0.62, 0.7), 1, "FLAMINGO")
	t._bonus(sign_a, "rs_sign", "Flamingo Sign", 900)
	t._glass_wall(Vector3(40.0, 0.0, -22.0), Vector3(0, 0, 1), Vector3(-1, 0, 0), 16.0, 12.0, 4.0, 4.0)       # lobby glass facing the launcher
	var pent = _hotel(t, 96.0, 22.0, 26.0, 44.0, 18.0, Color(0.45, 0.85, 0.85), -1, "AQUA")
	t._bonus(pent, "rs_aqua", "Aqua Penthouse", 600)
	_hotel(t, 124.0, -22.0, 20.0, 28.0, 16.0, Color(1.0, 0.9, 0.45), 1, "SUNSET")
	# palm boulevard
	for i in 15:
		var px: float = 24.0 + float(i) * 8.0
		t._palm(Vector3(px, 0.0, -8.5))
		t._palm(Vector3(px + 4.0, 0.0, 8.5))
	# pools + decks, loungers, umbrellas
	for pc in [Vector3(52.0, 0.1, -5.5), Vector3(96.0, 0.1, 5.5)]:
		t._yard_box(Vector3(pc.x, 0.03, pc.z), Vector3(18.0, 0.06, 8.0), Color(0.95, 0.92, 0.85), "ground")
		var pool = t._yard_box(pc, Vector3(14.0, 0.12, 5.0), Color(0.25, 0.75, 0.95), "water")
		if pc.x < 60.0:
			t._bonus(pool, "rs_pool", "Pool Splash", 300)
		for i in 3:
			t._prop_box(Vector3(pc.x - 6.0 + float(i) * 6.0, 0.0, pc.z + (5.0 if pc.z < 0.0 else -5.0)), Vector3(2.0, 0.5, 0.8), Color(1, 1, 1), "canvas", 3.0)
		t._yard_box(Vector3(pc.x + 7.0, 2.2, pc.z + (5.2 if pc.z < 0.0 else -5.2)), Vector3(4.2, 0.2, 4.2), Color(1.0, 0.4, 0.4), "canvas", Basis(Vector3.BACK, deg_to_rad(12.0)))
	# waterslide: a tower and two angled, offset segments (slippery, odd rebounds)
	t._yard_box(Vector3(70.0, 7.0, 14.0), Vector3(4.0, 14.0, 4.0), Color(0.95, 0.5, 0.15), "metal")
	var seg1 = t._yard_box(Vector3(80.0, 9.0, 14.0), Vector3(16.0, 0.4, 3.6), Color(0.2, 0.7, 1.0), "water", Basis(Vector3.BACK, deg_to_rad(-24.0)))
	t._yard_box(Vector3(92.0, 3.2, 12.0), Vector3(14.0, 0.4, 3.6), Color(0.1, 0.85, 0.7), "water", Basis(Vector3.UP, deg_to_rad(18.0)) * Basis(Vector3.BACK, deg_to_rad(-16.0)))
	t._bonus(seg1, "rs_slide", "Waterslide", 400)
	# inflatable bouncy castle in the boulevard + stage with scaffolding + beach cabanas + shops
	var castle = t._yard_box(Vector3(112.0, 3.0, 0.0), Vector3(10.0, 6.0, 10.0), Color(1.0, 0.5, 0.85), "canvas")
	t._bonus(castle, "rs_castle", "Bouncy Castle", 250)
	for dx in [-4.0, 4.0]:
		for dz in [-3.0, 3.0]:
			t._block(Vector3(132.0 + dx, 4.0, 4.0 + dz), Vector3(0.5, 8.0, 0.5), Color(0.3, 0.3, 0.35), "metal", 3.0, 7.0, "stage")
	var beam = t._block(Vector3(132.0, 8.4, 4.0), Vector3(10.0, 0.8, 0.8), Color(0.3, 0.3, 0.35), "metal", 5.0, 7.0, "stage", true)
	t._bonus(beam, "rs_stage", "Main Stage", 600)
	t._yard_box(Vector3(136.0, 5.0, 4.0), Vector3(0.4, 7.0, 9.0), Color(0.95, 0.3, 0.7), "metal", Basis(Vector3.BACK, deg_to_rad(-15.0)))
	for i in 5:
		t._wood_house(int((104.0 + float(i) * 6.0) / 1.5), int(-36.0 / 1.5), 2, 2, 1, "cabana_%d" % i)
	for sz in [-14.0, 14.0]:
		var shop_h: float = 7.0
		t._yard_box(Vector3(32.0, shop_h * 0.5, sz + (3.5 if sz < 0.0 else -3.5)), Vector3(16.0, shop_h, 7.0), Color(0.55, 0.85, 0.9) if sz < 0.0 else Color(0.95, 0.8, 0.5), "masonry")
		t._glass_wall(Vector3(32.0, 0.0, sz + (-0.1 if sz < 0.0 else 0.1) + (7.0 if sz < 0.0 else -7.0) * 0.0 + (0.0 if sz < 0.0 else 0.0)), Vector3.RIGHT, Vector3(0, 0, 1 if sz < 0.0 else -1), 16.0, 6.0, 4.0, 3.0)
