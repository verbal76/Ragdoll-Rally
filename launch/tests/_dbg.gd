extends SceneTree
const Rules := preload("res://scripts/rules.gd")
const Hillside := preload("res://scripts/hillside.gd")
func _init():
	_r.call_deferred()
func _r():
	var main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.skip_select = true
	main.force_rebuild = true
	root.add_child(main)
	for i in 5: await process_frame
	for id in ["hill_steep","hill_rolling"]:
		Hillside.dbg = {}
		main.start_game(0, main.Rules.env_index(id))
		for i in 3: await process_frame
		print(id, " lots ", Hillside.last_stats["lots"].size(), " ", Hillside.dbg, " contours ", Hillside.last_stats["contours"])
	quit()
