extends SceneTree
## Regression checks for per-instance clips and listen mapped to idle (06.11, 21:16: proposed by the reviewing AI after
## the Director sent it the animations; brought in as given).
## godot --headless --fixed-fps 60 --path game -s res://tests/test_animation_state.gd

const DT := 1.0 / 60.0
var failures := 0


class SheetStub extends RefCounted:
	var texture_scale := 2.25


class NpcStub extends Node2D:
	var sprite: Sprite2D
	var sheet = SheetStub.new()


func _initialize() -> void:
	_run()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _make_live(spec: Dictionary) -> NpcLive3D:
	var npc := NpcStub.new()
	npc.sprite = Sprite2D.new()
	npc.add_child(npc.sprite)
	root.add_child(npc)
	var live := NpcLive3D.new()
	npc.add_child(live)
	if not live.setup(npc, spec, 0.55):
		_check(false, "Actor setup failed")
		return null
	live.view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	return live


func _tick(live: NpcLive3D, frames: int) -> void:
	for frame in frames:
		live.process(DT)
		await process_frame


func _run() -> void:
	await process_frame
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/pavel.json"))
	# These checks isolate the clip/state logic from clothing clearance and foot IK.
	spec["rt3d"].erase("arm_body")
	spec["rt3d"].erase("feet")
	spec["rt3d"].erase("arm_hang")
	var first := _make_live(spec)
	if first == null:
		quit(1)
		return
	var second_spec := spec.duplicate(true)
	second_spec["rt3d"]["smooth"] = {"sigma_frames": 0.0}
	var second := _make_live(second_spec)
	if second == null:
		quit(1)
		return
	var first_clip := first.view.anim.get_animation(first.view.clips["talk"])
	var second_clip := second.view.anim.get_animation(second.view.clips["talk"])
	_check(first_clip != second_clip, "Two actor instances share an Animation resource")
	_check(first_clip.has_meta("kinks_smoothed"), "First actor did not apply configured smoothing")
	_check(not second_clip.has_meta("kinks_smoothed"), "Second actor inherited the first actor's preprocessing metadata")
	var cached_model := (load(String(spec["rt3d"]["scene"])) as PackedScene).instantiate()
	var cached_player := first.view._find(cached_model, "AnimationPlayer") as AnimationPlayer
	var cached_clip := cached_player.get_animation(first.view.clips["talk"])
	_check(not cached_clip.has_meta("kinks_smoothed"), "Actor setup changed the cached imported clip")
	var track := first_clip.add_track(Animation.TYPE_VALUE)
	first_clip.track_set_path(track, NodePath("ReviewOnly:marker"))
	first_clip.track_insert_key(track, 0.0, 17)
	_check(first_clip.get_track_count() == second_clip.get_track_count() + 1, "Animation track data is shared across instances")
	_check(cached_clip.get_track_count() == second_clip.get_track_count(), "Animation edits reached the cached imported clip")
	first_clip.remove_track(track)
	cached_model.free()
	second.get_parent().queue_free()
	await process_frame

	_check(first._state_action("idle") == "", "Idle incorrectly requests an action")
	_check(first._state_action("talk") == "talk", "Talk no longer requests its clip")
	_check(first._state_action("listen") == "", "Listen mapped to idle requests a duplicate action")
	first.set_state("talk")
	await _tick(first, 120)
	_check(first.act_w > 0.99 and first.view.shown_act_w() > 0.99, "Talk did not fade in")
	first.set_state("listen")
	_check(first.act_name == "talk", "Listen alias replaced the fading talk clip immediately")
	await _tick(first, 120)
	_check(first.act_w < 0.001 and first.view.shown_act_w() < 0.001, "Listen alias kept the action layer active")
	_check(first.view.life.idle_weight > 0.99, "Living motion did not return while listening in idle")

	# The imported listen animation remains available even when data aliases listen to idle.
	var distinct := ""
	for clip_name in first.view.anim.get_animation_list():
		if String(clip_name).get_file().get_slice(".", 0) == "listen":
			distinct = clip_name
	_check(distinct != "", "Test model is missing its distinct listen clip")
	if distinct != "":
		first.view.clips["listen"] = distinct
		_check(first._state_action("listen") == "listen", "Distinct listen clip was treated as idle")
		first.set_state("listen")
		await _tick(first, 180)
		_check(first.act_name == "listen" and first.view.shown_act_w() > 0.99, "Distinct listen did not fade in")

	# One-shot callers use the same action path and must still complete and fade out.
	_check(first.play_once("talk"), "Existing one-shot clip was rejected")
	await _tick(first, 180)
	_check(first.once_busy() and first.view.shown_act_w() > 0.99, "One-shot action was disabled by state routing")
	var duration := first.view.action_length("talk")
	await _tick(first, int(ceil((duration + 2.0) / DT)))
	_check(not first.once_busy(), "One-shot action failed to finish")
	_check(first.view.shown_act_w() < 0.001, "Completed one-shot failed to fade out")
	_check(first.play_once("talk", true), "Held one-shot clip was rejected")
	await _tick(first, int(ceil((duration + 2.0) / DT)))
	_check(first.once_busy() and first.view.shown_act_w() > 0.99, "Held one-shot did not retain its final pose")
	first.release_once()
	await _tick(first, 120)
	_check(not first.once_busy() and first.view.shown_act_w() < 0.001, "Released one-shot failed to fade out")
	first.get_parent().queue_free()
	await process_frame
	print("Animation state regressions: %s" % ("PASS" if failures == 0 else "%d failures" % failures))
	quit(0 if failures == 0 else 1)
