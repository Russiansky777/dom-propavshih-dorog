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

var files: Array = []
var _last := -1


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


func setup(p_files: Array, pos: Vector2, sz: Vector2) -> void:
	files = p_files
	name = "Video"
	expand = true
	volume_db = -80.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = pos
	size = sz
	loop = files.size() == 1
	autoplay = false
	if files.size() > 1:
		finished.connect(_next)


func _ready() -> void:
	_next()   # play() needs the tree


func _next() -> void:
	if files.is_empty():
		return
	var i := 0
	if files.size() > 1:
		i = randi() % (files.size() - 1)
		if i >= _last and _last >= 0:
			i += 1   # any clip but the one that just ended
	_last = i
	stream = load(String(files[i]))
	play()


## Tests and the web probe.
func probe() -> Dictionary:
	return {"files": files, "current": _last, "playing": is_playing(), "loop": loop, "position": stream_position}
