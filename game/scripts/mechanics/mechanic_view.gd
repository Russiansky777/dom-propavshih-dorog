class_name MechanicView
extends CanvasLayer
## Interactive close-ups of day two (rooms data: hotspot `mechanic: {type, …}`), opened by
## StoryRunner.open_mechanic(): the office mirror on Dunya's stand with the bell (H2), the sluice (M4),
## mother's mirror (H2), the plate on the pier (Z3), the signal lantern (R1), the photo in the mill passage
## (M2). Layer 4 — under GameUi (5): the texts the close-up asks for (StoryRunner.mechanic_say /
## mechanic_event) play in the dialogue box above it, and while a text is on screen the dialogue's modal
## takes the clicks. Everything is done with the mouse; «Закрыть» and Esc put it away. Each type is its own
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
}

var spec: Dictionary = {}
var root: Control = null
var panel: MechanicPanel = null
var title_label: Label = null
var close_button: Button = null
var _players: Array[AudioStreamPlayer] = []
var sounds_played: Array[String] = []   # tests: what the close-up sounded (name per play)


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
	title_label.position = Vector2(40, 96)
	title_label.size = Vector2(900, 60)
	title_label.theme_type_variation = &"CloseupTitle"
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(title_label)
	close_button = Button.new()
	close_button.name = "Close"
	close_button.text = StoryData.text(String(spec.get("close_label", "@ui.close")))
	close_button.size = Vector2(200, 56)
	close_button.position = Vector2(1680, 990)
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(func(): StoryRunner.close_mechanic())
	root.add_child(close_button)
	visible = true
	panel.opened()


func _close() -> void:
	visible = false
	if panel != null and is_instance_valid(panel):
		panel.closing()
	_free_nodes()
	spec = {}


func _free_nodes() -> void:
	if root != null and is_instance_valid(root):
		root.queue_free()
	root = null
	panel = null
	title_label = null
	close_button = null


func play(sound_name: String) -> void:
	sounds_played.append(sound_name)
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
		get_viewport().set_input_as_handled()
		StoryRunner.close_mechanic()


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
