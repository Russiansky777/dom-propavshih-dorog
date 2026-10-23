class_name RoomBuilder
extends RefCounted
## Builds a Room node tree at runtime from data/story/rooms/<id>.json (via StoryData).
## No per-room .tscn is needed: background, walkable polygon, props, hotspots, exits and spawns
## all come from data. Placeholder art: generated PNG (tools/make_placeholders.py) when present,
## otherwise flat polygons drawn here.

const BG_DIR: String = "res://assets/placeholders/rooms"
const LABEL_FONT_SIZE: int = 22


static func build(room_id: String) -> Room:
	var spec: Dictionary = StoryData.room(room_id)
	if spec.is_empty():
		push_error("RoomBuilder: no data for room " + room_id)
		return null
	var idx: Dictionary = StoryData.rooms_index
	var bg: Dictionary = spec.get("background", {})
	var kind := String(bg.get("kind", "interior"))
	var horizon := float(bg.get("horizon", 640))

	var room := Room.new()
	room.name = room_id
	room.room_id = room_id
	room.room_name = StoryData.location_name(room_id)
	var depth: Dictionary = spec.get("depth", idx.get("defaults", {}).get("depth_exterior" if kind == "exterior" else "depth", {}))
	room.depth_top_y = float(depth.get("top_y", horizon))
	room.depth_bottom_y = float(depth.get("bottom_y", 1070))
	room.scale_top = float(depth.get("scale_top", 0.6))
	room.scale_bottom = float(depth.get("scale_bottom", 1.1))

	_build_background(room, room_id, bg, horizon)
	_build_walkable(room, spec, kind, idx)
	_build_props(room, spec)
	_build_layers(room, spec)
	AmbientBuilder.build(room, room_id)  # живой мир: дождь, ветер, вода, лужи и следы — data/story/ambient/<LOC>.json
	_build_effects(room, spec)
	_build_spawns(room, spec)
	_build_hotspots(room, room_id, spec)
	_build_exits(room, room_id, spec, idx, horizon)
	RoomLighting.build(room, room_id)  # свет, огонь, тени от источников: data/story/lights/<LOC>.json
	TimeGrade.build(room, room_id)  # время суток: оттенок, окна — data/story/time (F17)
	return room


# --- Pieces -------------------------------------------------------------------

static func _rect_polygon(w: float, h: float, centered: bool = true) -> PackedVector2Array:
	if centered:
		return PackedVector2Array([Vector2(-w / 2, -h / 2), Vector2(w / 2, -h / 2), Vector2(w / 2, h / 2), Vector2(-w / 2, h / 2)])
	return PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)])


static func _make_label(text: String, w: float, h: float, font_size: int = LABEL_FONT_SIZE) -> Label:
	var l := Label.new()
	l.name = "Caption"
	l.text = text
	l.position = Vector2(-w / 2, -h / 2)
	l.size = Vector2(w, h)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func _build_background(room: Room, room_id: String, bg: Dictionary, horizon: float) -> void:
	var container := Node2D.new()
	container.name = "Background"
	container.z_index = -10
	room.add_child(container)
	# Art ordered but not delivered (R2, R3 — Docs/BRIEF_CHATGPT_v4.md): flat shapes from data, never the room code.
	if bg.has("placeholder"):
		container.add_child(PlaceholderArt.build(bg["placeholder"].get("shapes", [])))
		return
	var png := String(bg.get("image", "%s/%s.png" % [BG_DIR, room_id]))
	if ResourceLoader.exists(png):
		var s := Sprite2D.new()
		s.name = "Image"
		s.texture = load(png)
		s.centered = false
		var tex_size: Vector2 = s.texture.get_size()
		if tex_size.x > 0:
			# The whole picture fits the 1920-wide frame: one uniform scale, no crop, no zoom
			# (1672x941 → 1.1483; 2048x1152 → 0.9375). It is the room's art scale: every layer and
			# state is drawn with it too (see _build_layers). Off-16:9 art is centred vertically.
			room.art_scale = 1920.0 / tex_size.x
			s.scale = Vector2(room.art_scale, room.art_scale)
			s.position = Vector2(0.0, roundf((1080.0 - tex_size.y * room.art_scale) / 2.0))
		container.add_child(s)
		return
	# Fallback: flat colours.
	var wall := Polygon2D.new()
	wall.name = "Wall"
	wall.color = Color.html(String(bg.get("wall", "#555555")))
	wall.polygon = _rect_polygon(1920, horizon, false)
	container.add_child(wall)
	var floor_p := Polygon2D.new()
	floor_p.name = "Floor"
	floor_p.color = Color.html(String(bg.get("floor", "#777777")))
	floor_p.polygon = _rect_polygon(1920, 1080 - horizon, false)
	floor_p.position = Vector2(0, horizon)
	container.add_child(floor_p)
	var base := Polygon2D.new()
	base.name = "Baseboard"
	base.color = Color.html(String(bg.get("accent", "#444444")))
	base.polygon = _rect_polygon(1920, 10, false)
	base.position = Vector2(0, horizon - 10)
	container.add_child(base)
	var title := _make_label(room_id, 400, 80, 48)
	title.position = Vector2(1500, 20)
	title.modulate.a = 0.35
	container.add_child(title)


static func _build_walkable(room: Room, spec: Dictionary, kind: String, idx: Dictionary) -> void:
	var pts: Array = spec.get("walkable", idx.get("defaults", {}).get("walkable_exterior" if kind == "exterior" else "walkable_interior", []))
	var region := NavigationRegion2D.new()
	region.name = "Walkable"
	var poly := NavigationPolygon.new()
	var verts := PackedVector2Array()
	for i in pts.size():
		verts.append(Vector2(float(pts[i][0]), float(pts[i][1])))
	poly.add_outline(verts)
	# Holes (furniture standing on the floor: the Z1 counter, desks, a table) are OBSTRUCTION outlines.
	# A second traversable outline is merged with the floor by the 4.7 baker, not subtracted — that
	# was the defect «Агата проходит сквозь стойку Z1» (the hole was in the data but not in the mesh).
	var source := NavigationMeshSourceGeometryData2D.new()
	for hole in spec.get("walkable_holes", []):
		var hv := PackedVector2Array()
		for p in hole:
			hv.append(Vector2(float(p[0]), float(p[1])))
		source.add_obstruction_outline(hv)
	poly.agent_radius = 0.0
	# Bake synchronously: the outline may be concave (e.g. H1 floor around the armchair) and the
	# navigation server needs convex polygons.
	NavigationServer2D.bake_from_source_geometry_data(poly, source)
	if poly.get_polygon_count() == 0:
		push_error("RoomBuilder: baking produced no polygons in %s; using the raw outline WITHOUT holes" % String(spec.get("id", "?")))
		var indices := PackedInt32Array()
		for i in pts.size():
			indices.append(i)
		poly.vertices = verts
		poly.add_polygon(indices)
	region.navigation_polygon = poly
	room.add_child(region)


static func _build_props(room: Room, spec: Dictionary) -> void:
	var occluders := Node2D.new()
	occluders.name = "Occluders"
	var props := Node2D.new()
	props.name = "Props"
	room.add_child(props)
	room.add_child(occluders)
	for p in spec.get("props", []):
		var r: Array = p.get("rect", [0, 0, 10, 10])
		var node := Node2D.new()
		node.name = String(p.get("id", "prop"))
		var w := float(r[2])
		var h := float(r[3])
		node.position = Vector2(float(r[0]) + w / 2, float(r[1]) + h / 2)
		var image := String(p.get("image", ""))
		if image != "" and ResourceLoader.exists(image):
			var spr := Sprite2D.new()
			spr.name = "Image"
			spr.texture = load(image)
			spr.centered = false
			spr.position = Vector2(-w / 2, -h / 2)
			var ts: Vector2 = spr.texture.get_size()
			if ts.x > 0 and ts.y > 0:
				spr.scale = Vector2(w / ts.x, h / ts.y)
			node.add_child(spr)
		else:
			var fill := Polygon2D.new()
			fill.name = "Fill"
			fill.color = Color.html(String(p.get("color", "#666666")))
			fill.polygon = _rect_polygon(w, h)
			node.add_child(fill)
			var label_key := String(p.get("label", ""))
			if label_key != "":
				node.add_child(_make_label(StoryData.text(label_key), w, h))
		if bool(p.get("occluder", false)):
			# Sorting line: explicit `z` (e.g. the feet of a table drawn in a full-screen PNG), else the rect bottom.
			node.z_index = clampi(int(p.get("z", float(r[1]) + h)), 0, 4096)
			occluders.add_child(node)
		else:
			props.add_child(node)


## `layers[]`: PNGs drawn with the room's art scale (the background's 1920/width) — the same pixel
## size as the background, whatever the layer canvas is — then moved by `offset` (screen px).
## `scale` multiplies it only for art drawn at a different size than the background; such a layer
## must say why in `scale_reason` (tools/validate_rooms.py, tests/test_room_geometry.gd). The old
## rule stretched every canvas to 1920x1080 on its own, which distorted a 1602x981 state by 9 %.
## `occluder` + `z` → drawn in Occluders with that z (y-sort line); otherwise z 0 under the player.
## `if`/`unless` make it a state layer (StateLayer refreshes on flag changes).
static func _build_layers(room: Room, spec: Dictionary) -> void:
	var occluders := room.get_node_or_null("Occluders")
	var container := Node2D.new()
	container.name = "Layers"
	room.add_child(container)
	for l in spec.get("layers", []):
		if not l.has("image") and l.has("text"):
			_build_text_layer(container, l)
			continue
		var image := String(l.get("image", ""))
		if image == "" or not ResourceLoader.exists(image):
			# Art ordered and not delivered yet (`pending` — its request in assets/manifest.json, партия 8б): the
			# engine's stand-in `stub` takes its place (PlaceholderArt.stand_in, screen px) with the same if / unless.
			# The import of the ordered file (tools/import_room_art.py) puts the picture at `image` — the stand-in is
			# then never built, nothing in the data changes.
			if l.has("stub"):
				_build_stub_layer(container, occluders, l)
				continue
			push_warning("RoomBuilder: layer image missing: " + image)
			continue
		var node := StateLayer.new()
		node.name = String(l.get("id", image.get_file().get_basename()))
		var spr := Sprite2D.new()
		spr.name = "Image"
		spr.texture = load(image)
		spr.centered = false
		var ts: Vector2 = spr.texture.get_size()
		var sc := float(l.get("scale", 1.0))
		# No background picture (placeholder room): the layer's own width defines the art scale.
		var art := room.art_scale if room.art_scale > 0.0 else (1920.0 / ts.x if ts.x > 0 else 1.0)
		spr.scale = Vector2(art * sc, art * sc)
		var off: Array = l.get("offset", [0, 0])
		spr.position = Vector2(float(off[0]), float(off[1]))
		# `modulate` "#rrggbb": a day patch laid over an evening state takes its tone (Z3: the shore stone
		# without a plate over the batch-3 dusk layer).
		if l.has("modulate"):
			spr.modulate = Color.html(String(l["modulate"]))
		# `pivot` [x, y] in the layer's own pixels: the sprite turns about it — static `rotation_deg` (the M4
		# lever in a notch) or `spin` (the M1 wheel); the canvas origin still lands at `offset`.
		if l.has("pivot"):
			var pv := Vector2(float(l["pivot"][0]), float(l["pivot"][1]))
			spr.offset = -pv
			spr.position += pv * art * sc
			spr.rotation_degrees = float(l.get("rotation_deg", 0.0))
		node.add_child(spr)
		if bool(l.get("occluder", false)) and occluders != null:
			node.z_index = clampi(int(l.get("z", 1080)), 0, 4096)
			occluders.add_child(node)
		else:
			node.z_index = clampi(int(l.get("z", 0)), -10, 4096)
			container.add_child(node)
		node.setup(l)


## A stand-in layer until its picture is drawn (`text` instead of `image`, `_stub` says what it replaces —
## O1: «Мама, я иду» in chalk on the board): the text in the game's font inside `rect`, `font`
## (body_italic by default; "italic" = body_italic), `font_size`, `color` with `alpha`, tilted by `angle_deg`.
## Same if / unless rules as an image layer.
static func _build_text_layer(container: Node2D, l: Dictionary) -> void:
	var node := StateLayer.new()
	node.name = String(l.get("id", "text"))
	node.add_child(PlaceholderArt.text_label(l))
	node.z_index = clampi(int(l.get("z", 0)), -10, 4096)
	container.add_child(node)
	node.setup(l)


## The stand-in of a layer whose picture is ordered (`stub` — PlaceholderArt.stand_in, screen px), under the
## layer's own id, if / unless, z and occluder rule; meta `stub` = true (probes: which pictures are still stand-ins).
static func _build_stub_layer(container: Node2D, occluders: Node, l: Dictionary) -> void:
	var node := StateLayer.new()
	node.name = String(l.get("id", "stub"))
	node.set_meta("stub", true)
	node.add_child(PlaceholderArt.stand_in(l["stub"]))
	if bool(l.get("occluder", false)) and occluders != null:
		node.z_index = clampi(int(l.get("z", 1080)), 0, 4096)
		occluders.add_child(node)
	else:
		node.z_index = clampi(int(l.get("z", 0)), -10, 4096)
		container.add_child(node)
	node.setup(l)


## `effects[]`: programmatic effects (fire in the stove, snow in the yard), flag-conditional.
static func _build_effects(room: Room, spec: Dictionary) -> void:
	var container := Node2D.new()
	container.name = "Effects"
	room.add_child(container)
	for e in spec.get("effects", []):
		var node := RoomEffect.new()
		node.name = String(e.get("id", e.get("type", "effect")))
		node.z_index = clampi(int(e.get("z", 1)), -10, 4096)
		container.add_child(node)
		node.setup(e)


static func _build_spawns(room: Room, spec: Dictionary) -> void:
	var spawns := Node2D.new()
	spawns.name = "Spawns"
	room.add_child(spawns)
	for sid in spec.get("spawns", {}).keys():
		var m := Marker2D.new()
		m.name = String(sid)
		var p: Array = spec["spawns"][sid]
		m.position = Vector2(float(p[0]), float(p[1]))
		spawns.add_child(m)


static func _build_hotspots(room: Room, room_id: String, spec: Dictionary) -> void:
	var container := Node2D.new()
	container.name = "Hotspots"
	room.add_child(container)
	for h in spec.get("hotspots", []):
		var r: Array = h.get("rect", [0, 0, 10, 10])
		var w := float(r[2])
		var hgt := float(r[3])
		var hs := StoryHotspot.new()
		hs.name = String(h.get("id", "hotspot"))
		hs.position = Vector2(float(r[0]) + w / 2, float(r[1]) + hgt / 2)
		var shape := CollisionShape2D.new()
		shape.name = "Shape"
		var rs := RectangleShape2D.new()
		rs.size = Vector2(w, hgt)
		shape.shape = rs
		hs.add_child(shape)
		var visual := Node2D.new()
		visual.name = "Visual"
		var fill := Polygon2D.new()
		fill.name = "Fill"
		fill.polygon = _rect_polygon(w, hgt)
		visual.add_child(fill)
		var kind := String(h.get("kind", "object"))
		# Static sprite for a real-art hotspot (e.g. an NPC front view): fitted to the rect height,
		# feet at the rect bottom; placeholder fill/labels stay hidden (draw:false).
		var image := String(h.get("image", ""))
		if image != "" and ResourceLoader.exists(image):
			var spr := Sprite2D.new()
			spr.name = "Image"
			spr.texture = load(image)
			spr.centered = false
			var ts: Vector2 = spr.texture.get_size()
			var sc := hgt / maxf(ts.y, 1.0)
			spr.scale = Vector2(sc, sc)
			spr.position = Vector2(-ts.x * sc / 2, -hgt / 2)
			# Sorted by the feet (rect bottom) like the player and the occluders: Agata walking on the
			# R1 pier behind Pelageya is drawn behind her, Tamara stays behind the Z1 counter.
			spr.z_index = clampi(int(float(r[1]) + hgt), 0, 4096)
			# A flat figure in a dusk / night painting takes the scene's tone (Mitya at the far pier): data
			# `image_tint` "#rrggbb" (multiplied; no lighting file tones a hotspot picture).
			if h.has("image_tint"):
				spr.modulate = Color.html(String(h["image_tint"]))
			hs.add_child(spr)
		# No sheet yet (Pavel, Mitya — BRIEF_CHATGPT_v4 §A): a flat figure filling the rect, feet at its bottom,
		# sorted by the feet like a sprite. Data: placeholder {kind: silhouette, color, cap, beard, lantern}.
		var ph: Dictionary = h.get("placeholder", {})
		if String(ph.get("kind", "")) == "silhouette":
			var fig := PlaceholderArt.silhouette(Rect2(-w / 2, -hgt / 2, w, hgt), Color.html(String(ph.get("color", "#2e2822"))), ph)
			fig.z_index = clampi(int(float(r[1]) + hgt), 0, 4096)
			hs.add_child(fig)
		if kind == "npc":
			var head := Polygon2D.new()
			head.name = "Head"
			head.color = Color(0.95, 0.85, 0.72)
			var hr := minf(w, 70.0) * 0.45
			head.polygon = PackedVector2Array([Vector2(-hr, -hgt / 2 + 10), Vector2(hr, -hgt / 2 + 10), Vector2(hr, -hgt / 2 + 10 + hr * 1.6), Vector2(-hr, -hgt / 2 + 10 + hr * 1.6)])
			visual.add_child(head)
		elif kind == "pickup":
			var star := Polygon2D.new()
			star.name = "Mark"
			star.color = Color(1, 1, 0.7, 0.9)
			star.polygon = PackedVector2Array([Vector2(0, -hgt / 2 - 14), Vector2(8, -hgt / 2 - 2), Vector2(-8, -hgt / 2 - 2)])
			visual.add_child(star)
		var caption := _make_label("", w, hgt)
		if kind == "npc":
			caption.position = Vector2(-w / 2 - 60, -hgt / 2 - 44)
			caption.size = Vector2(w + 120, 40)
		visual.add_child(caption)
		visual.visible = bool(h.get("draw", true))  # real-art rooms: invisible, discovered by hover
		hs.add_child(visual)
		var stand := Marker2D.new()
		stand.name = "StandPoint"
		var sp: Array = h.get("stand", [r[0], r[1]])
		stand.position = Vector2(float(sp[0]), float(sp[1])) - hs.position
		hs.add_child(stand)
		hs.fill = fill
		hs.caption = caption
		container.add_child(hs)
		hs.setup(room_id, h)


static func exit_geometry(spec: Dictionary, ex: Dictionary, idx: Dictionary, horizon: float) -> Dictionary:
	## Mirrors tools/validate_rooms.py::exit_geometry. Returns {rect: Rect2, stand: Vector2}.
	if ex.has("rect") and ex.has("stand"):
		var r: Array = ex["rect"]
		return {"rect": Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3])), "stand": Vector2(float(ex["stand"][0]), float(ex["stand"][1]))}
	var sides: Dictionary = idx.get("sides", {})
	var side := String(ex.get("side", ""))
	if side == "left" or side == "right":
		var s: Dictionary = sides.get(side, {})
		var r: Array = s.get("rect", [0, 560, 130, 520])
		var st: Array = s.get("stand", [110, 900])
		return {"rect": Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3])), "stand": Vector2(float(st[0]), float(st[1]))}
	if side == "back":
		var s: Dictionary = sides.get("back", {})
		var x := float(ex.get("x", 960))
		var hw := float(s.get("half_w", 100))
		var top := float(s.get("top", 220))
		return {"rect": Rect2(x - hw, top, hw * 2, horizon - top), "stand": Vector2(x, horizon + float(s.get("stand_below_horizon", 60)))}
	if side == "bottom":
		var s: Dictionary = sides.get("bottom", {})
		var x := float(ex.get("x", 960))
		var hw := float(s.get("half_w", 200))
		return {"rect": Rect2(x - hw, float(s.get("top", 1000)), hw * 2, float(s.get("h", 80))), "stand": Vector2(x, float(s.get("stand_y", 1030)))}
	push_warning("RoomBuilder: exit %s without side/rect in %s" % [String(ex.get("to", "?")), String(spec.get("id", "?"))])
	return {"rect": Rect2(1790, 560, 130, 520), "stand": Vector2(1810, 900)}


## Exits: an Area2D per `exits[]` entry (requires from locations.json edges), its StandPoint, a
## placeholder Visual (draw:true rooms only) and — unless it is drawn in the art — an ExitCue mark.
static func _build_exits(room: Room, room_id: String, spec: Dictionary, idx: Dictionary, horizon: float) -> void:
	var container := Node2D.new()
	container.name = "Exits"
	room.add_child(container)
	var edges: Dictionary = StoryData.edges.get(room_id, {})
	for ex in spec.get("exits", []):
		var to := String(ex.get("to", ""))
		var requires: Array = []
		if edges.has(to):
			requires = edges[to].get("requires", []).duplicate()
			# One direction only (data exit `requires`, added to the edge's): back into the boat from the far pier
			# only once the boat goes both ways (F13, Director 23.10: `boat_shuttle_open`, set by blocks 3–5).
			for f in ex.get("requires", []):
				if not requires.has(f):
					requires.append(f)
		else:
			push_warning("RoomBuilder: exit %s→%s has no edge in locations.json" % [room_id, to])
		var g := exit_geometry(spec, ex, idx, horizon)
		var rect: Rect2 = g["rect"]
		var node := StoryExit.new()
		node.name = "to_" + to
		node.position = rect.get_center()
		var shape := CollisionShape2D.new()
		shape.name = "Shape"
		var rs := RectangleShape2D.new()
		rs.size = rect.size
		shape.shape = rs
		node.add_child(shape)
		var visual := Node2D.new()
		visual.name = "Visual"
		var fill := Polygon2D.new()
		fill.name = "Fill"
		fill.polygon = _rect_polygon(rect.size.x, rect.size.y)
		visual.add_child(fill)
		var arrow := Polygon2D.new()
		arrow.name = "Arrow"
		arrow.color = Color(1, 1, 1, 0.7)
		var side := String(ex.get("side", ""))
		match side:
			"left":
				arrow.polygon = PackedVector2Array([Vector2(20, -30), Vector2(-20, 0), Vector2(20, 30)])
			"right":
				arrow.polygon = PackedVector2Array([Vector2(-20, -30), Vector2(20, 0), Vector2(-20, 30)])
			"bottom":
				arrow.polygon = PackedVector2Array([Vector2(-30, -15), Vector2(30, -15), Vector2(0, 20)])
			_:
				arrow.polygon = PackedVector2Array([Vector2(-30, 15), Vector2(30, 15), Vector2(0, -20)])
		visual.add_child(arrow)
		var caption := _make_label("", rect.size.x + 160, 60)
		caption.position = Vector2(-(rect.size.x + 160) / 2, rect.size.y / 2 - 70 if side != "bottom" else -rect.size.y / 2 - 60)
		if side == "right":
			caption.size = Vector2(250, 60)
			caption.position.x = (1910.0 - 250.0) - node.position.x
			caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		elif side == "left":
			caption.size = Vector2(250, 60)
			caption.position.x = 10.0 - node.position.x
			caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		visual.add_child(caption)
		visual.visible = bool(ex.get("draw", true))
		node.add_child(visual)
		var stand := Marker2D.new()
		stand.name = "StandPoint"
		stand.position = g["stand"] - node.position
		node.add_child(stand)
		node.fill = fill
		node.caption = caption
		# How the player finds it (Director 18.10): an exit drawn in the art (door, opening, gate) needs
		# only its caption and the exit cursor; an exit off the frame edge or along a path into the
		# depth gets a visible mark (ExitCue) — direction from `cue`, `side` or the edge the rect touches.
		var cue_info := ExitCue.classify(ex, rect)
		node.cue_dir = String(cue_info["dir"])
		node.cue_source = String(cue_info["source"])
		if node.cue_dir != "door":
			var cue := ExitCue.new()
			cue.name = "Cue"
			cue.direction = node.cue_dir
			if ex.has("cue_deg"):
				cue.angle_deg = float(ex["cue_deg"])   # a path leaving at a slant (F20)
			cue.exit_node = node
			cue.position = Vector2(cue_info["at"]) - node.position
			node.add_child(cue)
			node.cue = cue
		container.add_child(node)
		node.setup(room_id, ex, requires)
