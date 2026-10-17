class_name PuppetActor
extends Node2D
## A bone-rigged character drawn from ONE picture (Tikhon): a Polygon2D mesh laid over the opaque
## part of the image, skinned to a Skeleton2D whose bones come from data/actors/<id>.json. Weights are
## computed here from the data's regions (tail / head / ears / body, with smooth seams) and, inside the
## tail, by distance to its links. Life comes from two AnimationPlayers built in code from the data:
## "Life" loops breathing + a tail wave (one seamless period); "Accent" plays one-shots — an ear twitch
## or a small head tilt every few seconds, a head lift on the character's own lines, "scared" (tail up
## and fluffed) for future scenes.
##
## Attached by NpcActor.attach_all for an `npc` hotspot whose actor data has "type": "puppet". It
## mirrors the hotspot's visibility (Tikhon: after M03) and leaves clicks to the hotspot. Placement:
## data `place.<room>` (feet + floor depth), else the hotspot's bottom centre. The room's light tones it
## like the sheet actors (RoomLighting.actor_tone_at, eased); a small soft contact shadow sits under it.

const TONE_RATE := 6.0

var actor_id: String = ""
var spec: Dictionary = {}
var hotspot: Node2D = null
var player: Node2D = null
var poly: Polygon2D = null
var skeleton: Skeleton2D = null
var bones: Dictionary = {}          # name -> Bone2D
var life: AnimationPlayer = null
var accent: AnimationPlayer = null
var talking: bool = false
var scared: bool = false
var tex_scale: float = 1.0          # texture px per source px
var depth_y: float = 0.0
var _rng := RandomNumberGenerator.new()
var _next_accent: float = 0.0
var _tone: Color = Color.WHITE
var _tone_set: bool = false
var _room: Node = null


static func all_in(room: Node) -> Array:
	var out: Array = []
	if room == null:
		return out
	for c in room.get_children():
		if c is PuppetActor:
			out.append(c)
	return out


func setup(id: String, h: Node2D, room: Node, the_player: Node2D) -> bool:
	actor_id = id
	hotspot = h
	player = the_player
	_room = room
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/%s.json" % id))
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	spec = parsed
	var tex_path := String(spec.get("image", ""))
	if not ResourceLoader.exists(tex_path):
		push_warning("PuppetActor %s: no image %s" % [id, tex_path])
		return false
	var tex: Texture2D = load(tex_path)
	var src: float = float(spec.get("source_size", tex.get_width()))
	tex_scale = float(tex.get_width()) / src
	_build_rig(tex)
	_place(room, h)
	_build_shadow()
	_build_animations()
	# The puppet replaces the placeholder box with the name (like NpcActor hides the static image);
	# the hotspot itself (shape, hover label, clicks) stays as it is.
	var placeholder := h.get_node_or_null("Visual")
	if placeholder != null:
		placeholder.visible = false
	var img := h.get_node_or_null("Image")
	if img != null:
		img.visible = false
	visible = h.visible
	h.visibility_changed.connect(func(): visible = hotspot.visible)
	StoryRunner.beat_changed.connect(_on_beat_changed)
	_rng.seed = hash(id)
	_next_accent = _rng.randf_range(2.0, 5.0)
	life.play("idle")
	return true


func _exit_tree() -> void:
	if StoryRunner.beat_changed.is_connected(_on_beat_changed):
		StoryRunner.beat_changed.disconnect(_on_beat_changed)


# --- Rig ---------------------------------------------------------------------

## Source px → rig space (texture px with the feet at the origin).
func _rig(p: Vector2) -> Vector2:
	var feet := _v(spec.get("feet_px", [0, 0]))
	return (p - feet) * tex_scale


static func _v(a) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


func _build_rig(tex: Texture2D) -> void:
	var rig := Node2D.new()
	rig.name = "Rig"
	add_child(rig)
	skeleton = Skeleton2D.new()
	skeleton.name = "Skeleton"
	rig.add_child(skeleton)
	# Bones: positions relative to their parent, rest = the drawn pose.
	var defs: Array = spec.get("bones", [])
	var abs_from := {}
	for b in defs:
		var bone := Bone2D.new()
		bone.name = String(b["name"])
		var from := _rig(_v(b["from"]))
		var to := _rig(_v(b["to"]))
		abs_from[bone.name] = from
		var parent_name := String(b.get("parent", ""))
		var parent: Node = skeleton if parent_name == "" else bones[parent_name]
		var parent_origin: Vector2 = Vector2.ZERO if parent_name == "" else abs_from[parent_name]
		bone.position = from - parent_origin
		bone.set_autocalculate_length_and_angle(false)
		bone.set_length((to - from).length())
		bone.set_bone_angle((to - from).angle())
		parent.add_child(bone)
		bone.rest = bone.transform
		bones[bone.name] = bone
	# Mesh: grid cells that contain any visible pixel.
	var img: Image = tex.get_image()
	if img.is_compressed():
		img.decompress()
	var cell := maxi(int(round(float(spec.get("mesh_cell_px", 36)) * tex_scale)), 6)
	var w := img.get_width()
	var h := img.get_height()
	var nx := int(ceil(float(w) / cell))
	var ny := int(ceil(float(h) / cell))
	var index := {}
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var polys: Array = []
	var feet_tex := _v(spec.get("feet_px", [0, 0])) * tex_scale
	for gy in ny:
		for gx in nx:
			var r := Rect2i(gx * cell, gy * cell, mini(cell, w - gx * cell), mini(cell, h - gy * cell))
			if img.get_region(r).is_invisible():
				continue
			var quad := PackedInt32Array()
			for corner in [Vector2i(gx, gy), Vector2i(gx + 1, gy), Vector2i(gx + 1, gy + 1), Vector2i(gx, gy + 1)]:
				if not index.has(corner):
					var uv := Vector2(mini(corner.x * cell, w), mini(corner.y * cell, h))
					index[corner] = verts.size()
					verts.append(uv - feet_tex)
					uvs.append(uv)
				quad.append(int(index[corner]))
			polys.append(PackedInt32Array([quad[0], quad[1], quad[2]]))
			polys.append(PackedInt32Array([quad[0], quad[2], quad[3]]))
	poly = Polygon2D.new()
	poly.name = "Body"
	poly.texture = tex
	poly.polygon = verts
	poly.uv = uvs
	poly.polygons = polys
	poly.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	rig.add_child(poly)
	rig.move_child(poly, 0)
	poly.skeleton = poly.get_path_to(skeleton)
	_skin(verts)


## Weights from the data regions: tail (right part), head (upper part), ears (above the ear line,
## left/right), body (the rest); inside the tail by inverse 4th power of the distance to each link.
func _skin(verts: PackedVector2Array) -> void:
	var reg: Dictionary = spec.get("regions", {})
	var tx: Array = reg.get("tail_x", [690, 760])
	var hy: Array = reg.get("head_y", [600, 520])
	var ey: Array = reg.get("ear_y", [330, 265])
	var split_x := float(reg.get("ear_split_x", 470))
	var tails: Array = []
	for b in spec.get("bones", []):
		if String(b["name"]).begins_with("tail"):
			tails.append(b)
	var weights := {}
	for name in bones.keys():
		weights[name] = PackedFloat32Array()
		weights[name].resize(verts.size())
	var feet := _v(spec.get("feet_px", [0, 0]))
	for i in verts.size():
		var p: Vector2 = verts[i] / tex_scale + feet   # back to source px
		var t_tail := smoothstep(float(tx[0]), float(tx[1]), p.x)
		var t_head := smoothstep(float(hy[0]), float(hy[1]), p.y) * (1.0 - t_tail)
		var t_ear := smoothstep(float(ey[0]), float(ey[1]), p.y) * t_head
		t_head -= t_ear
		var t_body := maxf(0.0, 1.0 - t_tail - t_head - t_ear)
		weights["body"][i] = t_body
		weights["head"][i] = t_head
		weights["ear_l" if p.x < split_x else "ear_r"][i] = t_ear
		if t_tail > 0.0:
			var ws: Array = []
			var sum := 0.0
			for b in tails:
				var d := Geometry2D.get_closest_point_to_segment(p, _v(b["from"]), _v(b["to"])).distance_to(p)
				var wv := 1.0 / pow(1.0 + d / 60.0, 4.0)
				ws.append(wv)
				sum += wv
			for k in tails.size():
				weights[String(tails[k]["name"])][i] = t_tail * float(ws[k]) / maxf(sum, 0.000001)
	for name in bones.keys():
		poly.add_bone(skeleton.get_path_to(bones[name]), weights[name])


func _place(room: Node, h: Node2D) -> void:
	var rid := String(room.get("room_id")) if room != null else ""
	var pl: Dictionary = spec.get("place", {}).get(rid, {})
	var feet: Vector2
	if pl.has("feet"):
		feet = _v(pl["feet"])
	else:
		var size := Vector2.ZERO
		var shape := h.get_node_or_null("Shape")
		if shape is CollisionShape2D and shape.shape is RectangleShape2D:
			size = shape.shape.size
		feet = h.global_position + Vector2(0, size.y / 2)
	depth_y = float(pl.get("depth_y", feet.y))
	global_position = feet
	var depth := 1.0
	if room != null and room.has_method("depth_scale"):
		depth = room.depth_scale(depth_y)
	# Agata's figure height in px at scale 1 (her actor data), × the share for this character.
	var agata = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/agata.json"))
	var agata_h: float = float(agata.get("figure_height_px", 337.0)) if typeof(agata) == TYPE_DICTIONARY else 337.0
	var fig_src := float(spec.get("feet_px", [0, 0])[1]) - float(spec.get("figure_top_px", 0))
	var target_h := float(spec.get("height_rel_agata", 0.28)) * agata_h * depth
	var s := target_h / maxf(fig_src * tex_scale, 1.0)
	scale = Vector2(s, s)
	z_index = clampi(int(depth_y), -4096, 4096)


## Screen height of the figure (feet to ear tips), px.
func figure_height_px() -> float:
	var fig_src := float(spec.get("feet_px", [0, 0])[1]) - float(spec.get("figure_top_px", 0))
	return fig_src * tex_scale * absf(scale.y)


func _build_shadow() -> void:
	var sh: Dictionary = spec.get("shadow", {})
	var fig_w := float(spec.get("feet_px", [0, 0])[1]) * float(sh.get("width_rel", 0.6)) * tex_scale
	var node := ActorShadow.make_size(fig_w, float(sh.get("height_ratio", 0.3)), float(sh.get("alpha", 0.45)))
	add_child(node)
	move_child(node, 0)


# --- Animations ----------------------------------------------------------------

func _build_animations() -> void:
	var a: Dictionary = spec.get("anim", {})
	life = AnimationPlayer.new()
	life.name = "Life"
	add_child(life)
	accent = AnimationPlayer.new()
	accent.name = "Accent"
	add_child(accent)
	var lib_life := AnimationLibrary.new()
	var lib_acc := AnimationLibrary.new()
	# Idle loop: breathing (body scale) and a tail wave, one common period so the loop has no seam.
	var bp := float(a.get("breath_period_s", 3.2))
	var tp := float(a.get("tail_period_s", 4.8))
	var period := _common_period(bp, tp)
	var idle := Animation.new()
	idle.length = period
	idle.loop_mode = Animation.LOOP_LINEAR
	var steps := int(round(period / 0.1))
	var tb := idle.add_track(Animation.TYPE_VALUE)
	idle.track_set_path(tb, "%s:scale" % get_path_to(bones["body"]))
	var bs := float(a.get("breath_scale", 0.02))
	for i in steps + 1:
		var t := period * float(i) / float(steps)
		var k := 0.5 - 0.5 * cos(TAU * t / bp)
		idle.track_insert_key(tb, t, Vector2(1.0 + bs * 0.25 * k, 1.0 + bs * k))
	var amps: Array = a.get("tail_amp_deg", [2.5, 4.0, 6.0, 8.0])
	var ph := float(a.get("tail_phase_rad", 0.7))
	var n := 0
	for name in ["tail1", "tail2", "tail3", "tail4"]:
		if not bones.has(name):
			continue
		var tr := idle.add_track(Animation.TYPE_VALUE)
		idle.track_set_path(tr, "%s:rotation" % get_path_to(bones[name]))
		var rest_rot: float = bones[name].rest.get_rotation()
		var amp := deg_to_rad(float(amps[mini(n, amps.size() - 1)]))
		for i in steps + 1:
			var t := period * float(i) / float(steps)
			idle.track_insert_key(tr, t, rest_rot + amp * sin(TAU * t / tp - ph * n))
		n += 1
	lib_life.add_animation("idle", idle)
	life.add_animation_library("", lib_life)
	# Accents (head, ears; tail only in "scared"): one-shots that start and end on the rest pose.
	var ear := deg_to_rad(float(a.get("ear_twitch_deg", 14.0)))
	lib_acc.add_animation("ear_twitch_l", _pulse("ear_l", "rotation", bones["ear_l"].rest.get_rotation(), -ear, 0.35))
	lib_acc.add_animation("ear_twitch_r", _pulse("ear_r", "rotation", bones["ear_r"].rest.get_rotation(), ear, 0.35))
	lib_acc.add_animation("head_tilt", _pulse("head", "rotation", bones["head"].rest.get_rotation(), deg_to_rad(float(a.get("head_tilt_deg", 5.0))), 2.6, 0.5))
	var lift := Animation.new()
	lift.length = 0.45
	var lt := lift.add_track(Animation.TYPE_VALUE)
	lift.track_set_path(lt, "%s:rotation" % get_path_to(bones["head"]))
	var hr: float = bones["head"].rest.get_rotation()
	lift.track_insert_key(lt, 0.0, hr)
	lift.track_insert_key(lt, 0.45, hr + deg_to_rad(float(a.get("talk_lift_deg", -6.0))))
	lift.track_set_interpolation_type(lt, Animation.INTERPOLATION_CUBIC)
	lib_acc.add_animation("talk_lift", lift)
	var sc := Animation.new()
	sc.length = 0.5
	n = 0
	for name in ["tail1", "tail2", "tail3", "tail4"]:
		if not bones.has(name):
			continue
		var r0: float = bones[name].rest.get_rotation()
		var rot := sc.add_track(Animation.TYPE_VALUE)
		sc.track_set_path(rot, "%s:rotation" % get_path_to(bones[name]))
		sc.track_insert_key(rot, 0.0, r0)
		sc.track_insert_key(rot, 0.5, r0 - deg_to_rad(10.0 + 6.0 * n))   # tail up
		var scl := sc.add_track(Animation.TYPE_VALUE)
		sc.track_set_path(scl, "%s:scale" % get_path_to(bones[name]))
		sc.track_insert_key(scl, 0.0, Vector2.ONE)
		sc.track_insert_key(scl, 0.5, Vector2(1.0, 1.35))   # fluffed across the tail
		n += 1
	lib_acc.add_animation("scared", sc)
	accent.add_animation_library("", lib_acc)


## Rest → rest + delta (held) → rest over `length` seconds (start and end on the rest pose).
func _pulse(bone: String, prop: String, rest_v: float, delta: float, length: float, hold: float = 0.0) -> Animation:
	var an := Animation.new()
	an.length = length
	var tr := an.add_track(Animation.TYPE_VALUE)
	an.track_set_path(tr, "%s:%s" % [get_path_to(bones[bone]), prop])
	var rise := (length - hold) * 0.4
	an.track_insert_key(tr, 0.0, rest_v)
	an.track_insert_key(tr, rise, rest_v + delta)
	an.track_insert_key(tr, rise + hold, rest_v + delta)
	an.track_insert_key(tr, length, rest_v)
	an.track_set_interpolation_type(tr, Animation.INTERPOLATION_CUBIC)
	return an


static func _common_period(a: float, b: float) -> float:
	for k in range(1, 9):
		var t := a * k
		if absf(t / b - round(t / b)) < 0.02:
			return t
	return a * b


# --- Behaviour -------------------------------------------------------------------

func _process(delta: float) -> void:
	_update_tone(delta)
	if not visible or talking or scared or accent.is_playing():
		return
	_next_accent -= delta
	if _next_accent > 0.0:
		return
	var a: Dictionary = spec.get("anim", {})
	var every: Array = a.get("accent_every_s", [5.0, 12.0])
	_next_accent = _rng.randf_range(float(every[0]), float(every[1]))
	if _rng.randf() < float(a.get("head_tilt_share", 0.3)):
		accent.play("head_tilt")
	else:
		accent.play("ear_twitch_l" if _rng.randf() < 0.5 else "ear_twitch_r")


## His own line → lifts the head (and keeps it up while he speaks); anything else → back down.
func _on_beat_changed() -> void:
	var b: Dictionary = StoryRunner.current_beat
	var mine: bool = String(b.get("type", "")) == "line" and String(b.get("speaker", "")) == actor_id
	if mine and not talking:
		talking = true
		accent.stop()
		accent.play("talk_lift")
	elif not mine and talking:
		talking = false
		accent.play_backwards("talk_lift")


## Future scenes: the tail goes up and fluffs (and settles back with calm()).
func play_scared() -> void:
	scared = true
	accent.stop()
	accent.play("scared")


func calm() -> void:
	if scared:
		scared = false
		accent.play_backwards("scared")


func _update_tone(delta: float) -> void:
	var rl: Node = null
	if _room != null and is_instance_valid(_room):
		for c in _room.get_children():
			if c.has_method("actor_tone_at"):
				rl = c
				break
	if rl == null:
		return
	var target: Color = rl.call("actor_tone_at", global_position, figure_height_px())
	if not _tone_set:
		_tone = target
		_tone_set = true
	else:
		_tone = _tone.lerp(target, 1.0 - exp(-delta * TONE_RATE))
	poly.self_modulate = _tone
