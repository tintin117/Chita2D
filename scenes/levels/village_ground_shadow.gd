@tool
extends Node2D
## Soft contact shadow on the ground plane, sized to each prop's footprint.

@export var footprint := Vector2(32, 16):
	set(value):
		footprint = value
		queue_redraw()
@export var drift := Vector2(2, 5):
	set(value):
		drift = value
		queue_redraw()
@export var squared := false:
	set(value):
		squared = value
		queue_redraw()

const STEPS := 24
const CENTER := Color(0.02, 0.018, 0.016, 0.52)
const SHOULDER := Color(0.02, 0.018, 0.016, 0.34)
const EDGE := Color(0.02, 0.018, 0.016, 0.0)

func _draw() -> void:
	for i in STEPS:
		var a := _rim_point(i)
		var b := _rim_point(i + 1)
		var inner_a := drift * 0.6 + a * 0.72
		var inner_b := drift * 0.6 + b * 0.72
		draw_polygon(PackedVector2Array([Vector2.ZERO, inner_a, inner_b]),
			PackedColorArray([CENTER, SHOULDER, SHOULDER]))
		draw_polygon(PackedVector2Array([inner_a, drift + a, drift + b, inner_b]),
			PackedColorArray([SHOULDER, EDGE, EDGE, SHOULDER]))

func _rim_point(step: int) -> Vector2:
	var unit := Vector2.from_angle(TAU * step / STEPS)
	if squared:
		# Blend a diamond footprint with its ellipse to round the four corners.
		unit = unit.lerp(unit / (absf(unit.x) + absf(unit.y)), 0.72)
	return unit * footprint
