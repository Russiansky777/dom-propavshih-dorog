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
var talking: bool = false


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
	direction = sheet.direction_index(ActorSheet.facing_vector(sheet.facing))
	visible = h.visible
	h.visibility_changed.connect(func(): visible = hotspot.visible)
	StoryRunner.beat_changed.connect(_on_beat_changed)
	_play_idle()
	return true


func _exit_tree() -> void:
	if StoryRunner.beat_changed.is_connected(_on_beat_changed):
		StoryRunner.beat_changed.disconnect(_on_beat_changed)


func face_towards(target: Vector2) -> void:
	var v := target - global_position
	if v.length_squared() > 1.0:
		direction = sheet.direction_index(v)


func _play_idle() -> void:
	talking = false
	_play(sheet.anim_name(sheet.idle_action, direction))


func _play_talk() -> void:
	talking = true
	if sheet.has_action(sheet.talk_action):
		_play(sheet.anim_name(sheet.talk_action, direction))
	else:
		_play(sheet.anim_name(sheet.idle_action, direction))


## Switches animation with a short cross-fade from the current pose (no jump between clips).
func _play(anim: String) -> void:
	if sprite.animation != anim and sprite.is_playing():
		ActorCrossfade.begin(sprite, sheet.crossfade_s)
	sprite.play(anim)


## A line of this character → talk (facing the player); anything else → idle.
func _on_beat_changed() -> void:
	var b: Dictionary = StoryRunner.current_beat
	var mine: bool = String(b.get("type", "")) == "line" and String(b.get("speaker", "")) == actor_id
	if mine:
		if player != null and is_instance_valid(player):
			face_towards(player.global_position)
		if not talking or not sprite.animation.begins_with(sheet.talk_action):
			_play_talk()
	elif talking:
		_play_idle()
