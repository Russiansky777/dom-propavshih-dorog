extends SceneTree
## Probe: the idle desync mechanism on Agata's model with villager-style data (local: villager GLBs do not import here).

func _init() -> void:
	await process_frame
	var base = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/agata.json"))
	var out := []
	for id in ["ilya", "ulyana", "nina"]:
		var spec: Dictionary = base.duplicate(true)
		spec["id"] = id
		spec["rt3d"]["idle"]["pool"] = [spec["rt3d"]["idle"]["pool"][0]]
		spec["rt3d"]["idle"]["desync"] = {"phase": true, "rate_jitter": 0.07}
		var v := Actor3D.new()
		root.add_child(v)
		print(id, " ok=", v.setup(spec), " idle=", v.idle_phase(), " rate=%.3f breath=%.2f t=%.2f" % [v.idle_rate, v.life.breath_period_s, v.life.t])
		for i in 120:
			v.pose(1.0 / 60.0, 0.0, 0.0, 0.0)
		print("   after 2 s: ", v.idle_phase())
		v.queue_free()
	quit(0)
