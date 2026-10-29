class_name NpcActor
extends Node2D
## Animated non-player character standing at an `npc` hotspot of a data-driven room.
##
## RoomManager calls `attach_all(room, player)` after a room is built: every hotspot of kind "npc"
## whose id has `data/actors/<id>.json` gets an NpcActor (sheets through ActorSheet, like Agata).
## The figure's feet sit at the bottom centre of the hotspot rect (+ `npc.feet_offset`), the scale is
## the room's depth scale at the feet × `npc.scale_factor`, z_index = int(y) so it y-sorts with the
## player and the occluders. It idles (pingpong idle sheet) and plays `talk` while a dialogue line
## of this character is on screen, facing the player for the conversation. The hotspot itself keeps
## handling clicks and labels; its static `image` (if any) is hidden.

var actor_id: String = ""
var sheet: ActorSheet = null
var sprite: AnimatedSprite2D = null
var hotspot: StoryHotspot = null
var player: Node2D = null
var direction: int = 0
## F22 (23.10): the row on screen turns to `direction` through the neighbouring rows, one every TURN_STEP_S
## (as Agata), the idle/talk animation going on — no flip when the NPC turns to face Agata.
var shown_dir: int = 0
var _turn_t: float = 0.0
var talking: bool = false
## I-T4: walking off in a staging (go_off with a walk sheet) — beats do not switch the clip meanwhile.
var walking: bool = false
## I-T2 (Director 02:34): three states of every villager — "idle" (just stands: breathing, rare small
## moves), "listen" (turned to Agata, quiet: a scene with this villager is on and someone else speaks),
## "talk" (gesture/head while their own line is up). Per actor data `states.<state>` = {action, speed,
## face_agata}: a new model (I-T4) just names its own clips; missing clips fall back to idle.
var state: String = "idle"
const DEFAULT_STATES: Dictionary = {
	"idle": {"action": "", "speed": 1.0, "face_agata": false},
	"listen": {"action": "listen", "speed": 0.6, "face_agata": true},
	"talk": {"action": "", "speed": 1.0, "face_agata": true},
}
var states: Dictionary = {}
## I-T2 (Director 25.10 14:07: «повороты — с человеческой скоростью»): 180° in `turn.seconds_180` of the actor data
## (default DEFAULT_TURN_180), each row change a short cross-fade `turn.blend_s` — as Agata, never a snap.
const DEFAULT_TURN_180: float = 0.36
const DEFAULT_TURN_BLEND: float = 0.08
var turn_step_s: float = Player.TURN_STEP_S
var turn_blend_s: float = DEFAULT_TURN_BLEND
## I-T2 (Director, lines 128–129): a staging can turn a villager to another one (npc_go[].face: "<id>" — Pelageya
## hugging Mitya): idle and listen then face the partner, not Agata; a line of theirs marked `"to": "agata"` still
## turns them to her. Cleared with the room (the node is rebuilt on the next entry).
var partner: Node2D = null


static func attach_all(room: Node, the_player: Node2D) -> Array:
	var made: Array = []
	if room == null or not room.has_method("get_hotspots"):
		return made
	for h in room.get_hotspots():
		if not (h is StoryHotspot) or h.kind() != "npc":
			continue
		var id: String = h.hotspot_id
		if not FileAccess.file_exists("res://data/actors/%s.json" % id):
			continue
		var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/%s.json" % id))
		if typeof(spec) == TYPE_DICTIONARY and String(spec.get("type", "")) == "puppet":
			# One-picture bone rig (Tikhon): its own actor class, same placement/visibility contract.
			var pup := PuppetActor.new()
			pup.name = "puppet_" + id
			room.add_child(pup)
			if pup.setup(id, h, room, the_player):
				made.append(pup)
			else:
				room.remove_child(pup)
				pup.free()
			continue
		var npc := NpcActor.new()
		npc.name = "npc_" + id
		room.add_child(npc)
		if npc.setup(id, h, room, the_player):
			made.append(npc)
		else:
			room.remove_child(npc)
			npc.free()
	return made


static func all_in(room: Node) -> Array:
	var out: Array = []
	if room == null:
		return out
	for c in room.get_children():
		if c is NpcActor:
			out.append(c)
	return out


func setup(id: String, h: StoryHotspot, room: Node, the_player: Node2D) -> bool:
	actor_id = id
	hotspot = h
	player = the_player
	sheet = ActorSheet.load_actor(id)
	if sheet == null or not sheet.is_loaded():
		push_warning("NpcActor: sheet for '%s' not loaded (%s)" % [id, sheet.load_error if sheet else "?"])
		return false
	sprite = AnimatedSprite2D.new()
	sprite.name = "Sprite"
	sprite.centered = false
	sprite.offset = sheet.sprite_offset()
	sprite.sprite_frames = sheet.frames
	sprite.scale = sheet.sprite_scale()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(sprite)
	if sheet.shadow_alpha > 0.0:
		sprite.add_child(ActorShadow.make(sheet))
	# Feet at the bottom centre of the hotspot rect.
	var size := Vector2.ZERO
	var shape := h.get_node_or_null("Shape")
	if shape is CollisionShape2D and shape.shape is RectangleShape2D:
		size = shape.shape.size
	global_position = h.global_position + Vector2(0, size.y / 2) + sheet.feet_offset
	var s := 1.0
	if room.has_method("depth_scale"):
		s = room.depth_scale(global_position.y)
	s *= sheet.scale_factor
	scale = Vector2(s, s)
	z_index = clampi(int(global_position.y), -4096, 4096)
	var img := h.get_node_or_null("Image")
	if img != null:
		img.visible = false  # the sheet replaces the static front view
	_load_states(id)
	direction = sheet.direction_index(ActorSheet.facing_vector(sheet.facing))
	_face_data()
	shown_dir = direction
	visible = h.visible
	h.visibility_changed.connect(func(): visible = hotspot.visible)
	StoryRunner.beat_changed.connect(_on_beat_changed)
	_play_idle()
	return true


func _exit_tree() -> void:
	if StoryRunner.beat_changed.is_connected(_on_beat_changed):
		StoryRunner.beat_changed.disconnect(_on_beat_changed)


## H28 (Director 24.10: Pavel at the office door looked right, away from it): rooms data `face` [x, y] on the hotspot
## or its current state — where the villager looks when not talking (the door he waits at).
func _face_data() -> void:
	if hotspot == null or not is_instance_valid(hotspot):
		return
	var f: Array = hotspot.current_state().get("face", hotspot.data.get("face", []))
	if f.size() >= 2:
		face_towards(Vector2(float(f[0]), float(f[1])))


func face_towards(target: Vector2) -> void:
	var v := target - global_position
	if v.length_squared() > 1.0:
		direction = sheet.direction_index(v)


func _end_walk() -> void:
	walking = false
	if is_instance_valid(sprite):
		set_state(wanted_state())


func walks_off() -> bool:
	return sheet != null and sheet.has_action(sheet.walk_action) and sprite != null


## A villager walks off in a staging (scenes data stage[].npc_go — G18: Pavel «Иди за мной» to the passage door; G29:
## Nina from her porch into the house): the villagers have idle and talk sheets only (no walk cycle), so the figure
## turns to the door, eases there — growing or shrinking with the room depth — and fades out in the second half,
## instead of vanishing in a cut. Returns its seconds (the staging waits for them before its fade).
## I-T4: a villager whose sheet has a walk cycle (models v2: Nina, Ilya, Ulyana, Pelageya, Tamara) walks there at an
## even pace instead — the cycle's cadence follows the speed (ActorSheet.walk_fps), so the feet do not slide.
func go_off(target: Vector2, seconds: float, fade: bool, room: Node) -> float:
	face_towards(target)
	var tw := create_tween().set_parallel(true)
	if walks_off():
		walking = true
		shown_dir = direction
		var speed_px := global_position.distance_to(target) / maxf(seconds, 0.01)
		_play(sheet.anim_name(sheet.walk_action, shown_dir))
		sprite.speed_scale = sheet.walk_fps(speed_px, scale.x) / maxf(float(sheet.actions[sheet.walk_action].get("fps", 24)), 0.01)
		tw.tween_property(self, "global_position", target, seconds)
		get_tree().create_timer(seconds).timeout.connect(_end_walk)
	else:
		tw.tween_property(self, "global_position", target, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if room != null and room.has_method("depth_scale") and sheet != null:
		var s: float = room.depth_scale(target.y) * sheet.scale_factor
		tw.tween_property(self, "scale", Vector2(s, s), seconds)
	if fade:
		# I-T2 (Director, line 140: «Нина уходит в дверь, не растворяется»): she walks the whole way and only
		# at the door goes out of sight — the fade is the last fifth of the walk, not its second half.
		tw.tween_property(self, "modulate:a", 0.0, seconds * 0.2).set_delay(seconds * 0.8)
	return seconds


func _process(delta: float) -> void:
	if sheet == null or sprite == null or shown_dir == direction:
		_turn_t = 0.0
		return
	_turn_t += delta
	if _turn_t >= turn_step_s:
		_turn_t = minf(_turn_t - turn_step_s, turn_step_s)  # one row per step, never two in a frame
		shown_dir = ActorSheet.step_toward(shown_dir, direction, sheet.directions)
		var cur := String(sprite.animation)
		var cut := cur.rfind("_")
		var anim := sheet.anim_name(cur.substr(0, cut) if cut > 0 else sheet.idle_action, shown_dir)
		if anim != cur and sprite.sprite_frames.has_animation(anim):
			var f := sprite.frame
			var pr := sprite.frame_progress
			if turn_blend_s > 0.0:
				ActorCrossfade.begin(sprite, turn_blend_s)  # the pose of the old row melts into the new one
			sprite.play(anim)  # a turn step: same frame on the next row
			if sprite.sprite_frames.get_frame_count(anim) > f:
				sprite.set_frame_and_progress(f, pr)


func _load_states(id: String) -> void:
	var spec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/%s.json" % id))
	var data: Dictionary = (spec.get("states", {}) if spec is Dictionary else {})
	var tn: Dictionary = (spec.get("turn", {}) if spec is Dictionary else {})
	turn_step_s = maxf(float(tn.get("seconds_180", DEFAULT_TURN_180)) / maxf(float(sheet.directions) * 0.5, 1.0), 0.02)
	turn_blend_s = float(tn.get("blend_s", DEFAULT_TURN_BLEND))
	for st in DEFAULT_STATES.keys():
		var d: Dictionary = (DEFAULT_STATES[st] as Dictionary).duplicate()
		var over = data.get(st, {})
		if over is Dictionary:
			for k in over.keys():
				if not String(k).begins_with("_"):
					d[k] = over[k]
		states[st] = d


## The sheet action that plays in a state: the data clip if the sheet has it, else talk/idle.
func state_action(st: String) -> String:
	var want := String((states.get(st, {}) as Dictionary).get("action", ""))
	if want != "" and sheet.has_action(want):
		return want
	if st == "talk" and sheet.has_action(sheet.talk_action):
		return sheet.talk_action
	return sheet.idle_action


func set_state(st: String) -> void:
	state = st
	talking = st == "talk"
	var spec: Dictionary = states.get(st, {})
	if partner != null and is_instance_valid(partner) and not (st == "talk" and _line_to_agata()):
		face_towards(partner.global_position)
	elif bool(spec.get("face_agata", st == "talk")) and player != null and is_instance_valid(player):
		# J (Director 29.10, стр. 157: «не смотрят на собеседника»): talking, a person turns to Agata unless the data
		# says otherwise (`face_agata: false`) or they talk to someone else (partner, above)
		face_towards(player.global_position)
	elif st == "idle":
		_face_data()
	_play(sheet.anim_name(state_action(st), shown_dir))
	sprite.speed_scale = float(spec.get("speed", 1.0))


func _line_to_agata() -> bool:
	return String(StoryRunner.current_beat.get("to", "")) == "agata"


## npc_go[].face: turns to the partner and keeps to them (set_state reads it).
func set_partner(other: Node2D) -> void:
	partner = other
	if other != null:
		face_towards(other.global_position)


func _play_idle() -> void:
	set_state("idle")


func _play_talk() -> void:
	set_state("talk")


## Switches animation with a short cross-fade from the current pose (no jump between clips).
func _play(anim: String) -> void:
	if sprite.animation != anim and sprite.is_playing():
		ActorCrossfade.begin(sprite, sheet.crossfade_s)
	sprite.play(anim)


## True while a scene this villager speaks in is running (they listen when someone else has the line).
func in_active_scene() -> bool:
	var sid := String(StoryRunner.active_scene)
	if sid == "":
		return false
	for l in StoryData.scene(sid).get("mandatory_lines", []):
		if l is Dictionary and String(l.get("speaker", "")) == actor_id:
			return true
	return false


## The state the current beat asks for.
func wanted_state() -> String:
	var b: Dictionary = StoryRunner.current_beat
	var is_line: bool = String(b.get("type", "")) == "line"
	if is_line and String(b.get("speaker", "")) == actor_id:
		return "talk"
	if not b.is_empty() and in_active_scene():
		return "listen"
	return "idle"


## A line of this character → talk (facing the player); a scene with them, someone else speaking → listen;
## anything else → idle.
func _on_beat_changed() -> void:
	if walking:
		return
	var want := wanted_state()
	if want != state or (want == "talk" and not sprite.animation.begins_with(state_action("talk"))):
		set_state(want)
