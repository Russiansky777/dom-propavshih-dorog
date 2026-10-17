class_name AmbientFootfall
extends Node2D
## «Живой мир» — what Agata's planted foot does to the ground in a street room.
##
## The moment a foot is planted is taken from the walk sheet, not invented: data/story/ambient/
## _index.json `footfall.<actor>.contact_frames` (the frame after the leading foot's farthest swing,
## where it starts sliding back with the ground — the new support foot of tools/measure_stride.py;
## tests/test_ambient.gd re-measures it from the sheet). On each change of the sheet frame to a
## contact frame while walking, the planted foot is at the drawn feet (foot lock: player.drawn_position)
## plus `planted_foot_px[row][contact]` × depth scale (that foot's centre and sole line in the frame
## of the current direction row, measured from the sheet too):
##   in a `puddles` polygon → a splash: a few drops fly out and fall (0.3–0.5 s, foot y + 1) and a
##                            ring spreads on the water (floor, z −8);
##   in a `mud` polygon     → a boot print (darker than the ground, z −8) that fades in 20–30 s;
##                            at most `prints_max` prints, the oldest goes first.
## Sizes follow the room depth scale exactly as Agata (AmbientGround). Only rooms whose ambient
## data has puddles or mud get this node (no interiors).

var root: AmbientRoot = null
var ground: AmbientGround = null
var cfg: Dictionary = {}
var active: bool = true
var puddles: Array[PackedVector2Array] = []
var mud: Array[PackedVector2Array] = []
var contact_frames: Array[int] = []
var planted_foot_px: Array = []      # [row][contact] → [dx, dy] frame px at scale 1
var prints: AmbientPrints = null

var steps: int = 0
var splashes: int = 0
var prints_made: int = 0
## Last events for tests/probe: {frame, pos, surface, scale}.
var events: Array[Dictionary] = []

var _player: Node2D = null
var _sprite: AnimatedSprite2D = null
var _walk_action: String = "walk"
var _last_frame: int = -1
var _last_pos: Vector2 = Vector2.INF
var _dir: Vector2 = Vector2.RIGHT
var _rng := RandomNumberGenerator.new()


func setup(p_root: AmbientRoot) -> void:
	root = p_root
	ground = root.ground
	cfg = AmbientData.merge(AmbientData.index().get("footfall_defaults", {}), root.spec.get("footfall", {}))
	for e in root.spec.get("puddles", []):
		var pts := AmbientData.shape_of(e)
		if pts.size() >= 3:
			puddles.append(pts)
	for e in root.spec.get("mud", []):
		var pts := AmbientData.shape_of(e)
		if pts.size() >= 3:
			mud.append(pts)
	prints = AmbientPrints.new()
	prints.name = "Prints"
	prints.z_index = AmbientBuilder.Z_DECAL
	prints.ground = ground
	prints.max_prints = clampi(int(cfg.get("prints_max", 24)), 1, 200)
	prints.fade_s = clampf(float(cfg.get("print_fade_s", 25.0)), 1.0, 120.0)
	prints.color = Color.html(String(cfg.get("print_color", "#1e140c")))
	prints.alpha = float(cfg.get("print_alpha", 0.34))
	prints.sheen = Color.html(String(cfg.get("print_sheen", "#c6ccd873")))
	add_child(prints)
	_rng.seed = hash(root.room_id)


func _ready() -> void:
	_bind()


func _exit_tree() -> void:
	_unbind()


func _bind() -> void:
	if _sprite != null:
		return
	var rm := get_node_or_null("/root/RoomManager")
	var p: Node2D = rm.get("player") if rm != null else null
	if p == null or not is_instance_valid(p):
		return
	var spr := p.get("sprite") as AnimatedSprite2D
	var sheet = p.get("sheet")
	if spr == null or sheet == null:
		return
	var actor := String(p.get("actor_id")) if p.get("actor_id") != null else "agata"
	var ff := AmbientData.footfall(actor)
	if ff.is_empty():
		return
	contact_frames.clear()
	for f in ff.get("contact_frames", []):
		contact_frames.append(int(f))
	planted_foot_px = ff.get("planted_foot_px", [])
	_walk_action = String(sheet.get("walk_action")) if sheet.get("walk_action") != null else "walk"
	_player = p
	_sprite = spr
	_last_frame = spr.frame
	_last_pos = p.global_position
	spr.frame_changed.connect(_on_frame_changed)


func _unbind() -> void:
	if _sprite != null and is_instance_valid(_sprite) and _sprite.frame_changed.is_connected(_on_frame_changed):
		_sprite.frame_changed.disconnect(_on_frame_changed)
	_sprite = null
	_player = null


func _process(_delta: float) -> void:
	if _sprite == null:
		_bind()
		return
	if not is_instance_valid(_player):
		_unbind()
		return
	var pos: Vector2 = _player.global_position
	if _last_pos != Vector2.INF:
		var d := pos - _last_pos
		if d.length_squared() > 0.25:
			_dir = d.normalized()
	_last_pos = pos


func _walking() -> bool:
	if _player == null or not _player.has_method("is_walking") or not _player.call("is_walking"):
		return false
	return String(_sprite.animation).begins_with(_walk_action)


## The sheet frame changed (AnimatedSprite2D, after the player re-anchored the drawn figure).
## Re-playing the same frame (a direction switch keeps the stride phase) is not a new step.
func _on_frame_changed() -> void:
	var f := _sprite.frame
	if f == _last_frame:
		return
	_last_frame = f
	if not active or not _walking():
		return
	var k := contact_frames.find(f)
	if k < 0:
		return
	foot_down(foot_position(k), k, f, _player.global_position.y)


## Where the planted foot is: drawn feet + the measured offset of that foot in the current row.
func foot_position(k: int) -> Vector2:
	var base: Vector2 = _player.call("drawn_position") if _player.has_method("drawn_position") else _player.global_position
	var s := absf(_player.scale.y)
	var row := int(_player.get("direction")) if _player.get("direction") != null else 0
	if row >= 0 and row < planted_foot_px.size() and k < planted_foot_px[row].size():
		var o: Array = planted_foot_px[row][k]
		return base + Vector2(float(o[0]), float(o[1])) * s
	return base


func surface_at(pos: Vector2) -> String:
	for p in puddles:
		if Geometry2D.is_point_in_polygon(pos, p):
			return "puddle"
	for p in mud:
		if Geometry2D.is_point_in_polygon(pos, p):
			return "mud"
	return ""


## A foot is planted at `pos` (k = which of the two contacts: alternates left/right). `feet_y` is the
## y the actor is sorted by (its logical feet line; the sole in the sheet sits a little above it):
## the drops sort just in front of the actor whose foot threw them.
func foot_down(pos: Vector2, k: int = 0, frame: int = -1, feet_y: float = NAN) -> String:
	steps += 1
	var surf := surface_at(pos)
	if surf == "puddle":
		_splash(pos, pos.y if is_nan(feet_y) else maxf(feet_y, pos.y))
		splashes += 1
	elif surf == "mud":
		prints.add(pos, ground.floor_dir(_dir, pos.y), 1.0 if k % 2 == 0 else -1.0)
		prints_made += 1
	events.append({"frame": frame, "pos": pos, "surface": surf, "scale": ground.size_scale(pos.y)})
	if events.size() > 32:
		events.pop_front()
	return surf


func _splash(pos: Vector2, feet_y: float) -> void:
	var drops := AmbientSplash.new()
	drops.name = "SplashDrops"
	drops.part = AmbientSplash.DROPS
	drops.z_index = clampi(int(feet_y) + 1, -4096, 4096)
	var ring := AmbientSplash.new()
	ring.name = "SplashRing"
	ring.part = AmbientSplash.RING
	ring.z_index = AmbientBuilder.Z_DECAL
	for n in [drops, ring]:
		n.position = pos
		n.ground = ground
		n.cfg = cfg
		n.seed_value = _rng.randi()
		n.forward = ground.floor_dir(_dir, pos.y)
		root.add_child(n)
		n.start()


func stats() -> Dictionary:
	return {"steps": steps, "splashes": splashes, "prints_made": prints_made, "prints": prints.count() if prints else 0,
		"contact_frames": contact_frames, "bound": _sprite != null}
