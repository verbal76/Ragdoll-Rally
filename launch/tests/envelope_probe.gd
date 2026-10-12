extends SceneTree
## Evidence: the launch envelope (max reachable height at distance x, ideal ballistics, 100%) per mayhem level.
const Rules := preload("res://scripts/rules.gd")
const Main := preload("res://scripts/main.gd")
func _init():
	var best_p := 0
	for c in Rules.CHARACTERS:
		best_p = maxi(best_p, int((c["stats"] as Dictionary)["power"]))
	print("best power stat ", best_p)
	var xs := [20, 40, 60, 80, 100, 140, 180, 220, 260, 300, 340, 380]
	for lvl in [0, 3, 5, 8, 10, 12, 15, 18, 20]:
		var lv: Dictionary = Rules.empty_levels()
		lv["power"] = lvl
		var fx: Dictionary = Rules.effective({"power": best_p, "bounce": 3, "ricochet": 3, "spin": 3, "durability": 3, "chaos": 3}, lv)
		var row := "L%2d vmax %.0f cap R%.0f A%.0f |" % [lvl, Main.speed_for_power(Main.OVERDRIVE_MAX) * float(fx["launch_mult"]), fx["range_cap"], fx["apex_cap"]]
		for x in xs:
			var hbest := -1.0
			for pd in range(3, 40):
				var th := deg_to_rad(float(pd))
				for pw in range(10, 146, 5):
					var v: float = Main.speed_for_power(float(pw) / 100.0) * float(fx["launch_mult"])
					v = Rules.governed_speed(v, th, fx)
					var t: float = float(x) / (v * cos(th))
					var y: float = 2.3 + v * sin(th) * t - 0.5 * Rules.g_eff() * t * t
					if Rules.ideal_range(v, th) >= float(x) - 5.0 or true:
						# the point must be reached before the descent passes the ground: y >= 0 at x
						if y > hbest and y > 0.0:
							hbest = y
			row += " %3.0f" % maxf(hbest, 0.0)
		print(row)
	print("x:", xs)
	quit()
