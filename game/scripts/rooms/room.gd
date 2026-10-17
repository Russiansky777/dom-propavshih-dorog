class_name Room
extends Node2D
## Base class for every room scene (`res://scenes/rooms/<room_id>.tscn`).
##
## Expected children (all optional, looked up by name):
##   Background  - Sprite2D / placeholder
##   Walkable    - NavigationRegion2D with the floor polygon
##   Hotspots    - Area2D children (Hotspot) with `hotspot_id` and `interact` signal
##   Exits       - Area2D children (RoomExit) with `target_room` / `target_spawn`
##   Spawns      - Marker2D children; name == spawn id
##   Occluders   - Sprite2D/Polygon2D children drawn above the player (z_index = foot y)
##
## Flag-driven visuals are data: `flag_visibility` maps a node path (relative to the
## room) to a flag name; prefix `!` shows the node when the flag is false.

@export var room_id: String = ""
@export var room_name: String = ""
## Background pixels → screen pixels: 1920 / background width (set by RoomBuilder; 0 = no picture).
## Every layer and state of the room is drawn with this same scale.
var art_scale: float = 0.0

@export_group("Depth / perspective")
## Player y at the far edge of the floor (scale == scale_top there).
@export var depth_top_y: float = 640.0
## Player y at the near edge of the floor (scale == scale_bottom there).
@export var depth_bottom_y: float = 1070.0
@export var scale_top: float = 0.6
@export var scale_bottom: float = 1.1

@export_group("Flags")
## { "Hotspots/Door/DoorOpen": "office_latch_open", "Hotspots/Door/DoorClosed": "!office_latch_open" }
@export var flag_visibility: Dictionary = {}

func _ready() -> void:
	if not GameState.flag_changed.is_connected(_on_flag_changed):
		GameState.flag_changed.connect(_on_flag_changed)
	apply_flags()


func _on_flag_changed(_flag: String, _value: bool) -> void:
	apply_flags()


## Shows/hides mapped nodes according to the current flags. Safe to call any time.
func apply_flags() -> void:
	for key in flag_visibility.keys():
		var node := get_node_or_null(NodePath(String(key)))
		if node == null:
			push_warning("Room %s: flag_visibility path '%s' not found" % [room_id, key])
			continue
		var spec := String(flag_visibility[key])
		var negate := spec.begins_with("!")
		var flag := spec.trim_prefix("!")
		var visible_now := GameState.has_flag(flag) != negate
		if node is CanvasItem:
			node.visible = visible_now
		elif node is CollisionShape2D or node is CollisionPolygon2D:
			node.set_deferred("disabled", not visible_now)


# --- Lookups ---------------------------------------------------------------

func get_spawn(spawn_id: String) -> Marker2D:
	var spawns := get_node_or_null("Spawns")
	if spawns == null:
		return null
	var m := spawns.get_node_or_null(spawn_id)
	return m as Marker2D


func get_default_spawn() -> Marker2D:
	var spawns := get_node_or_null("Spawns")
	if spawns == null or spawns.get_child_count() == 0:
		return null
	return spawns.get_child(0) as Marker2D


func get_walkable() -> NavigationRegion2D:
	return get_node_or_null("Walkable") as NavigationRegion2D


func get_hotspots() -> Array[Hotspot]:
	var out: Array[Hotspot] = []
	var container := get_node_or_null("Hotspots")
	if container != null:
		for c in container.get_children():
			if c is Hotspot:
				out.append(c)
	return out


func get_exits() -> Array[RoomExit]:
	var out: Array[RoomExit] = []
	var container := get_node_or_null("Exits")
	if container != null:
		for c in container.get_children():
			if c is RoomExit:
				out.append(c)
	return out


# --- Depth -----------------------------------------------------------------

## 0 at depth_top_y, 1 at depth_bottom_y (clamped).
func depth_t(y: float) -> float:
	if is_equal_approx(depth_bottom_y, depth_top_y):
		return 1.0
	return clampf((y - depth_top_y) / (depth_bottom_y - depth_top_y), 0.0, 1.0)


func depth_scale(y: float) -> float:
	return lerpf(scale_top, scale_bottom, depth_t(y))


# --- Picking ---------------------------------------------------------------

## Returns the Hotspot or RoomExit under `world_pos`, or null. Uses the physics space,
## so areas must have been inside the tree for at least one physics frame.
func pick(world_pos: Vector2) -> Node2D:
	var space := get_world_2d().direct_space_state
	if space == null:
		return null
	var params := PhysicsPointQueryParameters2D.new()
	params.position = world_pos
	params.collide_with_areas = true
	params.collide_with_bodies = false
	var hits := space.intersect_point(params, 16)
	var best: Node2D = null
	var best_priority := -1
	for hit in hits:
		var collider = hit.get("collider")
		if collider is Hotspot or collider is RoomExit:
			var prio: int = int(collider.get("pick_priority"))
			if prio > best_priority:
				best = collider
				best_priority = prio
	return best
