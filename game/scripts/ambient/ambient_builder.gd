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

## Off → rooms are built without the ambient layer (FPS comparison, ?ambientprobe in the web build).
static var enabled: bool = true


static func build(room: Room, room_id: String) -> AmbientRoot:
	if not enabled or room == null:
		return null
	var spec := AmbientData.room(room_id)
	if spec.is_empty():
		return null
	var root := AmbientRoot.new()
	root.name = "Ambient"
	room.add_child(root)
	root.setup(room, room_id, spec)
	AmbientProbe.register()
	return root


## The ambient layer of a built room (null when it has none).
static func of(room: Node) -> AmbientRoot:
	if room == null:
		return null
	return room.get_node_or_null("Ambient") as AmbientRoot
