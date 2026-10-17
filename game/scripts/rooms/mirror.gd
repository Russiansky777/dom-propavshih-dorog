extends Node2D
## The mirror shows the present-day view from its former place (the mill office).
## Not a portal: a SubViewport renders a view-only copy of the office (RoomOfficeView),
## and the Glass sprite displays its ViewportTexture through the glass shader.
## While `mounted_flag` is false the glass wobbles; mounting it calms the image.

@export var mounted_flag: String = "mirror_mounted"

@onready var viewport: SubViewport = $SubViewport
@onready var glass: Sprite2D = $Glass


func _ready() -> void:
	glass.texture = viewport.get_texture()
	GameState.flag_changed.connect(_on_flag_changed)
	GameState.state_reset.connect(refresh)
	refresh()


func _on_flag_changed(_flag: String, _value: bool) -> void:
	refresh()


func is_wobbling() -> bool:
	var mat := glass.material as ShaderMaterial
	return mat != null and float(mat.get_shader_parameter("wobble_enabled")) > 0.5


func refresh() -> void:
	var mat := glass.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("wobble_enabled", 0.0 if GameState.has_flag(mounted_flag) else 1.0)


func get_view_room() -> Node:
	return viewport.get_child(0) if viewport.get_child_count() > 0 else null
