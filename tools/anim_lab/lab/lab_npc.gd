extends Node2D
## Заглушка игрового NpcActor. NpcLive3D берёт у него только `sprite` (родитель картинки 3D-фигуры, его self_modulate —
## тон комнаты) и `sheet.texture_scale` (пикселей экрана на пиксель листа при масштабе узла 1), плюс позицию и масштаб узла.

class LabSheet extends RefCounted:
	var texture_scale := 2.25   # как в пробах основной игры (tests/probe_hands_closeup.gd)


var sprite: Sprite2D = null
var sheet = LabSheet.new()


func _init() -> void:
	sprite = Sprite2D.new()
	sprite.name = "Sprite"
	add_child(sprite)
