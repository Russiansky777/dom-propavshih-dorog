extends SceneTree
## The walk's rhythm as seen: per frame the figure's speed on the floor (m/s), the hips' height (cm) and the
## planted foot — over steady walking across the room. A walk that «floats» has a flat speed and a flat hip line.
##   -- [rate]

var _drawn: Array = []
var _prev_c: Array = []


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var gs = root.get_node("GameState")
	var rm = root.get_node("RoomManager")
	var PS = load("res://scripts/actors/player.gd")
	PS.forced_render = "3d"
	var main_node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main_node)
	for i in 4:
		await process_frame
	rm.autosave_enabled = false
	var player: Node2D = main_node.get_node("World/Player")
	gs.reset()
	for f in ["done_M01", "done_M02", "house_unlocked", "done_M03", "met_tikhon"]:
		gs.set_flag(f, true)
	rm.change_room("Z2", "default", Vector2(400, 900))
	for i in 20:
		await process_frame
	player.yaw3d = PI * 0.5
	player.yaw3d_target = PI * 0.5
	for i in 20:
		await process_frame
	player.click_at(player.global_position + Vector2(900, 0))
	var v: Actor3D = player.view3d
	v.skeleton.skeleton_updated.connect(func(): _drawn = v.feet_model())
	var prev: Vector2 = player.global_position
	var sp: Array = []
	var hz: Array = []
	var hs: Array = []   # the hips' own speed on the floor (figure + the hips inside it) — what the eye follows
	var sk: Array = []   # the lower foot's speed on the floor (mm/frame): a planted foot that skates
	var prev_h := NAN
	for i in 150:
		await process_frame
		var ppm_s: float = v.ppm * absf(player.scale.y)
		var d: Vector2 = player.global_position - prev
		prev = player.global_position
		# floor metres: the figure's own step (screen px over this depth's scale) + the bone inside the figure
		var ox: float = d.x / ppm_s
		var hx: float = v.bone_floor("Hips").x + ox
		# the feet as drawn (after the IK): per foot its contact — the ankle or the ball, whichever is nearer its floor —
		# while it is within 1 cm of it; its move on the floor this frame (mm): what a viewer sees skate
		var yb := Basis(Vector3.UP, v.get_yaw())
		var dl: Array = _drawn if not _drawn.is_empty() else v.feet_model()
		var cx: Array = []
		var slip := 0.0
		for f in 2:
			var ha: float = dl[f * 2].y - v.stride_floor[f * 2]
			var hb: float = dl[f * 2 + 1].y - v.stride_floor[f * 2 + 1]
			var c: int = f * 2 if ha <= hb else f * 2 + 1
			cx.append([(yb * dl[c]).x + ox, minf(ha, hb) < 0.01, c])
			if minf(ha, hb) < 0.01 and _prev_c.size() == 2 and int(_prev_c[f][2]) == c and bool(_prev_c[f][1]):
				slip = maxf(slip, absf(float(cx[f][0]) - float(_prev_c[f][0])) * 1000.0)
		_prev_c = []
		for f in 2:
			_prev_c.append([(yb * dl[int(cx[f][2])]).x, cx[f][1], cx[f][2]])
		if i > 50 and player.walk_w > 0.99:
			sp.append(d.length() / ppm_s * 60.0)
			hz.append(v.bone_model("Hips").y * 100.0)
			hs.append(absf(hx - prev_h) * 60.0)
			sk.append(slip)
		prev_h = v.bone_floor("Hips").x
	var skm: Array = sk.duplicate()
	skm.sort()
	print("drawn foot contacts (ankle or ball within 1 cm of the floor) per frame: median %.1f mm, 90%% %.1f, max %.1f" % [skm[skm.size() / 2], skm[int(skm.size() * 0.9)], skm.max()])
	var line := ""
	for k in range(0, sp.size(), 2):
		line += "%.2f/%.1f " % [sp[k], hz[k] - (hz.min() as float)]
	print("speed m/s: min %.2f max %.2f mean %.2f; hips height range %.1f cm" % [sp.min(), sp.max(), (sp.reduce(func(a, b): return a + b) as float) / sp.size(), (hz.max() as float) - (hz.min() as float)])
	print(line)
	line = "hips m/s / hips cm / planted foot mm per frame: "
	for k in range(0, hs.size(), 2):
		line += "%.2f/%.1f/%.0f " % [hs[k], hz[k] - (hz.min() as float), sk[k]]
	print("hips speed: min %.2f max %.2f; at the lowest third of the hips %.2f, at the highest third %.2f" % [hs.min(), hs.max(), _mean_where(hs, hz, true), _mean_where(hs, hz, false)])
	print(line)
	PS.forced_render = ""
	quit(0)


## Mean hips speed where the hips are in their lowest (or highest) third — an inverted pendulum is fastest low.
func _mean_where(sp: Array, hz: Array, low: bool) -> float:
	var lo: float = hz.min()
	var hi: float = hz.max()
	var acc := 0.0
	var n := 0
	for k in sp.size():
		var u: float = (float(hz[k]) - lo) / maxf(hi - lo, 0.001)
		if (low and u < 0.333) or (not low and u > 0.667):
			acc += float(sp[k])
			n += 1
	return acc / maxi(n, 1)
