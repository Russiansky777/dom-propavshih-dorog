class_name AmbientGround
extends RefCounted
## Ground plane of a room for the ambient layer (rain rings, splashes, footprints).
##
## The room's depth line (data `depth`: scale_top at top_y … scale_bottom at bottom_y) is the
## perspective of a pinhole camera over a flat floor: the depth scale is ∝ 1/distance and so is
## (y − horizon), hence scale(y) = slope·(y − horizon) — the horizon is where the line reaches 0.
## One metre on the floor across the view is scale(y)·px_per_m screen px; one metre along the view
## is that times squash(y) = (y − horizon) / focal_px (focal length from the camera FOV in
## ambient/_index.json `camera`). px_per_m comes from rooms/_index.json agata_ref (figure_px /
## height_m, the same ruler that sizes Agata). Sizes use the room's own depth_scale (clamped,
## exactly as Agata); squash uses the unclamped line (water and puddles lie beyond the floor edge).

var top_y: float = 640.0
var bottom_y: float = 1070.0
var scale_top: float = 0.6
var scale_bottom: float = 1.1
var slope: float = 0.0
var horizon_y: float = 0.0
var focal_px: float = 2059.0
var px_per_m: float = 208.2
var room: Room = null


static func for_room(r: Room) -> AmbientGround:
	var g := AmbientGround.new()
	g.room = r
	if r != null:
		g.top_y = r.depth_top_y
		g.bottom_y = r.depth_bottom_y
		g.scale_top = r.scale_top
		g.scale_bottom = r.scale_bottom
	g._derive()
	return g


func _derive() -> void:
	var dy := bottom_y - top_y
	slope = (scale_bottom - scale_top) / dy if absf(dy) > 0.001 else 0.0
	horizon_y = top_y - scale_top / slope if slope > 0.00001 else -1.0e5
	var cam := AmbientData.camera()
	var fov := deg_to_rad(float(cam.get("fov_deg", 50.0)))
	focal_px = 960.0 / tan(fov / 2.0)
	var ref: Dictionary = {}
	var sd := Engine.get_main_loop() as SceneTree
	if sd != null and sd.root.has_node("StoryData"):
		ref = sd.root.get_node("StoryData").rooms_index.get("agata_ref", {})
	var fig := float(ref.get("figure_px", cam.get("figure_px", 345.0)))
	var hm := float(ref.get("height_m", cam.get("height_m", 1.657)))
	px_per_m = fig / maxf(hm, 0.1)


## Depth scale used for sizes: the room's own (clamped) scale, the one Agata is drawn with.
func size_scale(y: float) -> float:
	if room != null:
		return room.depth_scale(y)
	return lerpf(scale_top, scale_bottom, clampf((y - top_y) / maxf(bottom_y - top_y, 0.001), 0.0, 1.0))


## Unclamped depth line (beyond the walkable floor: the river, the far bank).
func line_scale(y: float) -> float:
	return maxf(scale_top + (y - top_y) * slope, 0.02)


func squash(y: float) -> float:
	return clampf((y - horizon_y) / focal_px, 0.03, 1.0)


## Screen px per metre across the view at y (sizes follow Agata's scale).
func ppm(y: float) -> float:
	return size_scale(y) * px_per_m


## A floor vector in metres (x across, z towards the viewer) at `origin` → screen offset.
func ground_offset(origin_y: float, g: Vector2) -> Vector2:
	var k := ppm(origin_y)
	return Vector2(g.x * k, g.y * k * squash(origin_y))


## Screen direction → unit floor direction (x across, z towards the viewer).
func floor_dir(screen_dir: Vector2, y: float) -> Vector2:
	var v := Vector2(screen_dir.x, screen_dir.y / squash(y))
	return v.normalized() if v.length_squared() > 0.000001 else Vector2.RIGHT


## Uniforms shared by the water/puddle shaders: vec4(top_y, bottom_y, scale_top, scale_bottom)
## and vec4(horizon_y, focal_px, px_per_m, 0).
func depth_uniform() -> Vector4:
	return Vector4(top_y, bottom_y, scale_top, scale_bottom)


func ground_uniform() -> Vector4:
	return Vector4(horizon_y, focal_px, px_per_m, 0.0)
