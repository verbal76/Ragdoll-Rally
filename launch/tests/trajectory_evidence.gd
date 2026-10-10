extends SceneTree
## Prints old (v13, gain 1.05) vs new (v14, gain 0.62) launch pitch / vector / ideal trajectory for representative gestures, plus the
## terrain profile along the launch lane, as JSON for plotting (tests/trajectory_evidence.json in the scratch dir).
const Rules := preload("res://scripts/rules.gd")
const Main := preload("res://scripts/main.gd")
const Terrain := preload("res://scripts/terrain.gd")
func _init() -> void:
	var out := {"gestures": [], "terrain": {}}
	for gname in ["short", "normal", "high", "full", "overdrive"]:
		var b: Dictionary = {"short": 0.35, "normal": 0.6, "high": 0.9, "full": 1.0, "overdrive": 1.45}
		var power: float = float(b[gname])
		var rec := {"name": gname, "power": power}
		for ver in ["old", "new"]:
			var gain: float = 1.05 if ver == "old" else Rules.AIM_ELEV_GAIN
			var p_y: float = minf(power, 1.0)
			var up: float = clampf(p_y, 0.05, 1.0) * gain
			var dir: Vector3 = Rules.launch_dir(Vector3.RIGHT, up)
			var v: float = Main.speed_for_power(power)
			var pitch: float = asin(dir.y)
			var gv: float = Rules.governed_speed(v, pitch, {})
			var pts := []
			var t := 0.0
			while t < 9.0:
				var x: float = gv * dir.x * t
				var y: float = 2.3 + gv * dir.y * t - 0.5 * Rules.g_eff() * t * t
				if y < 0.0 and t > 0.1:
					break
				pts.append([snappedf(x, 0.1), snappedf(y, 0.1)])
				t += 0.1
			rec[ver] = {"pitch_deg": snappedf(rad_to_deg(pitch), 0.1), "dir": [snappedf(dir.x, 0.001), snappedf(dir.y, 0.001), snappedf(dir.z, 0.001)], "speed": snappedf(gv, 0.1), "raw_speed": snappedf(v, 0.1), "range": snappedf(Rules.ideal_range(gv, pitch), 0.1), "apex": snappedf(Rules.ideal_apex(gv, pitch), 0.1), "path": pts}
		out["gestures"].append(rec)
	for h in Rules.HILLS:
		var ter := Terrain.new(h)
		var prof := []
		for x in range(-20, 216, 4):
			prof.append([x, snappedf(ter.height(float(x), 0.0), 0.1)])
		out["terrain"][h["id"]] = prof
	var f := FileAccess.open(OS.get_environment("EVID_OUT"), FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	quit()
