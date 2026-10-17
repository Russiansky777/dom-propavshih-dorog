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
##     (R1: a click in the water brings Agata to the shore or onto the pier deck, never into the water).
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

	root.remove_child(room)
	room.free()
	NavigationServer2D.free_rid(map)
	await physics_frame


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
