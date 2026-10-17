class_name ActorSheet
extends RefCounted
## Builds SpriteFrames for an actor from `data/actors/<id>.json` + the sheet's `sprites.json`.
## Rows of a sheet are directions, columns are frames. Animations are named "<action>_<dir>".

var id: String = ""
var frame_w: int = 288
var frame_h: int = 384
var pivot: Vector2 = Vector2(0.5, 0.946)
var directions: int = 8
var actions: Dictionary = {}       # action -> {sheet, frames, fps}
## Direction mapping (data): `direction_zero` = where row 0 faces on screen ("down" = towards the
## viewer), `direction_order` = how rows go on screen ("ccw" or "cw").
var direction_zero: String = "down"
var direction_order: String = "ccw"
var figure_height_px: float = 337.0
var character_height_m: float = 1.657
var speed_mps: float = 1.12          # walking speed in model metres per second
var cycle_meters: float = 1.3        # ground covered by one full walk cycle (two steps)
var direction_threshold_px: float = 0.5
## Foot lock: the drawn figure advances only when the walk frame changes (by exactly one stride),
## so the planted foot never drifts while a frame is shown. The logical position still moves smoothly.
var foot_lock: bool = true
## Root motion by the stance foot (data walk.stride_table, written by tools/measure_stride.py):
## stride_rows[row][k] = sheet px (scale 1) the planted foot slides back between frames k and k+1.
## Empty → constant stride cycle_px / frames for every row (old behaviour).
var stride_rows: Array = []
var stride_row_cycle: PackedFloat32Array = PackedFloat32Array()
var stride_start_frame: int = 0
var stride_sheet_md5: String = ""
var idle_action: String = "idle"
var walk_action: String = "walk"
var talk_action: String = "talk"
## NPC placement (data `npc`): where the figure faces when nothing happens, a multiplier on the
## room's depth scale (height relative to Agata) and a feet offset from the hotspot's bottom centre.
var facing: String = "down"
var scale_factor: float = 1.0
var feet_offset: Vector2 = Vector2.ZERO
## Contact shadow (data `shadow`): ellipse width in model metres, height as a fraction of the width,
## peak opacity. Every actor gets one (ActorShadow); zero alpha disables it.
var shadow_width_m: float = 0.6
var shadow_height_ratio: float = 0.3
var shadow_alpha: float = 0.5
## Cross-fade between two different animations (idle↔walk↔talk↔action): the old pose fades out
## over this many seconds on top of the new one (ActorCrossfade). 0 disables.
var crossfade_s: float = 0.12
## One-shot actions (data `action_key_frame`): the sheet frame at which the action's effect is
## applied (the hand reaches the shutter, the item leaves the floor).
var action_key_frames: Dictionary = {}
## Actions of the pipeline's sprites.json the game does not use (data `skip_actions`, e.g. a sheet
## that duplicates another): not built, no warning.
var skip_actions: Array = []
## Even idle sway (data idle_motion, tools/measure_idle.py): per row {frames, path}.
var idle_motion_rows: Array = []
var idle_motion_md5: String = ""
var idle_static_frame: int = -1   # >= 0: the idle animation uses only this frame (turn clips, placeholders)
var sheet_dir: String = ""
var frames: SpriteFrames = null
var load_error: String = ""


static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed


## `overrides` replaces top-level keys of data/actors/<id>.json (tests: e.g. {"idle_static_frame": -1}).
static func load_actor(actor_id: String, overrides: Dictionary = {}) -> ActorSheet:
	var a := ActorSheet.new()
	a.id = actor_id
	var spec = _read_json("res://data/actors/%s.json" % actor_id)
	if typeof(spec) != TYPE_DICTIONARY:
		a.load_error = "missing data/actors/%s.json" % actor_id
		return a
	for k in overrides.keys():
		spec[k] = overrides[k]
	a.sheet_dir = String(spec.get("sheet_dir", "res://assets/characters/" + actor_id))
	a.direction_zero = String(spec.get("direction_zero", "down"))
	a.direction_order = String(spec.get("direction_order", "ccw"))
	a.figure_height_px = float(spec.get("figure_height_px", a.figure_height_px))
	var walk: Dictionary = spec.get("walk", {})
	a.speed_mps = float(walk.get("speed_mps", a.speed_mps))
	a.cycle_meters = float(walk.get("cycle_meters", a.cycle_meters))
	a.direction_threshold_px = float(walk.get("direction_threshold_px", a.direction_threshold_px))
	a.foot_lock = bool(walk.get("foot_lock", a.foot_lock))
	var st: Dictionary = walk.get("stride_table", {})
	if not st.is_empty():
		a.stride_rows = st.get("rows", [])
		for r in a.stride_rows:
			var sum := 0.0
			for v in r:
				sum += float(v)
			a.stride_row_cycle.append(sum)
		a.stride_start_frame = int(st.get("start_frame", 0))
		a.stride_sheet_md5 = String(st.get("sheet_md5", ""))
	a.idle_action = String(spec.get("idle_action", "idle"))
	a.walk_action = String(spec.get("walk_action", "walk"))
	a.talk_action = String(spec.get("talk_action", "talk"))
	var npc: Dictionary = spec.get("npc", {})
	a.facing = String(npc.get("facing", "down"))
	var sf = npc.get("scale_factor", 1.0)
	var auto_scale: bool = typeof(sf) == TYPE_STRING and String(sf) == "auto"
	a.scale_factor = 1.0 if auto_scale else float(sf)
	var fo: Array = npc.get("feet_offset", [0, 0])
	a.feet_offset = Vector2(float(fo[0]), float(fo[1]))
	var shadow: Dictionary = spec.get("shadow", {})
	a.shadow_width_m = float(shadow.get("width_m", a.shadow_width_m))
	a.shadow_height_ratio = float(shadow.get("height_ratio", a.shadow_height_ratio))
	a.shadow_alpha = float(shadow.get("alpha", a.shadow_alpha))
	a.idle_static_frame = int(spec.get("idle_static_frame", -1))
	var sprites = _read_json(a.sheet_dir + "/" + String(spec.get("sprites", "sprites.json")))
	if typeof(sprites) != TYPE_DICTIONARY:
		a.load_error = "missing sprites.json in " + a.sheet_dir
		return a
	a.frame_w = int(sprites.get("frame_w", 288))
	a.frame_h = int(sprites.get("frame_h", 384))
	var p: Dictionary = sprites.get("pivot", {})
	a.pivot = Vector2(float(p.get("x", 0.5)), float(p.get("y", 0.946)))
	a.directions = int(sprites.get("directions", 8))
	a.character_height_m = float(sprites.get("character_height_m", a.character_height_m))
	if auto_scale:
		# Every sheet is rendered with the figure filling the same frame height, so on screen an NPC's
		# height relative to the reference actor is the ratio of the model heights in the sprites.json.
		var ref_id := String(npc.get("height_reference", "agata"))
		var ref_spec = _read_json("res://data/actors/%s.json" % ref_id)
		var ref_dir := "res://assets/characters/" + ref_id
		if typeof(ref_spec) == TYPE_DICTIONARY:
			ref_dir = String(ref_spec.get("sheet_dir", ref_dir))
		var ref_sprites = _read_json(ref_dir + "/sprites.json")
		var ref_h: float = float(ref_sprites.get("character_height_m", 0.0)) if typeof(ref_sprites) == TYPE_DICTIONARY else 0.0
		if ref_h > 0.0:
			a.scale_factor = a.character_height_m / ref_h
	a.actions = sprites.get("actions", {})
	# Actor data may override per-action playback (e.g. a non-cyclic talk clip → pingpong) without
	# touching the pipeline's sprites.json.
	var over: Dictionary = spec.get("actions", {})
	for act_name in over.keys():
		if a.actions.has(act_name) and typeof(over[act_name]) == TYPE_DICTIONARY:
			var merged: Dictionary = (a.actions[act_name] as Dictionary).duplicate()
			for k in over[act_name].keys():
				if not String(k).begins_with("_"):
					merged[k] = over[act_name][k]
			a.actions[act_name] = merged
	a.crossfade_s = float(spec.get("crossfade_s", a.crossfade_s))
	a.skip_actions = spec.get("skip_actions", [])
	var im: Dictionary = spec.get("idle_motion", {})
	a.idle_motion_rows = im.get("rows", [])
	a.idle_motion_md5 = String(im.get("sheet_md5", ""))
	var kf: Dictionary = spec.get("action_key_frame", {})
	for k in kf.keys():
		if not String(k).begins_with("_"):
			a.action_key_frames[String(k)] = int(kf[k])
	a._build_frames()
	return a


func _build_frames() -> void:
	frames = SpriteFrames.new()
	frames.remove_animation("default")
	for action in actions.keys():
		if skip_actions.has(String(action)):
			continue
		var act: Dictionary = actions[action]
		var path := sheet_dir + "/" + String(act.get("sheet", action + ".png"))
		if not ResourceLoader.exists(path):
			if String(action) == idle_action or String(action) == walk_action:
				load_error = "missing sheet " + path
			else:
				push_warning("ActorSheet %s: no sheet for action '%s' (%s) — action skipped" % [id, action, path])
			continue
		var tex: Texture2D = load(path)
		var n := int(act.get("frames", 1))
		var fps := float(act.get("fps", 8))
		var frame_ids: Array = frame_sequence(n, String(act.get("playback", "loop")))
		if String(action) == idle_action and idle_static_frame >= 0 and idle_static_frame < n:
			frame_ids = [idle_static_frame]
		var eased: bool = String(act.get("playback", "")) == "pingpong_eased" and frame_ids.size() > 1
		for d in directions:
			var anim := "%s_%d" % [action, d]
			frames.add_animation(anim)
			frames.set_animation_loop(anim, bool(act.get("loop", true)))
			if eased:
				# Eased back-and-forth: timeline steps of 1/EASE_FPS s, each sheet frame held as long
				# as the eased path stays nearest to it (per-frame duration in steps).
				frames.set_animation_speed(anim, EASE_FPS)
				for seg in eased_timeline(String(action), d):
					var at := AtlasTexture.new()
					at.atlas = tex
					at.region = Rect2(int(seg[0]) * frame_w, d * frame_h, frame_w, frame_h)
					frames.add_frame(anim, at, float(seg[2]))
				continue
			frames.set_animation_speed(anim, fps)
			for i in frame_ids:
				var at := AtlasTexture.new()
				at.atlas = tex
				at.region = Rect2(i * frame_w, d * frame_h, frame_w, frame_h)
				frames.add_frame(anim, at)


const EASE_FPS: float = 30.0


## Eased back-and-forth of an action on row `row` (playback "pingpong_eased"; data idle_motion: the
## frames kept for this row and their path fractions 0..1). One period starts and ends in the middle
## of the hold on the first pose: hold → cosine ease along the path to the last pose → hold → ease
## back. Each moment shows the frame nearest to the eased path position. The two holds are adjusted
## so the total time spent in each extreme pose is the same. Returns [[column, seconds, steps], ...].
func eased_timeline(action: String, row: int) -> Array:
	var act: Dictionary = actions.get(action, {})
	var mrow: Dictionary = {}
	if row < idle_motion_rows.size():
		mrow = idle_motion_rows[row]
	var cols: Array = mrow.get("frames", range(int(act.get("frames", 1))))
	var path: Array = mrow.get("path", [])
	if path.size() != cols.size():
		path = []
		for i in cols.size():
			path.append(float(i) / maxf(cols.size() - 1, 1))
	# Symmetrise the measured path about its midpoint (average with its mirror; moves no frame by
	# more than a few % of the path): the middle frame sits at 0.5 and both end gaps are equal, so
	# travel times and holds come out the same towards both extremes.
	var sym: Array = []
	for k in path.size():
		sym.append((float(path[k]) + 1.0 - float(path[path.size() - 1 - k])) * 0.5)
	path = sym
	var period: float = float(act.get("period_s", 3.6))
	var hold: float = float(act.get("hold_s", 0.35))
	var ease: float = maxf((period - 2.0 * hold) / 2.0, 0.2)
	# Time the ease spends in each extreme pose (nearest-frame boundaries at half the end gaps).
	var n := cols.size()
	var tau0 := 0.0
	var tau1 := 0.0
	if n > 1:
		tau0 = ease * acos(clampf(1.0 - float(path[1]), -1.0, 1.0)) / PI
		tau1 = ease * acos(clampf(float(path[n - 2]), -1.0, 1.0)) / PI
	var h0 := hold + maxf(0.0, 2.0 * (tau1 - tau0))
	var h1 := hold + maxf(0.0, 2.0 * (tau0 - tau1))
	var total := 2.0 * ease + h0 + h1
	var steps := int(round(total * EASE_FPS))
	var dt := total / float(steps)
	var out: Array = []
	for i in steps:
		var t := (float(i) + 0.5) * dt
		var u := 0.0
		if t < h0 * 0.5:
			u = 0.0
		elif t < h0 * 0.5 + ease:
			u = (1.0 - cos(PI * (t - h0 * 0.5) / ease)) * 0.5
		elif t < h0 * 0.5 + ease + h1:
			u = 1.0
		elif t < h0 * 0.5 + 2.0 * ease + h1:
			u = (1.0 + cos(PI * (t - h0 * 0.5 - ease - h1) / ease)) * 0.5
		var best := 0
		for k in n:
			if absf(float(path[k]) - u) < absf(float(path[best]) - u):
				best = k
		var col := int(cols[best])
		if not out.is_empty() and int(out[-1][0]) == col:
			out[-1][1] = float(out[-1][1]) + dt
			out[-1][2] = int(out[-1][2]) + 1
		else:
			out.append([col, dt, 1])
	return out


## Played sequence of an action (sheet columns, before any idle_static_frame pinning). For an eased
## back-and-forth, the columns of `row`'s timeline (each shown for its own duration).
func action_sequence(action: String, row: int = 0) -> Array:
	var act: Dictionary = actions.get(action, {})
	if String(act.get("playback", "")) == "pingpong_eased":
		return eased_timeline(action, row).map(func(seg): return int(seg[0]))
	return frame_sequence(int(act.get("frames", 1)), String(act.get("playback", "loop")))


## True when the action repeats (idle, walk, talk); one-shot actions (`"loop": false`) play once.
func action_loops(action: String) -> bool:
	return bool(actions.get(action, {}).get("loop", true))


## Sheet columns played per cycle. "loop": 0..n-1. "pingpong": 0..n-1 then n-2..1 (the clip is
## rendered as a window of the Meshy action, so playing it back and forth hides the cut; the
## `window` field of sprites.json is render metadata and is ignored here).
static func frame_sequence(n: int, playback: String) -> Array:
	var seq: Array = range(n)
	if playback == "pingpong" and n > 2:
		for i in range(n - 2, 0, -1):
			seq.append(i)
	return seq


func is_loaded() -> bool:
	return load_error == "" and frames != null and frames.get_animation_names().size() > 0


## Sprite offset so that the pivot (feet) sits at the node origin (AnimatedSprite2D centered=false).
func sprite_offset() -> Vector2:
	return Vector2(-pivot.x * frame_w, -pivot.y * frame_h)


## Screen motion vector (y down) → direction row index. Evaluates the data mapping:
## a = atan2(vy, vx) in degrees; row = round((zero − a) / step) mod rows for "ccw", (a − zero) for "cw".
func direction_index(motion: Vector2) -> int:
	if motion.length_squared() < 0.000001:
		return 0
	var deg := rad_to_deg(atan2(motion.y, motion.x))
	var zero: float = float({"down": 90.0, "right": 0.0, "up": -90.0, "left": 180.0}.get(direction_zero, 90.0))
	var step: float = 360.0 / float(directions)
	var rel: float = (zero - deg) if direction_order == "ccw" else (deg - zero)
	return wrapi(int(round(rel / step)), 0, directions)


## Pixels per model metre at a given node scale (frame height spans the model's height).
func px_per_meter(scale: float) -> float:
	return float(frame_h) * scale / maxf(character_height_m, 0.01)


## Walking speed in screen px/s at a given depth scale (constant in metres per second).
func walk_speed_px(scale: float) -> float:
	return speed_mps * px_per_meter(scale)


## Frame rate of the walk cycle for a given screen speed and scale:
## fps = frames × speed_px / (cycle_meters × px_per_m).
func walk_fps(speed_px: float, scale: float) -> float:
	var n := walk_frames()
	return float(n) * speed_px / maxf(cycle_meters * px_per_meter(scale), 0.001)


func walk_frames() -> int:
	return int(actions.get(walk_action, {}).get("frames", 12))


func has_stride_table() -> bool:
	return stride_rows.size() == directions and stride_rows[0].size() == walk_frames()


## Ground the drawn figure covers between walk frames k and k+1 of a row (sheet px, scale 1).
func stride_at(row: int, k: int) -> float:
	if has_stride_table():
		return float(stride_rows[wrapi(row, 0, directions)][wrapi(k, 0, walk_frames())])
	return stride_px_unit()


## One walk cycle of a row on screen (sheet px, scale 1).
func row_cycle_px(row: int) -> float:
	if has_stride_table():
		return stride_row_cycle[wrapi(row, 0, directions)]
	return cycle_meters * px_per_meter(1.0)


## Walk-cycle frame rate (constant): frames × speed_mps / cycle_meters.
func walk_fps_const() -> float:
	return float(walk_frames()) * speed_mps / maxf(cycle_meters, 0.001)


## Logical walking speed in px/s for a direction row at a depth scale: the row's cycle per period, so
## the drawn figure (which advances by the row's table) and the logical position stay together.
func walk_speed_row_px(row: int, scale: float) -> float:
	return row_cycle_px(row) * scale * walk_fps_const() / float(walk_frames())


## Ground covered by one walk frame, in sheet pixels (node scale 1): cycle_px / frames.
## This is the distance the planted foot slides back between two consecutive sheet frames
## (measured on the sheet by tools/measure_stride.py), so the figure may advance by exactly
## this much per frame without the foot drifting.
func stride_px_unit() -> float:
	return cycle_meters * px_per_meter(1.0) / float(maxi(walk_frames(), 1))


func anim_name(action: String, dir: int) -> String:
	return "%s_%d" % [action, dir]


## Key frame of a one-shot action (index in the played sequence); defaults to the middle.
func action_key_frame(action: String) -> int:
	if action_key_frames.has(action):
		return int(action_key_frames[action])
	return action_sequence(action).size() / 2


func has_action(action: String) -> bool:
	return actions.has(action) and frames != null and frames.has_animation(anim_name(action, 0))


## Compass word → screen vector (y down): "down" = towards the viewer.
static func facing_vector(word: String) -> Vector2:
	match word:
		"up", "n": return Vector2(0, -1)
		"left", "w": return Vector2(-1, 0)
		"right", "e": return Vector2(1, 0)
		"down_left", "sw": return Vector2(-1, 1)
		"down_right", "se": return Vector2(1, 1)
		"up_left", "nw": return Vector2(-1, -1)
		"up_right", "ne": return Vector2(1, -1)
	return Vector2(0, 1)
