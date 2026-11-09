extends Line2D
## A line held in the hands while a villager's one-shot clip plays (Director 09.11, 12:35: «Пелагея должна быть
## развернута от нас и быть у каната, а не в воздух тянуть… раз уж она тянет бечеву»): from the middle of both hands'
## grips (Actor3D.hand_grip_frame_px) to a fixed point of the room (`to`, the pier plate where the line goes into the
## water), sagging a little, drawn under the figure — her body hides the hands' end when she stands with her back to
## us. Goes when the clip ends. StoryRunner `npc_act[].rope_to`. (Not «RopeLine»: that class is the crossing's rope, scripts/mechanics.)

var npc: Node2D = null
var to: Vector2 = Vector2.ZERO
var sag: float = 10.0
var _seen := false


static func attach(the_npc: Node2D, point: Vector2, color: Color = Color("#3b2d20"), px: float = 3.0) -> Line2D:
	var r: Line2D = load("res://scripts/actors/hand_line.gd").new()
	r.name = "HandLine"
	r.set("npc", the_npc)
	r.set("to", point)
	r.width = px
	r.default_color = color
	r.antialiased = true
	r.top_level = true
	the_npc.add_child(r)
	return r


func _grip(side: String) -> Vector2:
	var live = npc.get("live")
	if live == null or not is_instance_valid(live) or live.get("view") == null or live.get("body") == null:
		return Vector2.INF
	var px: Vector2 = live.view.call("hand_grip_frame_px", side)
	var b: Sprite2D = live.get("body")
	return b.global_transform * (px + b.offset) if px != Vector2.INF else Vector2.INF


func _process(_delta: float) -> void:
	var live = npc.get("live") if is_instance_valid(npc) else null
	var playing: bool = live != null and is_instance_valid(live) and bool(live.get("once"))
	if playing:
		_seen = true
	elif _seen or live == null:
		queue_free()
		return
	var a := _grip("Left")
	var b := _grip("Right")
	if a == Vector2.INF or b == Vector2.INF:
		visible = false
		return
	visible = true
	var from := (a + b) * 0.5
	clear_points()
	for i in 9:
		var t := float(i) / 8.0
		add_point(from.lerp(to, t) + Vector2(0.0, sag * 4.0 * t * (1.0 - t)))
	z_index = clampi(int(npc.z_index) - 1, -4096, 4096)
	z_as_relative = false
