@tool
extends Node2D
## Low timber cover, aligned to the arena's ground-plane axes.

@export var solid_radius := 46.0
@export var crossed := false:
	set(value):
		crossed = value
		queue_redraw()

const TIMBER := Color("#80543b")
const EDGE := Color("#b08053")
const IRON := Color("#382a22")
const SHADOW := Color(0.19, 0.11, 0.07, 0.42)

func _draw() -> void:
	var axis := Vector2(1.0, -0.5 if crossed else 0.5)
	var cast := Vector2(19, 12)
	var left := axis * -47.0
	var right := axis * 47.0
	draw_colored_polygon(PackedVector2Array([
		left + cast * 0.37, right + cast * 0.37,
		right + cast * 0.81, left + cast * 0.81,
	]), SHADOW)
	for offset: float in [-43.0, 0.0, 43.0]:
		var foot := axis * offset
		draw_line(foot, foot + cast, SHADOW, 5.0)
	for offset: float in [-43.0, 0.0, 43.0]:
		var foot := axis * offset
		draw_line(foot, foot - Vector2(0.0, 35.0), IRON, 7.0)
		draw_line(foot - Vector2(2, 0), foot - Vector2(2, 35), EDGE, 2.0)
	for level: float in [12.0, 24.0]:
		var inset := Vector2(0, level)
		var a := axis * -47.0 - inset
		var b := axis * 47.0 - inset
		draw_line(a, b, IRON, 11.0)
		draw_line(a - Vector2(0, 2), b - Vector2(0, 2), TIMBER, 8.0)
		draw_line(a - Vector2(0, 5), b - Vector2(0, 5), EDGE, 2.0)
		for offset: float in [-43.0, 0.0, 43.0]:
			draw_rect(Rect2(axis * offset - inset - Vector2(1, 4), Vector2(3, 4)), IRON)
