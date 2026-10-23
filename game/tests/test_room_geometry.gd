extends SceneTree
## Headless geometry test of the data-driven rooms. Usage:
##   godot --headless --path game -s res://tests/test_room_geometry.gd
## Defects behind it (Director, live build 17.10): «Агата проходит сквозь стойку / стол / парты /
## воду у причала». Every in-scope room is built by RoomBuilder on its OWN navigation map and checked
## against the points written in its data (data/story/rooms/<LOC>.json):
##   - the baked mesh has no polygon inside a `walkable_holes` obstacle (holes really carved);
##   - `no_walk_samples` (inside furniture / water) are not on the mesh, and a path from the default
##     spawn towards them stops short of them;
##   - `walk_samples`, every spawn and every stand point are on the mesh and reachable from the
##     default spawn (one connected floor, no islands);
##   - no path to them cuts through an obstacle or leaves the floor outline;
##   - `nearest_checks`: map_get_closest_point(from) lands in the expected rect
##     (R1: a click in the water brings Agata to the shore or onto the pier deck, never into the water);
##   - `clearance` (Z1 counter): no baked floor point closer to the object's floor projection than
##     Agata's half width × depth scale (the feet are outside, the body must be too);
##   - scale (Director: «стул слишком большой, сцена приближена»): the background fits 1920x1080 whole
##     with one uniform scale 1920/width (± 0.001), and every layer/state node is drawn with that same
##     scale — times its data `scale` only when the data gives a `scale_reason`.
## Exit code 0 only when every check passed.
##
## Note: a `-s` script is compiled before autoloads exist: they are reached through the tree and the
## room classes are loaded at runtime (see run_tests.gd).

const ON_MESH_PX: float = 1.5     # a reachable point must be this close to its target
const OFF_MESH_PX: float = 2.0    # an obstacle point must be at least this far from the mesh
const DEEP_PX: float = 1.5        # a path point counts as "inside" an obstacle beyond this depth

var _results: Array = []          # [name, passed, failures]
var _fails: Array[String] = []
var _builder = null
var _sd: Node = null


func _initialize() -> void:
	_run()


func _check(cond: bool, message: String) -> void:
	if not cond:
		_fails.append(message)


func _run() -> void:
	await process_frame
	_sd = root.get_node_or_null("StoryData")
	if _sd == null or not _sd.get("loaded"):
		print("FAIL  StoryData autoload missing or not loaded")
		quit(1)
		return
	_builder = load("res://scripts/rooms/room_builder.gd")
	for rid in _sd.rooms_index.get("in_scope", []):
		_fails = []
		var started := Time.get_ticks_msec()
		await _test_room(String(rid))
		var passed := _fails.is_empty()
		_results.append([rid, passed, _fails.duplicate()])
		print("%s  geometry %s  (%d ms)" % ["PASS" if passed else "FAIL", rid, Time.get_ticks_msec() - started])
		for f in _fails:
			print("        - " + f)
	var failed := 0
	for r in _results:
		if not r[1]:
			failed += 1
	print("")
	print("==== geometry: %d rooms, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(0 if failed == 0 else 1)


static func _pt(a) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


static func _poly(arr: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in arr:
		out.append(_pt(p))
	return out


## Distance from `p` to the border of `poly`.
static func _edge_dist(p: Vector2, poly: PackedVector2Array) -> float:
	var best := INF
	for i in poly.size():
		var c := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])
		best = minf(best, p.distance_to(c))
	return best


## x of the straight line through two points [[x, y], [x, y]] at height `y` (data `clearance` edges).
static func _line_x(seg: Array, y: float) -> float:
	var a := _pt(seg[0])
	var b := _pt(seg[1])
	if is_equal_approx(a.y, b.y):
		return a.x
	return a.x + (b.x - a.x) * (y - a.y) / (b.y - a.y)


## True when `p` is inside `poly` deeper than DEEP_PX (points on the border do not count).
static func _deep_inside(p: Vector2, poly: PackedVector2Array) -> bool:
	return Geometry2D.is_point_in_polygon(p, poly) and _edge_dist(p, poly) > DEEP_PX


## True when `p` is outside `poly` further than DEEP_PX.
static func _deep_outside(p: Vector2, poly: PackedVector2Array) -> bool:
	return not Geometry2D.is_point_in_polygon(p, poly) and _edge_dist(p, poly) > DEEP_PX


func _label(s: Array) -> String:
	return "%s%s" % [str(_pt(s)), (" «%s»" % String(s[2])) if s.size() > 2 else ""]


func _test_room(rid: String) -> void:
	var spec: Dictionary = _sd.room(rid)
	var room = _builder.build(rid)
	_check(room != null, "RoomBuilder.build(%s) returned null" % rid)
	if room == null:
		return
	root.add_child(room)
	_check_scales(room, spec)
	var region: NavigationRegion2D = room.get_walkable()
	var map := NavigationServer2D.map_create()
	NavigationServer2D.map_set_active(map, true)
	region.set_navigation_map(map)
	var nav: NavigationPolygon = region.navigation_polygon
	var outline := _poly(spec.get("walkable", []))
	var holes: Array[PackedVector2Array] = []
	for h in spec.get("walkable_holes", []):
		holes.append(_poly(h))

	# The baked mesh: present, no polygon inside an obstacle (the Z1 counter defect).
	_check(nav.get_polygon_count() > 0, "navigation mesh is empty")
	for i in nav.get_polygon_count():
		var idx := nav.get_polygon(i)
		var c := Vector2.ZERO
		for k in idx:
			c += nav.vertices[k]
		c /= maxf(idx.size(), 1)
		for hi in holes.size():
			_check(not _deep_inside(c, holes[hi]), "mesh polygon %d (centre %s) lies inside walkable_holes[%d] — the obstacle is not carved out" % [i, str(c.round()), hi])

	var start: Vector2 = room.get_spawn("default").position
	# Wait until the fresh map is queryable (Godot 4.7.2: a few physics frames).
	var frames := 0
	var probe := PackedVector2Array()
	while frames < 60 and probe.size() < 1:
		await physics_frame
		frames += 1
		probe = NavigationServer2D.map_get_path(map, start, start + Vector2(1, 0), true)
	_check(probe.size() >= 1, "navigation map not ready after %d physics frames" % frames)

	# Points that must be reachable: walk samples, spawns, hotspot and exit stands.
	var targets: Array = []   # [Vector2, description]
	for s in spec.get("walk_samples", []):
		targets.append([_pt(s), "walk_sample " + _label(s)])
	var spawns: Dictionary = spec.get("spawns", {})
	for sid in spawns.keys():
		targets.append([_pt(spawns[sid]), "spawn %s %s" % [sid, str(_pt(spawns[sid]))]])
	for h in spec.get("hotspots", []):
		if h.has("stand"):
			targets.append([_pt(h["stand"]), "stand of hotspot %s %s" % [String(h.get("id", "?")), str(_pt(h["stand"]))]])
	var horizon := float(spec.get("background", {}).get("horizon", 640))
	for ex in spec.get("exits", []):
		var g: Dictionary = _builder.exit_geometry(spec, ex, _sd.rooms_index, horizon)
		targets.append([g["stand"], "stand of exit to %s %s" % [String(ex.get("to", "?")), str(g["stand"])]])
	for t in targets:
		var p: Vector2 = t[0]
		var closest := NavigationServer2D.map_get_closest_point(map, p)
		_check(closest.distance_to(p) <= ON_MESH_PX, "%s is off the floor mesh (closest %s)" % [t[1], str(closest.round())])
		var path := NavigationServer2D.map_get_path(map, start, p, true)
		var reached := path.size() > 0 and path[path.size() - 1].distance_to(p) <= ON_MESH_PX
		_check(reached, "%s is not reachable from spawn default %s (path ends at %s)" % [t[1], str(start), str(path[path.size() - 1].round()) if path.size() > 0 else "—"])
		_check_path(path, outline, holes, t[1])

	# Obstacle points: off the mesh, and walking towards them stops short.
	for s in spec.get("no_walk_samples", []):
		var p := _pt(s)
		var closest := NavigationServer2D.map_get_closest_point(map, p)
		_check(closest.distance_to(p) >= OFF_MESH_PX, "no_walk_sample %s is ON the floor mesh — Agata walks into it" % _label(s))
		var path := NavigationServer2D.map_get_path(map, start, p, true)
		if path.size() > 0:
			_check(path[path.size() - 1].distance_to(p) >= OFF_MESH_PX, "a path from the spawn reaches no_walk_sample %s" % _label(s))
		_check_path(path, outline, holes, "path towards no_walk_sample " + _label(s))

	# Where a click in the water (or on furniture) sends Agata.
	for nc in spec.get("nearest_checks", []):
		var frm := _pt(nc["from"])
		var box: Array = nc["in"]
		var rect := Rect2(float(box[0]), float(box[1]), float(box[2]), float(box[3]))
		var closest := NavigationServer2D.map_get_closest_point(map, frm)
		_check(rect.grow(0.5).has_point(closest), "closest floor point to %s is %s, expected inside %s (%s)" % [str(frm), str(closest.round()), str(rect), String(nc.get("_note", ""))])

	# Body clearance at furniture (data `clearance`; Director 18.10: «Агата чуть да проходит сквозь углы
	# стола» in Z1): the feet may not stand closer to the object's floor projection than Agata's half width
	# × depth scale — checked on the BAKED mesh, every 4 px of the y range.
	for cl in spec.get("clearance", []):
		var y0 := float(cl["y"][0])
		var y1 := float(cl["y"][1])
		var hw := float(cl["half_width_px"])
		var bad := 0
		var first := Vector2.ZERO
		var y := y0 + 2.0   # 2 px inside the range and the edges: points ON the hole border are floor
		while y <= y1 - 2.0:
			var sx: float = hw * float(room.depth_scale(y))
			var xl := _line_x(cl["left"], y) - sx
			var xr := _line_x(cl["right"], y) + sx
			var x := xl + 2.0
			while x <= xr - 2.0:
				var q := Vector2(x, y)
				if NavigationServer2D.map_get_closest_point(map, q).distance_to(q) < 0.5:
					if bad == 0:
						first = q
					bad += 1
				x += 4.0
			y += 4.0
		_check(bad == 0, "clearance «%s»: %d floor points closer than half_width_px × depth scale to the object (first %s) — her body enters it" % [String(cl.get("what", "?")), bad, str(first.round())])

	root.remove_child(room)
	room.free()
	NavigationServer2D.free_rid(map)
	await physics_frame


## Background: uniform 1920/width, whole picture in the frame. Layers: the background's scale × data scale,
## and exactly the background's scale unless the data explains a different one (scale_reason).
func _check_scales(room: Node, spec: Dictionary) -> void:
	var bg: Sprite2D = room.get_node_or_null("Background/Image")
	if bg == null:
		_check(not spec.get("background", {}).has("image"), "background image node missing")
		return
	var ts: Vector2 = bg.texture.get_size()
	var expect := 1920.0 / ts.x
	_check(absf(bg.scale.x - expect) <= 0.001, "background scale %.5f, expected 1920/%d = %.5f" % [bg.scale.x, int(ts.x), expect])
	_check(absf(bg.scale.y - bg.scale.x) <= 0.000001, "background scale must be uniform, got %s" % str(bg.scale))
	_check(absf(float(room.get("art_scale")) - bg.scale.x) <= 0.000001, "room.art_scale %.5f ≠ background scale %.5f" % [float(room.get("art_scale")), bg.scale.x])
	var drawn_h := ts.y * bg.scale.y
	_check(absf(drawn_h - 1080.0) <= 2.0 and absf(bg.position.y - roundf((1080.0 - drawn_h) / 2.0)) <= 0.5 and bg.position.x == 0.0,
		"background must fill 1920x1080 without crop or zoom: drawn %dx%d at %s" % [int(ts.x * bg.scale.x), int(drawn_h), str(bg.position)])
	for l in spec.get("layers", []):
		var lid := String(l.get("id", ""))
		var node: Node = room.get_node_or_null("Occluders/" + lid)
		if node == null:
			node = room.get_node_or_null("Layers/" + lid)
		_check(node != null, "layer %s not built" % lid)
		if node == null:
			continue
		if not l.has("image") and l.has("text"):
			# stand-in text until the picture is drawn (O1 board lines, validate_rooms.py п. 11): no art scale to check
			_check(node.get_node_or_null("Text") is Label, "text layer %s has its Label" % lid)
			continue
		if node.has_meta("stub"):
			# art ordered, not delivered (`pending`, validate_rooms.py п. 13): the engine's stand-in in screen px — no art
			# scale yet; once the picture is imported the layer is checked like any other
			_check(l.has("pending") and l.has("stub") and node.get_node_or_null("StandIn") != null, "stand-in layer %s: pending + stub, built" % lid)
			continue
		var img: Sprite2D = node.get_node_or_null("Image")
		if img == null:
			_check(false, "layer %s has no Image" % lid)
			continue
		var sc := float(l.get("scale", 1.0))
		var want := bg.scale.x * sc
		_check(absf(img.scale.x - want) <= 0.001 and absf(img.scale.y - img.scale.x) <= 0.000001,
			"layer %s scale %s, expected uniform background scale × %.3f = %.4f" % [lid, str(img.scale), sc, want])
		if String(l.get("scale_reason", "")).strip_edges() == "":
			_check(absf(img.scale.x - bg.scale.x) <= 0.001, "layer %s is drawn at %.4f, not the background's %.4f, and the data gives no scale_reason" % [lid, img.scale.x, bg.scale.x])


## No vertex and no 8-px step of a path lies inside an obstacle or outside the floor outline.
func _check_path(path: PackedVector2Array, outline: PackedVector2Array, holes: Array[PackedVector2Array], what: String) -> void:
	for i in path.size():
		var a := path[i]
		var b := path[min(i + 1, path.size() - 1)]
		var steps := maxi(1, int(a.distance_to(b) / 8.0))
		for k in steps + 1:
			var q := a.lerp(b, float(k) / float(steps))
			if outline.size() >= 3 and _deep_outside(q, outline):
				_check(false, "%s: the path leaves the floor outline at %s" % [what, str(q.round())])
				return
			for hi in holes.size():
				if _deep_inside(q, holes[hi]):
					_check(false, "%s: the path cuts through walkable_holes[%d] at %s" % [what, hi, str(q.round())])
					return
