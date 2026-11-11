class_name FrameVideo
extends VideoStreamPlayer
## A painted frame alive (Director 08.11, 21:57 — 09.11, 00:29: the hugs, then the epilogue dinner): Ogg Theora clips
## made from the painting itself (tools/video_loop.py from a fal.ai image-to-video clip — every clip starts and ends in
## the painting) play over the picture at its place and scale, silent. Data `background`:
##   "video": "res://…/loop.ogv"                      — one clip, looped (the hugs);
##   "videos": [{"if": [flags], "unless": [flags], "files": ["res://…/a.ogv", "res://…/b.ogv"]}, …]
##                                                      — the first entry whose flags hold (StateLayer rules: `if` all
##                                                        set, `unless` none set); with several files the clips take
##                                                        turns at random, never the same one twice in a row — a long
##                                                        scene (the dinner, ~90 s) does not show the same 10 s over
##                                                        and over; one file loops.
## The picture under the player stays: the first frame while the stream opens, and the frame as it was without the
## file. The room's lights (RoomLighting) shade the player like the picture.
## Director 09.11, 12:35 («Уля вообще не приходит при этом на видео»): the clips were picked once, when the frame was
## built — the dinner opens without Ulyana and «Ульяна пришла» (ep_ulyana_came) is set later, at the door's line, so the
## video stayed on the family without her. Now a flag change picks again (`bg` kept): other clips → the new one at once.

## Director 09.11, 21:58 / 22:32 («экран „моргает“ постоянно в последней сцене… микросекунда… целиком»): a new stream
## starts with an empty (transparent) texture and gets its first picture only at the player's next update — when one
## clip ended and the next began (every 10 s at the dinner), one drawn frame showed the painting under the player: the
## empty room, the family gone for a blink. Now the picture the player showed last stays over it (`Hold`, the old
## stream's own texture — no copy) until the new clip has drawn. Test FV-7 (the clip's natural end, every frame watched).

## Director 10.11, 16:01 / 19:04 (the hugs in 1080p: «это явно не кадр в кадр склейка» → «ок, давай второй вариант»):
## `"video_intro": "res://…/intro.ogv"` beside `video` — the intro plays once, from the painting to the pose where the
## loop begins; the loop then goes round with no cross-fade into the painting (tools/video_loop.py --from --to --intro:
## the loop's last frame is the clip's frame right before its first one). Two players, so that nothing is opened at
## the join: this one holds the loop — opened, started and paused at its beginning; a child (`Intro`) plays the intro
## over it; when the intro ends the loop is let go, and the intro's last picture stays on top for the two frames the
## loop needs to draw (the same reason as `Hold` below). Test FV-8.

var files: Array = []
var bg: Dictionary = {}
var intro_file := ""
## tests (FV-8 self-check): false — the loop starts at once, as if the room named no intro
static var intro_enabled := true
## tests: false — frames build as without their files (the drawn layers marked `unless_video`). Since 10.11 every flag
## combination of the dinner has clips (no cup chosen — the blue ones), so the layer checks need the clip-less build.
static var videos_enabled := true
var _intro: VideoStreamPlayer = null
var _intro_ended := false
var _intro_frames := 0           # frames since the intro ended
var _loop_drawn := 0             # of them, with the loop already playing
const INTRO_OFF_AFTER := 2
var _last := -1
## tests (FV-7 self-check): false — the stream changes as before, with the empty frame
var hold_enabled := true
var _hold: TextureRect = null
var _hold_frames := 0
const HOLD_FRAMES := 3
const HOLD_MIN_S := 0.1          # of the new stream played before the cover goes
const HOLD_MAX_FRAMES := 30
var _hold_total := 0


static func pick(bg: Dictionary) -> Array:
	var single := String(bg.get("video", ""))
	var out: Array = []
	for e in bg.get("videos", []):
		if not (e is Dictionary):
			continue
		if not _holds(e):
			continue
		for f in e.get("files", []):
			if ResourceLoader.exists(String(f)):
				out.append(String(f))
		if not out.is_empty():
			return out
	if single != "" and ResourceLoader.exists(single):
		out.append(single)
	return out


static func _holds(e: Dictionary) -> bool:
	for f in e.get("if", []):
		if not GameState.has_flag(String(f)):
			return false
	for f in e.get("unless", []):
		if GameState.has_flag(String(f)):
			return false
	return true


func setup(p_files: Array, pos: Vector2, sz: Vector2, p_bg: Dictionary = {}) -> void:
	files = p_files
	bg = p_bg
	name = "Video"
	expand = true
	volume_db = -80.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = pos
	size = sz
	loop = files.size() == 1
	autoplay = false
	finished.connect(_on_finished)
	intro_file = String(bg.get("video_intro", ""))
	if not intro_enabled or files.size() != 1 or intro_file == "" or not ResourceLoader.exists(intro_file):
		intro_file = ""


func _ready() -> void:
	set_process(false)
	_next()   # play() needs the tree
	if intro_file != "":
		_start_intro()
	if not bg.is_empty() and not GameState.flag_changed.is_connected(_on_flag):
		GameState.flag_changed.connect(_on_flag)


func _exit_tree() -> void:
	if GameState.flag_changed.is_connected(_on_flag):
		GameState.flag_changed.disconnect(_on_flag)


func _on_finished() -> void:
	if files.size() > 1:
		_next()


## A story flag changed while the frame is shown: the variant's clips again; different ones start at once.
func _on_flag(_flag: String, _value: bool) -> void:
	var now := pick(bg)
	if now.is_empty() or now == files:
		return
	files = now
	_last = -1
	loop = files.size() == 1
	_next()


func _next() -> void:
	if files.is_empty():
		return
	var i := 0
	if files.size() > 1:
		i = randi() % (files.size() - 1)
		if i >= _last and _last >= 0:
			i += 1   # any clip but the one that just ended
	_last = i
	var shown: Texture2D = get_video_texture() if stream != null else null
	stream = load(String(files[i]))
	play()
	if hold_enabled and shown != null:
		_cover(shown)


## The loop waits at its beginning; the intro plays over it, once (see the header).
func _start_intro() -> void:
	paused = true
	_intro = VideoStreamPlayer.new()
	_intro.name = "Intro"
	_intro.expand = true
	_intro.volume_db = -80.0
	_intro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro.use_parent_material = true   # the room's lights shade it like the player
	_intro.size = size
	_intro.stream = load(intro_file)
	_intro.finished.connect(_on_intro_finished)
	add_child(_intro)
	_intro.play()


func _on_intro_finished() -> void:
	_intro_ended = true
	_intro_frames = 0
	_loop_drawn = 0
	paused = false
	set_process(true)


## The last picture of the stream that has just gone stays on top for a few frames (see the header).
func _cover(tex: Texture2D) -> void:
	if _hold == null:
		_hold = TextureRect.new()
		_hold.name = "Hold"
		_hold.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_hold.stretch_mode = TextureRect.STRETCH_SCALE
		_hold.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_hold)
	_hold.position = Vector2.ZERO
	_hold.size = size
	_hold.material = material   # the room's lights shade it like the player
	_hold.texture = tex
	_hold.visible = true
	_hold_frames = HOLD_FRAMES
	_hold_total = 0
	set_process(true)


func _process(_delta: float) -> void:
	if _intro != null and _intro_ended:
		# the intro's last picture goes when the loop has drawn (half a second at the most)
		_intro_frames += 1
		if stream_position > 0.0:
			_loop_drawn += 1
		if _loop_drawn >= INTRO_OFF_AFTER or _intro_frames >= HOLD_MAX_FRAMES:
			_intro.queue_free()
			_intro = null
	if _hold_frames <= 0:
		if _intro == null or not _intro_ended:
			set_process(false)
		return
	_hold_frames -= 1
	_hold_total += 1
	# not before the new clip has really drawn: a few frames AND a tenth of a second of the new stream played (a slow
	# disk or decoder — the Director's machine showed the blink as «a whole black screen» — takes longer than three
	# frames to give the first picture); half a second at the most
	if _hold_frames == 0 and stream_position < HOLD_MIN_S and _hold_total < HOLD_MAX_FRAMES:
		_hold_frames = 1
	if _hold_frames == 0 and _hold != null:
		_hold.visible = false
		_hold.texture = null


## Tests and the web probe.
func probe() -> Dictionary:
	return {"files": files, "current": _last, "playing": is_playing(), "loop": loop, "position": stream_position,
		"intro": intro_file, "intro_on": _intro != null, "intro_position": _intro.stream_position if _intro != null else -1.0}
