extends SceneTree
## Headless test of the ambient layer («Живой мир»: drizzle, wind, water, puddles, footprints, dust).
##   godot --headless --path game -s res://tests/test_ambient.gd
## Data: data/story/ambient/*.json (tools/validate_ambient.py checks the schema). Exit code 0 only
## when every check passed.
##   1. every room with an ambient file builds its layer with exactly the regions of its data;
##      interiors get no rain, water, puddles, mud or footfall; a new street needs one entry (Z4);
##   2. nothing in the ambient layer takes input (no CollisionObject2D / Control, no input processing)
##      and a click on a hotspot under the rain still finds the hotspot;
##   3. draw order: rain over everything in the room (z 4096 > any actor), regions on the picture
##      (z −9, or just above the room layer they redraw), prints on the floor (z −8), drops at feet y + 1;
##   4. shader parameters come from the data (intensity, slant, amplitudes, anchors, drop rings);
##   5. the foot contact frames and planted-foot offsets in the data equal a fresh measurement of the
##      walk sheet (same method as tools/measure_stride.py: alpha > 64, bottom band 40 px);
##   6. Agata walking in Z2: steps only on contact frames, a splash in each puddle step (drops sorted
##      in front of her, sized by the room depth scale), a print in each mud step, nothing on grass;
##   7. prints: at most prints_max, fade to nothing in print_fade_s; a splash lives 0.3–0.5 s;
##   8. flag conditions: H1 window panes and dust only with the shutters open.
## Note: a `-s` script is compiled before autoloads exist: they are reached through the tree and the
## room/ambient classes are loaded at runtime (see run_tests.gd).

const AMB_DIR := "res://data/story/ambient"

var _results: Array = []
var _fails: Array[String] = []
var gs: Node
var rm: Node
var sd: Node
var main_node: Node = null
var player: Node2D = null
var Builder = null
var RoomBuilderScript = null
var AmbData = null


func _initialize() -> void:
	_run()


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fails.append(msg)


func _test(name: String, fn: Callable) -> void:
	_fails = []
	var t0 := Time.get_ticks_msec()
	await fn.call()
	var ok := _fails.is_empty()
	_results.append([name, ok, _fails.duplicate()])
	print("%s  %s  (%d ms)" % ["PASS" if ok else "FAIL", name, Time.get_ticks_msec() - t0])
	for f in _fails:
		print("        - " + f)


func _run() -> void:
	await process_frame
	gs = root.get_node_or_null("GameState")
	rm = root.get_node_or_null("RoomManager")
	sd = root.get_node_or_null("StoryData")
	if gs == null or rm == null or sd == null or not sd.get("loaded"):
		print("FAIL  autoloads / StoryData not loaded")
		quit(1)
		return
	Builder = load("res://scripts/ambient/ambient_builder.gd")
	RoomBuilderScript = load("res://scripts/rooms/room_builder.gd")
	AmbData = load("res://scripts/ambient/ambient_data.gd")
	rm.autosave_enabled = false
	await _test("Ambient: every room with data builds its regions; interiors without rain/water/mud; Z4 by one entry", _test_build)
	await _test("Ambient: nothing takes input; a hotspot under the rain is still clicked", _test_no_input)
	await _test("Ambient: draw order — rain over all, regions on the picture, prints on the floor", _test_draw_order)
	await _test("Ambient: shader parameters come from the data", _test_params)
	await _test("Ambient: contact frames and planted-foot offsets = fresh measurement of the walk sheet", _test_contacts)
	await _test("Ambient: Agata in Z2 — splash in puddles, prints in mud, only on contact frames, sized by depth", _test_footfall)
	await _test("Ambient: prints capped and fading in print_fade_s; a splash lives 0.3–0.5 s", _test_prints_and_splash)
	await _test("Ambient: H1 panes and dust only with the shutters open", _test_flags)
	_cleanup()
	var failed := 0
	for r in _results:
		if not r[1]:
			failed += 1
	print("")
	print("==== ambient: %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(0 if failed == 0 else 1)


# --- Helpers --------------------------------------------------------------------------------------

func _ambient_rooms() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(AMB_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".json") and not f.begins_with("_"):
			out.append(f.get_basename())
	out.sort()
	return out


func _build(rid: String) -> Node:
	var room = RoomBuilderScript.build(rid)
	if room == null:
		return null
	root.add_child(room)
	return room


func _free(room: Node) -> void:
	if room != null and is_instance_valid(room):
		root.remove_child(room)
		room.free()


func _poly(e: Dictionary) -> PackedVector2Array:
	return AmbData.shape_of(e)


func _spawn_main() -> void:
	if main_node != null:
		return
	main_node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main_node)
	await process_frame
	await process_frame
	rm.autosave_enabled = false
	player = main_node.get_node("World/Player")


func _cleanup() -> void:
	if main_node != null and is_instance_valid(main_node):
		root.remove_child(main_node)
		main_node.free()
		main_node = null
	rm.current_room = null
	gs.reset()


# --- 1. Build ---------------------------------------------------------------------------------------

func _test_build() -> void:
	var rooms := _ambient_rooms()
	_check(rooms.size() >= 7, "expected ambient files for Z2 Z3 R1 H1 H2 O1 O2, got %s" % str(rooms))
	for rid in ["Z2", "Z3", "R1", "H1", "H2", "O1", "O2"]:
		_check(rid in rooms, "no ambient file for %s" % rid)
	for rid in rooms:
		if not sd.has_room(rid):
			print("    %s: ambient data waits for rooms/%s.json (not built yet)" % [rid, rid])
			continue
		var spec: Dictionary = AmbData.room(rid)
		var room := _build(rid)
		_check(room != null, "%s: room did not build" % rid)
		if room == null:
			continue
		var amb = Builder.of(room)
		_check(amb != null, "%s: no Ambient node" % rid)
		if amb == null:
			_free(room)
			continue
		var st: Dictionary = amb.stats()
		var kind := String(sd.room(rid).get("background", {}).get("kind", "exterior"))
		var has_pic: bool = amb.has_picture()
		var n_sway: int = spec.get("sway_regions", []).size() if has_pic else 0
		var n_water: int = spec.get("water", []).size() if has_pic else 0
		var n_pud: int = spec.get("puddles", []).size() if has_pic else 0
		_check(st["sway"] == n_sway, "%s: %d sway regions built, data has %d" % [rid, st["sway"], n_sway])
		_check(st["water"] == n_water, "%s: %d water regions built, data has %d" % [rid, st["water"], n_water])
		_check(st["puddles"] == n_pud, "%s: %d puddles built, data has %d" % [rid, st["puddles"], n_pud])
		_check(st["dust"] == spec.get("dust", []).size(), "%s: dust emitters %d vs data %d" % [rid, st["dust"], spec.get("dust", []).size()])
		_check(st["rain"] == spec.has("rain"), "%s: rain %s vs data %s" % [rid, st["rain"], spec.has("rain")])
		if kind == "interior":
			_check(not st["rain"] and st["water"] == 0 and st["puddles"] == 0 and amb.footfall == null,
				"%s: interior must have no rain, water, puddles or footfall (%s)" % [rid, str(st)])
		print("    %s (%s): %s" % [rid, kind, str(st)])
		_free(room)
	# Rooms without a file get nothing.
	for rid in sd.rooms_index.get("in_scope", []):
		if not (String(rid) in rooms):
			var room := _build(String(rid))
			if room != null:
				_check(Builder.of(room) == null, "%s: has no ambient file but got an Ambient node" % rid)
				_free(room)
	# A new street = one entry (preset street): Z4.
	var z4: Dictionary = AmbData.room("Z4")
	_check(z4.has("rain") and z4.has("wind"), "Z4 {id, preset: street} must give rain and wind from the preset")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(AMB_DIR + "/Z4.json"))
	var keys := raw.keys().filter(func(k): return not String(k).begins_with("_"))
	_check(keys.size() <= 2, "Z4 file should be one entry {id, preset}, has keys %s" % str(keys))


# --- 2. Input ---------------------------------------------------------------------------------------

func _collect(n: Node, out: Array) -> void:
	out.append(n)
	for c in n.get_children():
		_collect(c, out)


func _test_no_input() -> void:
	for rid in _ambient_rooms():
		if not sd.has_room(rid):
			continue
		var room := _build(rid)
		var amb = Builder.of(room)
		if amb == null:
			_free(room)
			continue
		var nodes: Array = []
		_collect(amb, nodes)
		for n in nodes:
			_check(not (n is CollisionObject2D), "%s: %s is a CollisionObject2D (would take clicks)" % [rid, n.get_path()])
			_check(not (n is Control), "%s: %s is a Control (would take clicks)" % [rid, n.get_path()])
			_check(not n.is_processing_input() and not n.is_processing_unhandled_input(), "%s: %s processes input" % [rid, n.name])
		_free(room)
	# Z2 under the rain: Room.pick still finds the porch exit and the landmarks hotspot.
	gs.reset()
	await _spawn_main()
	rm.change_room("Z2", "default")
	for i in 3:
		await physics_frame
	var room: Node = rm.current_room
	var spec: Dictionary = sd.room("Z2")
	for h in spec.get("hotspots", []) + spec.get("exits", []):
		if not h.has("rect"):
			continue
		var r: Array = h["rect"]
		var c := Vector2(float(r[0]) + float(r[2]) / 2.0, float(r[1]) + float(r[3]) / 2.0)
		var hit = room.pick(c)
		_check(hit != null, "Z2: nothing picked at %s (%s) with the ambient layer on" % [str(c), h.get("id", h.get("to", "?"))])


# --- 3. Draw order ----------------------------------------------------------------------------------

func _test_draw_order() -> void:
	for rid in _ambient_rooms():
		if not sd.has_room(rid):
			continue
		var room := _build(rid)
		var amb = Builder.of(room)
		if amb == null:
			_free(room)
			continue
		var min_actor_y: float = room.depth_top_y - 60.0   # actors are sorted by feet y ≥ the floor top
		if amb.rain != null:
			_check(amb.rain.z_index == 4096, "%s: rain z %d, must be 4096 (over everything in the room)" % [rid, amb.rain.z_index])
			_check(not amb.rain.z_as_relative or amb.z_index == 0, "%s: rain z must be absolute" % rid)
		for n in amb.sway + amb.water:
			var z: int = n.z_index
			_check(z <= 1 and z < int(min_actor_y), "%s: region %s z %d must lie on the picture (≤ 1, under every actor)" % [rid, n.name, z])
			_check(z >= -9, "%s: region %s z %d is under the background" % [rid, n.name, z])
		if amb.footfall != null:
			_check(amb.footfall.prints.z_index == -8, "%s: prints z %d must be −8 (floor)" % [rid, amb.footfall.prints.z_index])
		_free(room)


# --- 4. Parameters ----------------------------------------------------------------------------------

func _test_params() -> void:
	var room := _build("Z2")
	var amb = Builder.of(room)
	var spec: Dictionary = AmbData.room("Z2")
	var rain: Dictionary = spec["rain"]
	var m: ShaderMaterial = amb.rain.material
	_check(is_equal_approx(float(m.get_shader_parameter("intensity")), float(rain["intensity"])), "rain intensity not from data")
	_check(absf(float(m.get_shader_parameter("slant")) - tan(deg_to_rad(float(rain["slant_deg"])))) < 0.0001, "rain slant not from data")
	var l0: Vector4 = m.get_shader_parameter("layer0")
	var l2: Vector4 = m.get_shader_parameter("layer2")
	_check(l0.z < l2.z and l0.x < l2.x and l0.y < l2.y, "far drizzle layer must be slower, shorter and thinner than the near one (%s vs %s)" % [str(l0), str(l2)])
	var strength := float(spec.get("wind", {}).get("strength", 1.0))
	for r in spec["sway_regions"]:
		var n: Node = amb.get_node_or_null("Sway/" + String(r["id"]))
		_check(n != null, "sway %s not built" % r["id"])
		if n == null:
			continue
		var sm: ShaderMaterial = n.material
		_check(is_equal_approx(float(sm.get_shader_parameter("amp_px")), float(r.get("amp_px", 3.0)) * strength), "%s amp_px" % r["id"])
		if r.has("anchor_y"):
			_check(is_equal_approx(float(sm.get_shader_parameter("anchor_y")), float(r["anchor_y"])), "%s anchor_y" % r["id"])
		_check(int(sm.get_shader_parameter("poly_n")) == _poly(r).size(), "%s outline points" % r["id"])
	# Neighbouring regions sway out of step (different phase).
	var phases := {}
	for r in spec["sway_regions"]:
		var n: Node = amb.get_node_or_null("Sway/" + String(r["id"]))
		if n != null:
			phases[float(n.material.get_shader_parameter("phase"))] = true
	_check(phases.size() == spec["sway_regions"].size(), "every sway region needs its own phase, got %d distinct of %d" % [phases.size(), spec["sway_regions"].size()])
	for w in spec["puddles"]:
		var n: Node = amb.get_node_or_null("Water/" + String(w["id"]))
		var rings := float(n.material.get_shader_parameter("rain"))
		var expected := float(rain["intensity"]) * float(spec.get("puddle_style", {}).get("rings", 1.0))
		_check(absf(rings - expected) < 0.001, "puddle %s drop rings %.3f, expected intensity × rings %.3f" % [w["id"], rings, expected])
	_free(room)
	# Interiors: no drop rings anywhere.
	var h2 := _build("H2")
	var a2 = Builder.of(h2)
	_check(a2 != null and a2.rain == null and a2.water.is_empty(), "H2 must have no rain/water")
	_free(h2)


# --- 5. Contacts measured from the sheet ------------------------------------------------------------

class SheetProbe:
	var data: PackedByteArray
	var w: int
	var fw: int
	var fh: int

	func opaque(x: int, y: int) -> bool:
		return data[(y * w + x) * 4 + 3] > 64

	## Lowest opaque row of frame (row r, frame i), frame coordinates.
	func bottom(r: int, i: int) -> int:
		for y in range(fh - 1, -1, -1):
			for x in fw:
				if opaque(i * fw + x, r * fh + y):
					return y
		return -1

	## Occupied columns of the 41-px band above `floor`: [x] → bottom y (−1 = empty).
	func band(r: int, i: int, floor: int) -> PackedInt32Array:
		var out := PackedInt32Array()
		out.resize(fw)
		for x in fw:
			var b := -1
			for y in range(floor, floor - 41, -1):
				if opaque(i * fw + x, r * fh + y):
					b = y
					break
			out[x] = b
		return out

	## Contiguous occupied column runs (width ≥ 4): [x0, x1, bottom].
	static func runs(col: PackedInt32Array) -> Array:
		var out: Array = []
		var x := 0
		while x < col.size():
			if col[x] >= 0:
				var x0 := x
				var b := -1
				while x < col.size() and col[x] >= 0:
					b = maxi(b, col[x])
					x += 1
				if x - x0 >= 4:
					out.append([x0, x - 1, b])
			else:
				x += 1
		return out


func _test_contacts() -> void:
	var ff: Dictionary = AmbData.footfall("agata")
	_check(not ff.is_empty(), "_index.json footfall.agata missing")
	if ff.is_empty():
		return
	var sheet_path := String(ff["sheet"])
	var sprites: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(sheet_path.get_base_dir() + "/sprites.json"))
	var img := Image.load_from_file(ProjectSettings.globalize_path(sheet_path))
	_check(img != null and not img.is_empty(), "cannot read %s" % sheet_path)
	if img == null or img.is_empty():
		return
	img.convert(Image.FORMAT_RGBA8)
	var p := SheetProbe.new()
	p.data = img.get_data()
	p.w = img.get_width()
	p.fw = int(sprites["frame_w"])
	p.fh = int(sprites["frame_h"])
	var n := int(sprites["actions"]["walk"]["frames"])
	_check(n == int(ff["frames"]), "sheet has %d walk frames, data says %d" % [n, int(ff["frames"])])
	var pvx := float(sprites["pivot"]["x"]) * p.fw
	var pvy := float(sprites["pivot"]["y"]) * p.fh
	var floors := PackedInt32Array()
	for r in 8:
		var f := -1
		for i in n:
			f = maxi(f, p.bottom(r, i))
		floors.append(f)
	# Contact = the frame after the leading toe's farthest swing (profile rows 2 → +x, 6 → −x).
	var contacts_by_row := {}
	for rs in [[2, 1], [6, -1]]:
		var r: int = rs[0]
		var sgn: int = rs[1]
		var toes: Array[int] = []
		for i in n:
			var col := p.band(r, i, floors[r])
			var t := -100000
			for x in p.fw:
				if col[x] >= 0:
					t = maxi(t, x * sgn)
			toes.append(t)
		var c: Array[int] = []
		for i in n:
			if toes[i] >= toes[(i - 1 + n) % n] and toes[i] > toes[(i + 1) % n]:
				c.append((i + 1) % n)
		c.sort()
		contacts_by_row[r] = c
	var data_frames: Array = ff["contact_frames"]
	print("    measured contacts: row 2 %s, row 6 %s; data %s" % [str(contacts_by_row[2]), str(contacts_by_row[6]), str(data_frames)])
	_check(contacts_by_row[2] == contacts_by_row[6], "profile rows disagree on the contact frames: %s vs %s" % [str(contacts_by_row[2]), str(contacts_by_row[6])])
	var df: Array[int] = []
	for f in data_frames:
		df.append(int(f))
	_check(df == contacts_by_row[2], "data contact_frames %s ≠ measured %s (walk sheet changed: re-measure)" % [str(df), str(contacts_by_row[2])])
	# Planted foot: the leading run along the travel x (rows 0/4: the lowest run).
	var sx := [0, 1, 1, 1, 0, -1, -1, -1]
	var table: Array = ff["planted_foot_px"]
	for r in 8:
		for k in df.size():
			var rr := SheetProbe.runs(p.band(r, df[k], floors[r]))
			if rr.is_empty():
				_check(false, "row %d frame %d: no feet in the bottom band" % [r, df[k]])
				continue
			var best: Array = rr[0]
			for run in rr:
				if sx[r] == 0:
					if run[2] > best[2]:
						best = run
				elif sx[r] * (run[0] + run[1]) > sx[r] * (best[0] + best[1]):
					best = run
			var off := Vector2((best[0] + best[1]) / 2.0 - pvx, best[2] - pvy)
			var d: Array = table[r][k]
			var dv := Vector2(float(d[0]), float(d[1]))
			_check(off.distance_to(dv) <= 4.0, "row %d contact %d: planted foot measured %s, data %s (> 4 px)" % [r, k, str(off.snapped(Vector2(0.1, 0.1))), str(dv)])


# --- 6. Footfall in Z2 ------------------------------------------------------------------------------

func _walk(from: Vector2, to: Vector2) -> void:
	player.call("enter_room", rm.current_room, from)
	for i in 4:
		await physics_frame
	player.call("walk_to", to)
	var frames := 0
	while player.call("is_walking") and frames < 900:
		await physics_frame
		frames += 1


func _test_footfall() -> void:
	gs.reset()
	await _spawn_main()
	rm.change_room("Z2", "default")
	for i in 4:
		await physics_frame
	var room: Node = rm.current_room
	var amb = Builder.of(room)
	_check(amb != null and amb.footfall != null, "Z2 has no footfall")
	if amb == null or amb.footfall == null:
		return
	var ff = amb.footfall
	var spec: Dictionary = AmbData.room("Z2")
	var contacts: Array[int] = []
	for f in AmbData.footfall("agata")["contact_frames"]:
		contacts.append(int(f))
	# Through the big puddle on the right (puddles and the road between them).
	await _walk(Vector2(1200, 835), Vector2(1790, 862))
	_check(ff.stats()["bound"], "footfall did not bind to Agata's walk sheet")
	var ev: Array = ff.events.duplicate()
	print("    puddle walk: %d steps, %d splashes, %d prints" % [ff.steps, ff.splashes, ff.prints_made])
	_check(ev.size() >= 3, "expected ≥ 3 steps over 590 px, got %d" % ev.size())
	var puddle_steps := 0
	for e in ev:
		_check(int(e["frame"]) in contacts, "a step on sheet frame %d, not a contact frame %s" % [int(e["frame"]), str(contacts)])
		var pos: Vector2 = e["pos"]
		_check(absf(float(e["scale"]) - room.depth_scale(pos.y)) < 0.001, "step scale %.3f ≠ room depth scale %.3f at y %.0f" % [e["scale"], room.depth_scale(pos.y), pos.y])
		if e["surface"] == "puddle":
			puddle_steps += 1
			var in_any := false
			for w in spec["puddles"]:
				if Geometry2D.is_point_in_polygon(pos, _poly(w)):
					in_any = true
			_check(in_any, "splash at %s is not inside a puddle polygon" % str(pos))
			_check(int(e["drops_z"]) >= int(e["feet_y"]) + 1, "drops z %d must be in front of Agata (feet y %d + 1)" % [int(e["drops_z"]), int(e["feet_y"])])
	_check(puddle_steps >= 1 and ff.splashes == puddle_steps, "expected splashes in the puddles: %d puddle steps, %d splashes" % [puddle_steps, ff.splashes])
	# Splash nodes are gone after their life (≤ 0.5 s).
	await create_timer(0.6).timeout
	var left := 0
	var splash_script = load("res://scripts/ambient/ambient_splash.gd")
	for c in amb.get_children():
		if c.get_script() == splash_script:
			left += 1
	_check(left == 0, "%d splash nodes still alive 0.5 s after the walk" % left)
	# Mud: across the road on the left — prints, no splash.
	var p0: int = ff.prints_made
	var s0: int = ff.splashes
	await _walk(Vector2(300, 690), Vector2(560, 700))
	print("    mud walk: %d prints (total %d), splashes +%d" % [ff.prints_made - p0, ff.prints.count(), ff.splashes - s0])
	_check(ff.prints_made - p0 >= 1, "no prints in the mud of the road")
	_check(ff.prints.count() <= ff.prints.max_prints, "more prints than prints_max")
	# Grass corner (no mud, no puddle): steps leave nothing.
	var g0: int = ff.prints_made + ff.splashes
	await _walk(Vector2(200, 1000), Vector2(450, 1040))
	_check(ff.prints_made + ff.splashes - g0 <= 1, "steps on the grass corner left %d prints/splashes" % (ff.prints_made + ff.splashes - g0))


# --- 7. Prints and splash ---------------------------------------------------------------------------

func _test_prints_and_splash() -> void:
	var room := _build("Z2")
	var amb = Builder.of(room)
	var prints = amb.footfall.prints
	var cfg: Dictionary = amb.footfall.cfg
	var maxp := int(cfg["prints_max"])
	var fade := float(cfg["print_fade_s"])
	_check(fade >= 20.0 and fade <= 30.0, "print_fade_s %.1f outside 20–30 s" % fade)
	for i in maxp + 5:
		prints.add(Vector2(600 + i * 20, 800), Vector2.RIGHT, 1.0 if i % 2 == 0 else -1.0)
	_check(prints.count() == maxp, "prints count %d, cap %d" % [prints.count(), maxp])
	_check(prints.alpha_at(0.0) > 0.2, "a fresh print must be visible")
	_check(prints.alpha_at(fade * 0.95) < prints.alpha_at(0.0) * 0.1, "a print must be almost gone near print_fade_s")
	prints.advance(fade * 0.5)
	_check(prints.count() == maxp, "prints must stay for half the fade")
	prints.advance(fade * 0.5 + 0.01)
	_check(prints.count() == 0, "prints must be gone after print_fade_s (%d left)" % prints.count())
	# Splash life and depth scale.
	var Splash = load("res://scripts/ambient/ambient_splash.gd")
	var sizes := []
	for y in [700.0, 1000.0]:
		for part in [0, 1]:
			var s = Splash.new()
			s.part = part
			s.position = Vector2(900, y)
			s.ground = amb.ground
			s.cfg = cfg
			s.seed_value = int(y) + part
			amb.add_child(s)
			s.start()
			_check(s.life >= 0.3 and s.life <= 0.5, "splash life %.2f outside 0.3–0.5 s" % s.life)
			if part == 0:
				_check(s.get("_drops").size() >= int(cfg["splash"]["drops_min"]), "too few drops")
				sizes.append(s.get("_ppm"))
	_check(sizes[0] < sizes[1], "a far splash must be smaller than a near one (%s)" % str(sizes))
	_check(absf(sizes[1] - room.depth_scale(1000.0) * amb.ground.px_per_m) < 0.01, "splash px/m = room depth scale × Agata's px/m")
	await create_timer(0.6).timeout
	var alive := 0
	for c in amb.get_children():
		if c.get_script() == Splash:
			alive += 1
	_check(alive == 0, "%d splashes alive after 0.6 s" % alive)
	_free(room)


# --- 8. Flags ---------------------------------------------------------------------------------------

func _test_flags() -> void:
	gs.reset()
	var room := _build("H1")
	var amb = Builder.of(room)
	_check(amb != null and amb.sway.size() == 4 and amb.dust.size() == 1, "H1 ambient: 4 panes and 1 dust emitter expected")
	if amb == null or amb.dust.is_empty():
		_free(room)
		return
	_check(not amb.sway[0].visible and not amb.dust[0].visible and not amb.dust[0].emitting, "shutters closed: panes and dust must be off")
	gs.set_flag("h1_shutter_open", true)
	_check(amb.sway[0].visible and amb.dust[0].visible and amb.dust[0].emitting, "shutters open: panes and dust must be on")
	gs.set_flag("h1_shutter_open", false)
	_check(not amb.sway[0].visible, "shutters closed again: panes off")
	_free(room)
	gs.reset()
