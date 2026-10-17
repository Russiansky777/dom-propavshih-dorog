class_name AmbientBuilder
extends RefCounted
## «Живой мир» — entry point called by RoomBuilder.build() after the room layers exist (one line
## there). Builds the ambient layer of a room from data/story/ambient/<LOC>.json: drizzle, wind
## sway, water, puddles/mud with footfall, dust in window light. Nothing here takes input: only
## Polygon2D / Node2D / CPUParticles2D (test_ambient.gd checks it).
##
## Draw order (absolute z; the room background is at −10):
##   Z_GROUND  −9  sway regions, river, puddles — the picture itself, under layers/states/effects
##   Z_DECAL   −8  footprints and step rings on the floor
##   dust          per entry `z` (default 2, in the room air behind the actors)
##   drops         foot y + 1 (y-sorted with the actors, just over the boot)
##   Z_RAIN  4096  drizzle over everything in the room; the UI (CanvasLayer) stays above it

const Z_GROUND: int = -9
const Z_DECAL: int = -8
const Z_RAIN: int = 4096

## Off → rooms are built without the ambient layer (F2 in the F3 overlay, ?ambientprobe in the web build).
static var enabled: bool = true

## Effects quality, data/story/ambient/_index.json `quality.levels` (high / low). The player's choice
## (F4 in the F3 overlay) is kept in user://ambient.cfg; otherwise `quality.default`.
const SETTINGS: String = "user://ambient.cfg"
static var quality_id: String = ""


static func quality() -> Dictionary:
	var q: Dictionary = AmbientData.index().get("quality", {})
	var levels: Dictionary = q.get("levels", {})
	if quality_id == "":
		var cfg := ConfigFile.new()
		quality_id = String(q.get("default", "high"))
		if cfg.load(SETTINGS) == OK:
			quality_id = String(cfg.get_value("ambient", "quality", quality_id))
	if not levels.has(quality_id):
		quality_id = String(q.get("default", "high")) if levels.has(String(q.get("default", "high"))) else "high"
	var out: Dictionary = levels.get(quality_id, {}).duplicate()
	out["id"] = quality_id
	return out


## Switches high ↔ low (or to `id`), saves the choice and rebuilds the ambient layer of `room`.
static func set_quality(id: String, room: Node = null) -> void:
	quality_id = id
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("ambient", "quality", id)
	cfg.save(SETTINGS)
	rebuild(room)


## Rebuilds the ambient layer of a built room (quality or on/off changed).
static func rebuild(room: Node) -> void:
	if room == null or not (room is Room):
		return
	var old := of(room)
	if old != null:
		room.remove_child(old)
		old.queue_free()
	build(room as Room, String(room.get("room_id")))


static func build(room: Room, room_id: String) -> AmbientRoot:
	AmbientProbe.register()  # web only, with ?ambientprobe in the URL; once
	AmbientPerf.ensure()     # hidden performance overlay, F3; once
	if not enabled or room == null:
		return null
	var spec := AmbientData.room(room_id)
	if spec.is_empty():
		return null
	var root := AmbientRoot.new()
	root.name = "Ambient"
	room.add_child(root)
	root.setup(room, room_id, spec)
	return root


## The ambient layer of a built room (null when it has none).
static func of(room: Node) -> AmbientRoot:
	if room == null:
		return null
	return room.get_node_or_null("Ambient") as AmbientRoot
