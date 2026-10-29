class_name PaperSway
extends Node
## J (Директор 29.10, стр. 161: «мамины письма и все бумаги в руках — лёгкое покачивание бумаги»): a sheet held in the
## hands breathes a little — a slow turn of a fraction of a degree and a pixel or two up and down, never still and
## never enough to blur the writing. Added as a child of the Control it moves (a close-up's sheet, an examined photo);
## the sheet's own rotation and place stay the middle of the sway. One seed per sheet: neighbours don't move in step.

var amp_deg: float = 0.32
var amp_px: float = 1.6
var _target: Control = null
var _rot0: float = 0.0
var _pos0: Vector2 = Vector2.ZERO
var _t: float = 0.0


func _ready() -> void:
	_target = get_parent() as Control
	if _target == null:
		set_process(false)
		return
	_rot0 = _target.rotation
	_pos0 = _target.position
	_t = float(abs(hash(String(_target.name) + str(_target.size))) % 1000) * 0.01


func _process(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		return
	_t += delta
	var r := (sin(_t * 0.83) + 0.4 * sin(_t * 1.71 + 1.3)) / 1.4
	_target.rotation = _rot0 + deg_to_rad(amp_deg * r)
	_target.position = _pos0 + Vector2(sin(_t * 0.61) * amp_px * 0.4, sin(_t * 0.97 + 0.6) * amp_px)


## The sheet back where it lies (tests, a close-up that is being put away).
func rest() -> void:
	if _target != null and is_instance_valid(_target):
		_target.rotation = _rot0
		_target.position = _pos0
