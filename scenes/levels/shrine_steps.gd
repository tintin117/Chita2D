@tool
extends Node2D
## Stair treads drawn on the same 2:1 plane as the arena's stone tiles.

@export var span := 455.0:
	set(value):
		span = value
		queue_redraw()
@export var run := 132.0:
	set(value):
		run = value
		queue_redraw()
@export_range(2, 10) var steps := 6:
	set(value):
		steps = value
		queue_redraw()
@export var across := false:
	set(value):
		across = value
		queue_redraw()

const TREAD := Color("#969485")
const RISER := Color("#716e63")
const NOSING := Color("#b9b4a1")
const JOINT := Color("#767568")

func _draw() -> void:
	var half := span * 0.5
	var stride := run / steps
	for i in steps:
		var near := i * stride - run * 0.5
		var far := near + stride
		var top := far - stride * 0.23
		_strip(near, top, half, TREAD.lightened((i % 3 - 1) * 0.035) if i % 3 != 0 else TREAD.darkened(0.04))
		_strip(top, far, half, RISER)
		draw_line(_project(top, -half), _project(top, half), NOSING, 1.6)
		var joint := -half + 24.0 + 18.0 * (i % 2)
		while joint < half - 8.0:
			draw_line(_project(near + 1.0, joint), _project(top - 1.0, joint), JOINT, 1.0)
			joint += 44.0

func _strip(near: float, far: float, half: float, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([_project(near, -half), _project(far, -half),
		_project(far, half), _project(near, half)]), color)

func _project(u: float, v: float) -> Vector2:
	if across:
		return Vector2(v - u, (u + v) * 0.5)
	return Vector2(u - v, (u + v) * 0.5)
