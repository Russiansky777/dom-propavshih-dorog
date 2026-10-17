extends SceneTree
## Evidence frames for room lighting (not a test; needs a display — tools/shots_lighting.sh runs it
## under Xvfb with the OpenGL renderer, the same GL Compatibility path as the web build):
##   xvfb-run -s "-screen 0 1920x1080x24" godot --path game --display-driver x11 \
##     --rendering-driver opengl3 -s res://tests/shots_lighting.gd -- <out_dir> [scenario ...]
## The real game (Main.tscn): flags are set, the room is entered, Agata is placed, frames are saved as
## <out_dir>/<scenario>[_NN].png. Series (`frames` > 1) are for GIFs (tools/shots_lighting.sh).

var _out_dir := ""
var _main: Node = null
var _player: Node2D = null

const SCENARIOS := {
	"H1_closed_cold": {"room": "H1", "flags": [], "pos": [1250, 860]},
	"H1_closed_stove": {"room": "H1", "flags": ["stove_lit"], "pos": [760, 880]},
	"H1_open_stove": {"room": "H1", "flags": ["stove_lit", "h1_shutter_open"], "pos": [760, 880]},
	"H1_open_cold": {"room": "H1", "flags": ["h1_shutter_open"], "pos": [1250, 860]},
	# Shutters open at t = 0: frames every 0.1 s show the 0.8 s fade.
	"H1_shutter_fade": {"room": "H1", "flags": ["stove_lit"], "pos": [1450, 880], "set_after": ["h1_shutter_open"], "frames": 12, "dt": 0.1, "time_scale": 0.25},
	# The fire itself: crop around the stove mouth, 24 frames at 1/12 s.
	"H1_fire": {"room": "H1", "flags": ["stove_lit"], "pos": [900, 1000], "frames": 24, "dt": 0.0833, "time_scale": 0.35, "crop": [40, 300, 300, 260]},
	# Agata walking past the stove: her cast shadow from the fire.
	"H1_shadow_walk": {"room": "H1", "flags": ["stove_lit"], "pos": [520, 860], "walk_to": [1300, 900], "frames": 16, "dt": 0.18, "time_scale": 0.35},
	"H1_at_stove": {"room": "H1", "flags": ["stove_lit"], "pos": [640, 830]},
	"H1_mid_stove": {"room": "H1", "flags": ["stove_lit"], "pos": [1000, 800]},
	"H1_tone_dark": {"room": "H1", "flags": [], "pos": [1250, 900], "pair": true},
	"H1_tone_dark_stove": {"room": "H1", "flags": ["stove_lit"], "pos": [640, 800], "pair": true},
	"H1_tone_dark_mid": {"room": "H1", "flags": ["stove_lit"], "pos": [1100, 860], "pair": true},
	"H1_tone_dark_nostove_mid": {"room": "H1", "flags": [], "pos": [1100, 860], "pair": true},
	"H1_tone_dark_door": {"room": "H1", "flags": ["stove_lit"], "pos": [980, 775], "pair": true},
	"H1_tone_open": {"room": "H1", "flags": ["h1_shutter_open"], "pos": [1250, 900], "pair": true},
	"H2_tone": {"room": "H2", "flags": [], "pos": [520, 880], "pair": true},
	"H2_door": {"room": "H2", "flags": [], "pos": [520, 880]},
	"H2_shadow_walk": {"room": "H2", "flags": [], "pos": [300, 820], "walk_to": [800, 1000], "frames": 14, "dt": 0.18, "time_scale": 0.35},
	"H2_flicker": {"room": "H2", "flags": [], "pos": [600, 950], "frames": 16, "dt": 0.1, "crop": [0, 80, 700, 900]},
	"Z1_lamp": {"room": "Z1", "flags": [], "pos": [560, 860]},
	"Z1_lamp_series": {"room": "Z1", "flags": [], "pos": [560, 860], "frames": 16, "dt": 0.1, "crop": [150, 350, 300, 260]},
	"Z1_shadow_walk": {"room": "Z1", "flags": [], "pos": [300, 900], "walk_to": [1500, 950], "frames": 16, "dt": 0.2, "time_scale": 0.35},
}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out_dir = args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://../build/shots/lighting")
	var names: Array = []
	for i in range(1, args.size()):
		names.append(args[i])
	if names.is_empty():
		names = SCENARIOS.keys()
	_run(names)


func _run(names: Array) -> void:
	await process_frame
	var gs = root.get_node("GameState")
	var rm = root.get_node("RoomManager")
	gs.reset()
	_main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(_main)
	await process_frame
	await process_frame
	rm.autosave_enabled = false
	_player = _main.get_node("World/Player")
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var made := 0
	for n in names:
		if not SCENARIOS.has(n):
			push_error("shots_lighting: unknown scenario " + str(n))
			continue
		made += await _scenario(String(n), SCENARIOS[n], gs, rm)
	gs.reset()
	quit(0 if made > 0 else 1)


func _scenario(sname: String, sc: Dictionary, gs, rm) -> int:
	gs.reset()
	for f in sc.get("flags", []):
		gs.set_flag(String(f), true)
	var pos: Array = sc.get("pos", [960, 900])
	rm.change_room(String(sc["room"]), "", Vector2(float(pos[0]), float(pos[1])))
	for i in 30:
		await process_frame
	var hover: Node = _main.find_child("Hover", true, false)
	if hover is CanvasItem:
		(hover as CanvasItem).visible = false
	# Slow game time for series: under llvmpipe one 1920x1080 frame takes ~0.1 s of wall time.
	var ts := float(sc.get("time_scale", 1.0))
	Engine.time_scale = ts
	for f in sc.get("set_after", []):
		gs.set_flag(String(f), true)
	if sc.has("walk_to"):
		var w: Array = sc["walk_to"]
		_player.call("walk_to", Vector2(float(w[0]), float(w[1])))
	var frames := int(sc.get("frames", 1))
	var dt := float(sc.get("dt", 0.1))
	var made := 0
	for k in frames:
		if k > 0:
			var t0 := Time.get_ticks_usec()
			while (Time.get_ticks_usec() - t0) < int(dt / ts * 1000000.0):
				await process_frame
		var hv: Node = _main.find_child("Hover", true, false)
		if hv is CanvasItem:
			(hv as CanvasItem).modulate.a = 0.0  # the cursor sits mid-screen under Xvfb
		await RenderingServer.frame_post_draw
		var img := root.get_viewport().get_texture().get_image()
		if img.get_width() != 1920:
			img.resize(1920, 1080, Image.INTERPOLATE_LANCZOS)
		if sc.has("crop"):
			var c: Array = sc["crop"]
			img = img.get_region(Rect2i(int(c[0]), int(c[1]), int(c[2]), int(c[3])))
		var path := _out_dir.path_join(("%s_%02d.png" % [sname, k]) if frames > 1 else ("%s.png" % sname))
		img.save_png(path)
		made += 1
		if sc.get("pair", false):
			# The same instant without Agata: tools/measure_tone.py compares her with the floor by her.
			_player.visible = false
			await process_frame
			await RenderingServer.frame_post_draw
			var bg := root.get_viewport().get_texture().get_image()
			if bg.get_width() != 1920:
				bg.resize(1920, 1080, Image.INTERPOLATE_LANCZOS)
			bg.save_png(path.get_basename() + "_bg.png")
			_player.visible = true
	Engine.time_scale = 1.0
	print("lighting shots %s: %d frame(s) → %s" % [sname, made, _out_dir])
	return made
