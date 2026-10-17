class_name RoomLighting
extends Node2D
## Light, fire and cast shadows of a room, built from data/story/lights/<LOC>.json (a room without
## that file has no lighting node). RoomBuilder calls `RoomLighting.build(room, room_id)` once the
## room is assembled (one hook line). The node `Lighting` holds one LightSource per `sources[]`
## entry and:
##   - re-reads flags on GameState.flag_changed (fades over each source's `fade_s`), jumps to the
##     final state on state_reset / state_loaded (a save never replays a transition);
##   - drives the flicker groups (one noise per `flicker.group`, shared by the fire, its light and
##     the shadows it casts);
##   - attaches an ActorLightShadow to every actor sprite (the player when this room is the current
##     one, NpcActor children of the room) for every source with `casts_actor_shadow`; the ones on
##     the player are removed when the room leaves the tree (the player outlives rooms);
##   - holds the room's LIGHT MAP (SubViewport, 1/4 resolution) where ambient / point / mask sources
##     draw; the room's art (Background, Layers, Occluders, Props, Hotspot images) gets
##     shaders/light_receive.gdshader and multiplies by it — one extra texture read per pixel;
##   - tones the actors' sprites instead of lighting them per pixel (self_modulate;
##     children such as the shadows are untouched): the light the room's sources give at the
##     figure (ambient, the masks under the feet, the point lights at the chest — the same field the
##     floor gets) × the `actor_tint` of present sources (the art of the figures is lighter than the
##     rooms: the dark H1 brings Agata to the floor's brightness) + `actor_warm` of near fires/lamps
##     by floor distance — eased, no jumps; the player gets its own lighting back when the room leaves;
##   - `suppress_effects`: ids of rooms/<LOC>.json `effects[]` this lighting replaces (the old
##     particle "fire" of the H1 stove) — removed at build time, the room data stays untouched.
## Nothing here takes input: lights, quads and shadows are not in the physics picking.

const DATA_DIR := "res://data/story/lights"
const RECEIVE_SHADER: Shader = preload("res://shaders/light_receive.gdshader")
const LM_DIV := 4
## Room parts whose art takes the light map (RoomBuilder's containers).
const RECEIVERS := ["Background", "Layers", "Occluders", "Props", "Hotspots"]
## Off only for measurements (LightProbe: FPS with and without lighting).
static var enabled: bool = true
## Off only for measurements (shots_lighting.gd "pair": the same instant on neutral light).
static var tone_enabled: bool = true
const RESCAN_S := 0.5

var room_id: String = ""
var data: Dictionary = {}
var foreshortening: float = 0.42
var sources: Array[LightSource] = []
var groups: Dictionary = {}          # group id -> LightFlicker
var shadows: Dictionary = {}         # "<actor instance id>:<source id>" -> ActorLightShadow
var extra_actors: Array[Node] = []   # tests: actors tracked besides the player / NpcActors
var tones: Dictionary = {}          # actor instance id -> current tone (Color)
var light_map: SubViewport = null    # ambient / point / mask sources draw here
var receive_material: ShaderMaterial = null
var time_s: float = 0.0
const TONE_RATE := 8.0
var _rescan_t: float = 0.0


static func data_path(id: String) -> String:
	return "%s/%s.json" % [DATA_DIR, id]


static func load_data(id: String) -> Dictionary:
	var path := data_path(id)
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("RoomLighting: %s is not a JSON object" % path)
		return {}
	return parsed


## Hook for RoomBuilder: adds `Lighting` to the room when lights/<room_id>.json exists.
static func build(room: Node2D, id: String) -> RoomLighting:
	LightProbe.register()  # web only, with ?lightprobe in the URL (tools/light_fps.mjs); once
	if not enabled:
		return null
	var spec := load_data(id)
	if spec.is_empty():
		return null
	var fx := room.get_node_or_null("Effects")
	for eid in spec.get("suppress_effects", []):
		var n: Node = fx.get_node_or_null(NodePath(String(eid))) if fx != null else null
		if n != null:
			fx.remove_child(n)
			n.free()
	var rl := RoomLighting.new()
	rl.name = "Lighting"
	rl.room_id = id
	rl.data = spec
	rl.foreshortening = float(spec.get("floor_foreshortening", 0.42))
	room.add_child(rl)
	for s in spec.get("sources", []):
		if not (s is Dictionary):
			continue
		var src := LightSource.new()
		rl.add_child(src)
		src.setup(s, rl._group_flicker(s.get("flicker", {})))
		rl.sources.append(src)
		if src.lm != null:
			rl._lm_root().add_child(src.lm)
	if rl.light_map != null:
		rl.receive_material = ShaderMaterial.new()
		rl.receive_material.shader = RECEIVE_SHADER
		for part in RECEIVERS:
			var n := room.get_node_or_null(NodePath(part))
			if n != null:
				rl._receive(n)
	return rl


## The light map: a SubViewport at 1/LM_DIV of the canvas, its content scaled to match, cleared to
## LightSource.LM_SCALE (light 1 = the art as painted) by a full-frame base sprite.
func _lm_root() -> Node2D:
	if light_map != null:
		return light_map.get_node("Root")
	light_map = SubViewport.new()
	light_map.name = "LightMap"
	light_map.size = Vector2i(1920 / LM_DIV, 1080 / LM_DIV)
	light_map.disable_3d = true
	light_map.transparent_bg = false
	light_map.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	light_map.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	add_child(light_map)
	var root := Node2D.new()
	root.name = "Root"
	root.scale = Vector2.ONE / float(LM_DIV)
	light_map.add_child(root)
	var base := Sprite2D.new()
	base.name = "Base"
	base.texture = LightSource.white_texture()
	base.centered = false
	base.scale = Vector2(1920.0, 1080.0) / float(LightSource.QUAD_SIZE)
	var v := LightSource.LM_SCALE
	base.self_modulate = Color(v, v, v, 1.0)
	root.add_child(base)
	return root


## Room art drawn under the light map: every Sprite2D / Polygon2D below `n` that has no material of
## its own (labels, other systems' shaded nodes and this lighting are left alone).
func _receive(n: Node) -> void:
	if n == self:
		return
	if (n is Sprite2D or n is Polygon2D or n is AnimatedSprite2D) and (n as CanvasItem).material == null:
		(n as CanvasItem).material = receive_material
	for c in n.get_children():
		_receive(c)


func _group_flicker(spec) -> LightFlicker:
	if not (spec is Dictionary) or spec.is_empty():
		return null
	var gid := String(spec.get("group", ""))
	if gid == "":
		return LightFlicker.new(spec, hash(room_id + str(groups.size())))
	if not groups.has(gid):
		groups[gid] = LightFlicker.new(spec, hash(room_id + ":" + gid))
	return groups[gid]


func _ready() -> void:
	if receive_material != null and light_map != null:
		receive_material.set_shader_parameter("room_light_tex", light_map.get_texture())
	process_priority = 20  # after the player's foot lock (10): shadows read this frame's position
	GameState.flag_changed.connect(_on_flag_changed)
	GameState.state_reset.connect(_on_state_snap)
	GameState.state_loaded.connect(_on_state_loaded)
	RoomManager.room_changed.connect(_on_room_changed)
	scan_actors.call_deferred()


func _exit_tree() -> void:
	if GameState.flag_changed.is_connected(_on_flag_changed):
		GameState.flag_changed.disconnect(_on_flag_changed)
	if GameState.state_reset.is_connected(_on_state_snap):
		GameState.state_reset.disconnect(_on_state_snap)
	if GameState.state_loaded.is_connected(_on_state_loaded):
		GameState.state_loaded.disconnect(_on_state_loaded)
	if RoomManager.room_changed.is_connected(_on_room_changed):
		RoomManager.room_changed.disconnect(_on_room_changed)
	# The player outlives the room: back to its own colours (the next room tones it again).
	var pl: Node2D = RoomManager.player
	if pl != null and is_instance_valid(pl):
		var spr = pl.get("sprite")
		if spr is CanvasItem and tones.has(pl.get_instance_id()):
			spr.self_modulate = Color.WHITE
	tones.clear()
	# Shadows on actors that outlive the room (the player) go now, not at the end of the frame.
	for key in shadows.keys():
		var sh = shadows[key]
		if is_instance_valid(sh):
			var p: Node = sh.get_parent()
			if p != null:
				p.remove_child(sh)
			sh.queue_free()
	shadows.clear()


func _on_flag_changed(_f: String, _v: bool) -> void:
	for s in sources:
		s.refresh(false)


func _on_state_snap() -> void:
	for s in sources:
		s.refresh(true)


func _on_state_loaded(_slot: String) -> void:
	_on_state_snap()


func _on_room_changed(_id: String) -> void:
	scan_actors()


func _process(delta: float) -> void:
	time_s += delta
	for s in sources:
		s.step(delta, time_s)
	_update_tones(delta)
	_rescan_t += delta
	if _rescan_t >= RESCAN_S:
		_rescan_t = 0.0
		scan_actors()


## The light in the room: true when a source is on (tests / probes).
func source(id: String) -> LightSource:
	for s in sources:
		if s.source_id == id:
			return s
	return null


func shadow_sources() -> Array[LightSource]:
	var out: Array[LightSource] = []
	for s in sources:
		if s.casts_shadow:
			out.append(s)
	return out


## Actors that get cast shadows here: the player (only while this room is the current one),
## NpcActor children of the room, and `extra_actors` (tests).
func actors() -> Array[Node]:
	var out: Array[Node] = []
	var room := get_parent()
	var p: Node2D = RoomManager.player
	if p != null and is_instance_valid(p) and p.is_inside_tree() and RoomManager.current_room == room:
		out.append(p)
	if room != null:
		for c in room.get_children():
			if c is NpcActor:
				out.append(c)
	for a in extra_actors:
		if is_instance_valid(a) and not out.has(a):
			out.append(a)
	return out


func scan_actors() -> void:
	if not is_inside_tree():
		return
	_update_tones(0.0)  # new actors are toned before their first drawn frame (snap)
	var casters := shadow_sources()
	if casters.is_empty():
		return
	for a in actors():
		var spr = a.get("sprite")
		if not (spr is AnimatedSprite2D) or not is_instance_valid(spr):
			continue
		for s in casters:
			var key := "%d:%s" % [a.get_instance_id(), s.source_id]
			if shadows.has(key) and is_instance_valid(shadows[key]):
				continue
			shadows[key] = ActorLightShadow.attach(spr, s, foreshortening)


## Tone of a figure with feet at `feet` and figure height `fig_h` (screen px):
## (1 + Σ light_on_actor) × room actor_tint × Π source actor_tint + Σ actor_warm, then two guards
## (coordinator 18.10: «тон комнаты не обесцвечивает актёров» — Agata's brown coat stays brown):
##   - no cold cast stronger than `actor_max_cool` (data, default 0.04): green and blue may exceed
##     red by at most that fraction — a bluish multiply is what greys a brown figure;
##   - brightness (Rec.709 luminance of the tone) capped at `actor_max_gain` (default 1.05), the hue
##     kept: a fire or a sunny floor tints the figure, it does not bleach it.
## Multiplying keeps the figure's own saturation (each channel scaled), the guards keep the shift light.
func actor_tone_at(feet: Vector2, fig_h: float = 500.0) -> Color:
	var chest := feet  # point lights read at the feet too: the figure gets what the floor by her gets
	var lit := Color(1, 1, 1, 1)
	var m := Color.WHITE
	var rt = data.get("actor_tint")  # room grade: figures take the room's colour (warm workshop)
	if rt is Array and rt.size() >= 3:
		m = Color(float(rt[0]), float(rt[1]), float(rt[2]), 1.0)
	var add := Color(0, 0, 0, 0)
	for s in sources:
		var l := s.light_on_actor(feet, chest)
		lit = Color(lit.r + l.r, lit.g + l.g, lit.b + l.b, 1.0)
		var t := s.actor_tint()
		m = Color(m.r * t.r, m.g * t.g, m.b * t.b, 1.0)
		add += s.actor_warm(feet, foreshortening)
	var r := maxf(lit.r * m.r + add.r, 0.0)
	var g := maxf(lit.g * m.g + add.g, 0.0)
	var b := maxf(lit.b * m.b + add.b, 0.0)
	var cool := float(data.get("actor_max_cool", 0.04))
	g = minf(g, r * (1.0 + cool))
	b = minf(b, r * (1.0 + cool))
	var lum := r * 0.2126 + g * 0.7152 + b * 0.0722
	var cap := float(data.get("actor_max_gain", 1.05))
	if lum > cap:
		var k := cap / lum
		r *= k
		g *= k
		b *= k
	return Color(r, g, b, 1.0)


## Eases every actor's sprite towards its tone (first sight: at once, no fade from white).
func _update_tones(delta: float) -> void:
	if sources.is_empty():
		return
	var w := 1.0 - exp(-delta * TONE_RATE)
	for a in actors():
		var spr = a.get("sprite")
		if not (spr is AnimatedSprite2D) or not is_instance_valid(spr):
			continue
		var fig_h: float = -spr.offset.y * absf(spr.get_global_transform().get_scale().y)
		var target := actor_tone_at(spr.global_position, fig_h) if tone_enabled else Color.WHITE
		var key: int = a.get_instance_id()
		var cur: Color = tones[key].lerp(target, w) if tones.has(key) else target
		tones[key] = cur
		spr.self_modulate = cur


## Cast shadows currently attached to `actor` (tests).
func shadows_of(actor: Node) -> Array:
	var out: Array = []
	for key in shadows.keys():
		if String(key).begins_with("%d:" % actor.get_instance_id()) and is_instance_valid(shadows[key]):
			out.append(shadows[key])
	return out
