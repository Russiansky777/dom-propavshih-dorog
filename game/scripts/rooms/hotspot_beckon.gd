class_name HotspotBeckon
extends Node2D
## A soft pulsing glow on a hotspot that the story wants noticed (rooms data `beckon` {if, unless}: Q06 —
## the shed of Ilya's workshop, invisible on the art, glows once the hook is said and until the first
## click, Director 25.10 «вход невидим … подсветка»). Warm ring around the rect centre, breathing
## between PULSE_MIN and PULSE_MAX alpha over PERIOD seconds; click-through, drawn above the room.

const PERIOD := 2.4
const PULSE_MIN := 0.18
const PULSE_MAX := 0.55
const COLOR := Color(1.0, 0.86, 0.55)

var radius: float = 60.0
var _t: float = 0.0


func _ready() -> void:
	z_index = 4000
	z_as_relative = false


func _process(delta: float) -> void:
	_t = fmod(_t + delta, PERIOD)
	queue_redraw()


func pulse_alpha() -> float:
	return lerpf(PULSE_MIN, PULSE_MAX, 0.5 - 0.5 * cos(TAU * _t / PERIOD))


func _draw() -> void:
	var a := pulse_alpha()
	for i in 6:
		var k := float(i) / 5.0
		draw_arc(Vector2.ZERO, radius * (0.75 + 0.35 * k), 0.0, TAU, 64,
			Color(COLOR.r, COLOR.g, COLOR.b, a * (1.0 - k) * 0.6), 6.0 + 4.0 * k, true)
