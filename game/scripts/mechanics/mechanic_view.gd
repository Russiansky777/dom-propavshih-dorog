class_name MechanicView
extends CanvasLayer
## Interactive close-ups of day two (rooms data: hotspot `mechanic: {type, …}`), opened by
## StoryRunner.open_mechanic(): the office mirror on Dunya's stand with the bell (H2), the sluice (M4),
## mother's mirror (H2), the plate on the pier (Z3), the signal lantern (R1), the photo in the mill passage
## (M2); day three's optional stories — the old map of Olkhovka, the way shown by clicks (O1, Q02), the second bench in
## Ilya's workshop (O4, Q06). Layer 4 — under GameUi (5): the texts the close-up asks for (StoryRunner.mechanic_say /
## mechanic_event) play in the dialogue box above it, and while a text is on screen the dialogue's modal
## takes the clicks. Everything is done with the mouse; «Закрыть» and Esc put it away (a mini-game's «Хватит» — with
## its farewell, `close_event`). Each type is its own
## panel (MechanicPanel subclass) built from the spec; the story state they change goes through
## StoryRunner.mechanic_event(name) → `events.<name>` in data.

const LAYER := 4
const PANELS := {
	"office_mirror": preload("res://scripts/mechanics/office_mirror_panel.gd"),
	"sluice": preload("res://scripts/mechanics/sluice_panel.gd"),
	"fast_mirror": preload("res://scripts/mechanics/fast_mirror_panel.gd"),
	"plate": preload("res://scripts/mechanics/plate_panel.gd"),
	"lantern": preload("res://scripts/mechanics/lantern_panel.gd"),
	"photo": preload("res://scripts/mechanics/photo_panel.gd"),
	"windlass": preload("res://scripts/mechanics/windlass_panel.gd"),
	"latch": preload("res://scripts/mechanics/latch_panel.gd"),
	"crossing": preload("res://scripts/mechanics/crossing_panel.gd"),
	"map_route": preload("res://scripts/mechanics/map_route_panel.gd"),
	"workbench": preload("res://scripts/mechanics/workbench_panel.gd"),
	"tictactoe": preload("res://scripts/mechanics/tictactoe_panel.gd"),
	"rhythm": preload("res://scripts/mechanics/rhythm_panel.gd"),
	"fishing": preload("res://scripts/mechanics/fishing_panel.gd"),
}

var spec: Dictionary = {}
var root: Control = null
var panel: MechanicPanel = null
var title_label: Label = null
var close_button: Button = null
var _players: Array[AudioStreamPlayer] = []
var sounds_played: Array[String] = []   # tests: what the close-up sounded (name per play)
var _close_sent: bool = false


func _ready() -> void:
	layer = LAYER
	visible = false
	StoryRunner.mechanic_opened.connect(_open)
	StoryRunner.mechanic_closed.connect(_close)
	for i in 4:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX" if AudioServer.get_bus_index("SFX") >= 0 else &"Master"
		p.volume_db = -8.0
		add_child(p)
		_players.append(p)


func is_open() -> bool:
	return visible and root != null


func _open(s: Dictionary) -> void:
	_free_nodes()
	spec = s
	var script = PANELS.get(String(spec.get("type", "")))
	if script == null:
		push_error("MechanicView: unknown mechanic type %s" % String(spec.get("type", "")))
		StoryRunner.close_mechanic.call_deferred()
		return
	root = Control.new()
	root.name = "Mechanic"
	root.size = Vector2(1920, 1080)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.theme = UiTheme.get_theme()
	add_child(root)
	var bg := ColorRect.new()
	bg.name = "Backdrop"
	bg.color = Color(0.04, 0.035, 0.03, 1.0)
	bg.size = root.size
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# `in_room: true` (the fishing on the jetty, 01.11): no backdrop — the game goes on over the room itself, the
	# player sees where she stands; the panel draws its float and rod in screen coordinates (= room coordinates).
	bg.visible = not bool(spec.get("in_room", false))
	root.add_child(bg)
	panel = script.new()
	panel.name = "Panel"
	panel.view = self
	panel.spec = spec
	panel.size = root.size
	root.add_child(panel)
	panel.build()
	title_label = Label.new()
	title_label.name = "Title"
	title_label.text = StoryData.text(String(spec.get("title", "")))
	# 14.11: `title_pos` — a panel with a frame of its own (mother's mirror) puts the title over the frame's left edge
	var tp: Array = spec.get("title_pos", [40, 96])
	title_label.position = Vector2(float(tp[0]), float(tp[1]))
	title_label.size = Vector2(900, 60)
	title_label.theme_type_variation = &"CloseupTitle"
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(title_label)
	_title_plate()
	close_button = Button.new()
	close_button.name = "Close"
	close_button.text = StoryData.text(String(spec.get("close_label", "@ui.close")))
	close_button.size = Vector2(200, 56)
	close_button.position = Vector2(1680, 990)
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(close_pressed)
	root.add_child(close_button)
	_close_sent = false
	# `closable: false` — no «Закрыть», no Esc (the crossing: the boat is on the rope, the only way is across).
	close_button.visible = bool(spec.get("closable", true))
	visible = true
	panel.opened()


## The title of a mini-game played over a whole picture lies on the same dark plate as its hint (Director 16.11,
## 14:55: «Заголовки — дай одну картинкой, как было и как может стать»): such a panel has put a plate under its hint
## (MechanicPanel.plate) — on the dark backdrop there is none and the title needs none. A hint right under the title
## (the fishing) shares one plate with it; elsewhere the title gets a plate of its own.
const TITLE_JOIN_PX := 40.0


func _title_plate() -> void:
	var plates: Array = panel.find_children("*", "HintPlate", true, false)
	if plates.is_empty() or title_label.text.strip_edges() == "":
		return
	var tw := HintPlate.words_of(title_label)
	for p in plates:
		var hp := p as HintPlate
		hp.fit()
		if hp.words.size.x > 0.0 and absf(hp.words.position.x - tw.position.x) < TITLE_JOIN_PX \
				and hp.words.position.y - tw.end.y < TITLE_JOIN_PX and hp.words.position.y > tw.position.y:
			hp.labels.append(title_label)
			hp.fit()
			return
	HintPlate.under([title_label])


func _close() -> void:
	visible = false
	if panel != null and is_instance_valid(panel):
		panel.closing()
	_free_nodes()
	spec = {}


func _free_nodes() -> void:
	if root != null and is_instance_valid(root):
		remove_child(root)   # ревью 01.11 (В-17): the next «Mechanic» keeps its name (no «Mechanic2» while the old one waits to be freed)
		root.queue_free()
	root = null
	panel = null
	title_label = null
	close_button = null


## «Закрыть» / Esc. The mini-games put it away with a word (J, часть G: one way out for every close-up, bottom right —
## not a «Хватит» of their own beside «Закрыть»): `close_label` names the button («Хватит»), `close_event` is the
## spec's event it fires (Ulyana's «Ладно. Завтра ещё сыграем…», the flags of having played, then the close).
func close_pressed() -> void:
	var ev := String(spec.get("close_event", ""))
	if ev == "":
		StoryRunner.close_mechanic()
		return
	if _close_sent:
		return
	_close_sent = true
	if close_button != null:
		close_button.disabled = true
	if not StoryRunner.mechanic_event(ev):
		StoryRunner.close_mechanic()


func play(sound_name: String) -> void:
	sounds_played.append(sound_name)
	var pad := get_node_or_null("/root/PadInput")
	if pad != null:
		pad.rumble_for(sound_name)   # Steam Deck: the jolt with the sound (data/story/rumble.json)
	for p in _players:
		if not p.playing:
			p.stream = SynthSfx.stream(sound_name)
			p.play()
			return
	_players[0].stream = SynthSfx.stream(sound_name)
	_players[0].play()


func _input(event: InputEvent) -> void:
	if not is_open():
		return
	if event is InputEventKey and event.pressed and not event.echo and \
			(event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE):
		# ревью 01.11 (Б-6): a close-up that cannot be closed (the crossing, the windlass) lets Esc through to the
		# pause menu instead of eating it — the player can still save or leave from inside it
		if not bool(spec.get("closable", true)):
			return
		get_viewport().set_input_as_handled()
		if bool(spec.get("closable", true)):
			# a game's farewell (`close_event`) waits for the text on screen; a plain close-up goes at once, as before
			if String(spec.get("close_event", "")) != "" and not StoryRunner.current_beat.is_empty():
				return
			close_pressed()


## Click targets and state for tests and the web probe (window.probeState.mechanic).
func probe() -> Dictionary:
	var out := {"open": is_open(), "type": String(spec.get("type", "")), "hotspot": String(spec.get("hotspot", ""))}
	if not is_open() or panel == null:
		return out
	out["close"] = _center(close_button)
	out["panel"] = panel.probe()
	return out


static func _center(c: Control) -> Dictionary:
	if c == null:
		return {}
	var r := c.get_global_rect()
	return {"x": r.position.x + r.size.x / 2, "y": r.position.y + r.size.y / 2}
