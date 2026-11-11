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
var _said_check_t: float = 0.0
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
	# K (стр. 12): the line said, still on screen — the idle stance, facing kept (no turn back as in idle)
	"quiet": {"action": "", "speed": 1.0, "face_agata": false},
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
## Director 30.10: the villager drawn live (NpcLive3D, actor data `rt3d` + `render` "3d") — null on sheets.
var live: NpcLive3D = null
var held: HeldProp = null   # 02.11 (стр. 21): rooms data `held` — a thing in the villager's hand
var action_props: Array = []   # block 3: HeldProp per thing in hand of a one-shot action (actor data rt3d.props)
var worn_props: Array = []     # 09.11: HeldProp per thing worn on the body (rooms data `worn`)
var _floor_k: float = ActorSheet.FLOOR_FORESHORTENING_DEFAULT


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
	# K (стр. 16): a villager drawn live needs the sheet for placement only — its pages are not read (a room change
	# loaded ~150 MB of PNG per villager to draw it invisible); if the model then fails, the full sheet is loaded.
	var aspec = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/%s.json" % id))
	var live_wanted: bool = aspec is Dictionary and NpcLive3D.wanted(aspec)
	sheet = ActorSheet.load_actor(id, {}, not live_wanted)
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
	var hd: Dictionary = h.data if h.data is Dictionary else {}
	# A figure in a frame (Director 05.11, block 2: the frames' figures live, not pictures): `feet` [x, y] — where the
	# feet stand, `figure_h` — the figure's height on screen (px), as the frame's composition had them; the frame's
	# own room depth is not the shot's camera.
	if hd.get("feet", null) is Array and (hd["feet"] as Array).size() >= 2:
		global_position = Vector2(float(hd["feet"][0]), float(hd["feet"][1])) + sheet.feet_offset
	var s := 1.0
	if room.has_method("depth_scale_at"):
		s = room.depth_scale_at(global_position)
	s *= sheet.scale_factor
	if hd.has("figure_h") and sheet.figure_height_px > 1.0:
		s = float(hd["figure_h"]) / sheet.figure_height_px
	scale = Vector2(s, s)
	z_index = clampi(int(global_position.y), -4096, 4096)
	var img := h.get_node_or_null("Image")
	if img != null:
		img.visible = false  # the sheet replaces the static front view
	_load_states(id)
	direction = sheet.direction_index(ActorSheet.facing_vector(sheet.facing))
	var rid := String(room.get("room_id")) if room.get("room_id") != null else ""
	if rid != "" and StoryData.rooms.has(rid):
		_floor_k = float(StoryData.rooms[rid].get("floor_foreshortening", ActorSheet.FLOOR_FORESHORTENING_DEFAULT))
	if live_wanted:
		live = NpcLive3D.new()
		live.name = "Live3D"
		add_child(live)
		if live.setup(self, aspec, _floor_k):
			live.face(ActorSheet.facing_vector(sheet.facing), _floor_k, true)
		else:
			live.queue_free()
			live = null
	# 02.11 (стр. 21): a thing carried in the hand (rooms data `held` on the hotspot — Mitya's lantern)
	if h.data is Dictionary and (h.data as Dictionary).has("held"):
		held = HeldProp.attach(self, h.data["held"])
	# 09.11 (Director 13:36 «повесь на бедро, как-то красиво»): a thing worn on the body (rooms data `worn`, HeldProp
	# grip "body" — Tamara's mail bag on her hip on the bridge)
	if h.data is Dictionary and (h.data as Dictionary).has("worn"):
		var wspec: Dictionary = (h.data["worn"] as Dictionary).duplicate()
		wspec["grip"] = "body"
		worn_props.append(HeldProp.attach(self, wspec))
	# block 3: a villager busy with something the whole time the room or frame is shown (rooms data `act` on the
	# hotspot {clip, loop, hold_at, start}: the epilogue's tarring, the postwoman's bag) — from `start` (share of the clip)
	if live != null and h.data is Dictionary and (h.data as Dictionary).has("act"):
		var ad: Dictionary = h.data["act"]
		if live.play_once(String(ad.get("clip", "")), bool(ad.get("hold", false)), float(ad.get("hold_at", -1.0)), bool(ad.get("loop", true))):
			live.act_t = float(ad.get("start", 0.0)) * live.view.action_length(String(ad.get("clip", "")))
	# block 3: things in hand during the villager's one-shot actions (actor data rt3d.props {clip: [spec]})
	var props: Dictionary = ((aspec.get("rt3d", {}) as Dictionary).get("props", {}) as Dictionary) if aspec is Dictionary else {}
	for clip in props.keys():
		if String(clip).begins_with("_"):
			continue
		for ps in props[clip]:
			var spec2: Dictionary = (ps as Dictionary).duplicate()
			spec2["during"] = String(clip)
			action_props.append(HeldProp.attach(self, spec2))
	if live == null and not sheet.textures_loaded:
		sheet = ActorSheet.load_actor(id)
		sprite.sprite_frames = sheet.frames
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
## A point a staging turned the villager to (StoryRunner npc_face [x, y], 11.11): kept through the lines after it — a
## narrator's line between no longer turns her back to her data facing (M17: Pelageya watched the boat at «Течение
## повело лодку» for a moment, then turned back to Agata while the boat went off). Cleared at the scene's end and by a
## turn to a person. INF — none.
var face_hold := Vector2.INF


func hold_face(at: Vector2) -> void:
	face_hold = at
	if not StoryRunner.scene_completed.is_connected(_on_scene_done):
		StoryRunner.scene_completed.connect(_on_scene_done)


func _on_scene_done(_id: String) -> void:
	face_hold = Vector2.INF


func _face_data() -> void:
	if face_hold != Vector2.INF:
		face_towards(face_hold)
		return
	if hotspot == null or not is_instance_valid(hotspot):
		return
	# Director 09.11, 12:35 («Тамара развернута к нам… Павел на финале тоже развернут непонятно как, Пелагея тоже»):
	# `face_dir` — the facing of the painted figure the frame had before its live 3D figure (layers compose `dir` of the
	# v2 sheets: 0 towards the viewer, then clockwise on screen — 2 left, 4 away, 6 right), so the figure stands turned
	# exactly as in the accepted frame, not as a point picked by eye
	if hotspot.data.has("face_dir"):
		var yaw := deg_to_rad(-45.0 * float(hotspot.data["face_dir"]))
		var k := maxf(_floor_k, 0.05)
		face_towards(global_position + Vector2(sin(yaw), cos(yaw) * k) * 200.0)
		return
	var f: Array = hotspot.current_state().get("face", hotspot.data.get("face", []))
	if f.size() >= 2:
		face_towards(Vector2(float(f[0]), float(f[1])))


var last_face_target := Vector2.INF   # where the villager last turned to (tests)


func face_towards(target: Vector2) -> void:
	last_face_target = target
	var v := target - global_position
	if v.length_squared() > 1.0:
		direction = sheet.direction_index(v)
		if live != null:
			live.face(v, _floor_k)


func _end_walk() -> void:
	walking = false
	if live != null:
		live.walk(false)
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
	if live != null and live.view != null and live.view.clips.has("walk"):
		# live: every villager model has a walk clip — she walks there at the staging's pace, whatever the sheets have
		walking = true
		live.walk(true, global_position.distance_to(target) / maxf(seconds, 0.01), scale.x)
		tw.tween_property(self, "global_position", target, seconds)
		get_tree().create_timer(seconds, false).timeout.connect(_end_walk)   # ревью 01.11 (В-2): waits through a pause, like the tween
	elif walks_off():
		walking = true
		shown_dir = direction
		var speed_px := global_position.distance_to(target) / maxf(seconds, 0.01)
		_play(sheet.anim_name(sheet.walk_action, shown_dir))
		sprite.speed_scale = sheet.walk_fps(speed_px, scale.x) / maxf(float(sheet.actions[sheet.walk_action].get("fps", 24)), 0.01)
		tw.tween_property(self, "global_position", target, seconds)
		get_tree().create_timer(seconds, false).timeout.connect(_end_walk)
	else:
		tw.tween_property(self, "global_position", target, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if room != null and room.has_method("depth_scale_at") and sheet != null:
		var s: float = room.depth_scale_at(target) * sheet.scale_factor
		tw.tween_property(self, "scale", Vector2(s, s), seconds)
	if fade:
		# I-T2 (Director, line 140: «Нина уходит в дверь, не растворяется»): she walks the whole way and only
		# at the door goes out of sight — the fade is the last fifth of the walk, not its second half.
		tw.tween_property(self, "modulate:a", 0.0, seconds * 0.2).set_delay(seconds * 0.8)
	return seconds


func _process(delta: float) -> void:
	if live != null:
		live.process(delta)
	# the voice of the line ends while it is still on screen (K, стр. 12): the hands come to rest then
	if (state == "talk" or state == "listen") and not StoryRunner.current_beat.is_empty():
		_said_check_t += delta
		if _said_check_t >= 0.1:
			_said_check_t = 0.0
			_on_beat_changed()
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
	var bface = StoryRunner.current_beat.get("face", null)
	var own_point: bool = st == "talk" and bface is Array and (bface as Array).size() >= 2 and String(StoryRunner.current_beat.get("speaker", "")) == actor_id
	if st == "talk" and not own_point:
		face_hold = Vector2.INF   # she speaks to someone: the held point (the boat) is over
	if face_hold != Vector2.INF and st != "talk":
		# 11.11 (R-21): listening — the narrator's line, Agata's — she keeps to the point a staging turned her to
		face_towards(face_hold)
	elif own_point:
		# 01.11 (Director, стр. 51: «Илью зовёт Митя, но повёрнут к маминому дому»): a line with `face` [x, y] is called
		# to that point (Ilya's shutter), not said to Agata
		face_towards(Vector2(float(bface[0]), float(bface[1])))
	elif partner != null and is_instance_valid(partner) and not (st == "talk" and _line_to_agata()):
		face_towards(partner.global_position)
	elif st == "listen" and hotspot != null and is_instance_valid(hotspot) and bool(hotspot.current_state().get("listen_keeps_face", hotspot.data.get("listen_keeps_face", false))):
		# 01.11 (стр. 51): rooms data `listen_keeps_face` — listening, the villager keeps to his own `face` (Mitya at Ilya's
		# shutter while the narrator tells of his knocking), not turning to Agata
		_face_data()
	elif bool(spec.get("face_agata", st == "talk")) and player != null and is_instance_valid(player):
		# J (Director 29.10, стр. 157: «не смотрят на собеседника»): talking, a person turns to Agata unless the data
		# says otherwise (`face_agata: false`) or they talk to someone else (partner, above)
		face_towards(player.global_position)
	elif st == "idle":
		_face_data()
	_play(sheet.anim_name(state_action(st), shown_dir))
	sprite.speed_scale = float(spec.get("speed", 1.0))
	if live != null:
		live.set_state(st)


## Block 3 (Director 05.11: villagers do what the story says): a one-shot clip of the live model (rt3d.clips role) —
## from the stance into the action and back; `hold` keeps the last pose until `release_action`. Returns its seconds
## (0 — drawn from sheets or no such clip: the staging goes on without it).
## The next action's arm lowered or raised (stage data npc_act[].arm — NpcLive3D.set_act_arm); nothing on sheets.
func act_arm(d: Dictionary, role: String) -> void:
	if live != null:
		live.set_act_arm(d, role)


## 10.11 (the windlass's crank): a hand of the live figure held at a point of the screen (NpcLive3D.hold_hand_at);
## nothing on sheets.
func hold_hand_at(side: String, screen: Vector2, weight: float, helps: bool = false) -> void:
	if live != null:
		live.hold_hand_at(side, screen, weight, helps)


func play_action(role: String, hold: bool = false, hold_at: float = -1.0, loop: bool = false) -> float:
	if live == null or not live.play_once(role, hold, hold_at, loop):
		return 0.0
	var L: float = live.view.action_length(role) / maxf(float(live.rt.get("act_speed", 1.0)), 0.05)
	return L * clampf(hold_at, 0.0, 1.0) if hold_at >= 0.0 else L


func release_action(at_share: float = -1.0) -> void:
	if live != null:
		live.release_once(at_share)


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


## The state the current beat asks for. K (Director 31.10, стр. 12: «анимации при разговорах циклично идут, даже если
## уже все закончили говорить»): talk and listen last while the line is being said (VoiceDirector.line_being_said —
## its recording, or the time to say it); after that, till the click, the speaker and the listeners stand quiet —
## the idle stance, still facing whom they spoke to (state "quiet": no turn back to the rest facing as in idle).
func wanted_state() -> String:
	var b: Dictionary = StoryRunner.current_beat
	var is_line: bool = String(b.get("type", "")) == "line"
	var said := _being_said(b)
	if is_line and String(b.get("speaker", "")) == actor_id:
		return "talk" if said else "quiet"
	if not b.is_empty() and in_active_scene():
		return "listen" if said else "quiet"
	return "idle"


func _being_said(b: Dictionary) -> bool:
	var vd := get_node_or_null("/root/VoiceDirector")
	return vd == null or bool(vd.call("line_being_said", b))


## A line of this character → talk (facing the player); a scene with them, someone else speaking → listen;
## anything else → idle.
func _on_beat_changed() -> void:
	if walking or (live != null and live.once_busy()):
		return   # block 3: a one-shot action (play_action) plays out — or is held — through the lines
	var want := wanted_state()
	if want != state or (want == "talk" and not sprite.animation.begins_with(state_action("talk"))):
		set_state(want)
