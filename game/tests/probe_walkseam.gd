extends SceneTree
## The walk as played (baked loop, via the tree, loco 1): LeftFoot / RightFoot step and second difference per 1/60 s
## over one and a half cycles — the seam must not stand out.

func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	for id in OS.get_cmdline_user_args():
		var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/%s.json" % id))
		var v := Actor3D.new()
		root.add_child(v)
		if not v.setup(spec):
			continue
		v.life.active = false
		print(id, " walk ", v.clips["walk"], " len ", v.walk_len)
		var prev: Array = []
		var pv: Array = []
		var line := ""
		var n := int(round(v.walk_len * 60.0 * 1.5))
		for i in n:
			var ph := fposmod(float(i) / 60.0 / v.walk_len, 1.0)
			v._apply(ph, 1.0, 0.0, "", 0.0)
			var f := [v.bone_model("LeftFoot"), v.bone_model("RightFoot"), v.bone_model("LeftHand")]
			if not prev.is_empty():
				var st := []
				for k in 3:
					st.append(f[k] - prev[k])
				if not pv.is_empty():
					var d := 0.0
					for k in 3:
						d = maxf(d, (st[k] - pv[k]).length())
					line += " %.2f:%d" % [ph, int(d * 1000.0)]
				pv = st
			prev = f
		print(line)
		v.queue_free()
		await process_frame
	quit(0)
