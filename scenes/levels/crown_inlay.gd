@tool
extends Node2D
## Ground-plane masonry at the crown marker. The same 2:1 projection as the floor tiles.

@export var accent := Color("#bca674"):
	set(value):
		accent = value
		queue_redraw()

const GROUND_PROJECTION := Vector2(1.0, 0.5)

func _draw() -> void:
	for radius in [104.0, 143.0]:
		var rim := PackedVector2Array()
		for step in 33:
			rim.append(Vector2.from_angle(TAU * step / 32.0) * radius * GROUND_PROJECTION)
		draw_polyline(rim, Color("#323e3a"), 5.0)
		draw_polyline(rim, accent, 2.0)
	for step in 8:
		var angle := TAU * step / 8.0
		var direction := Vector2.from_angle(angle)
		var side := direction.orthogonal()
		draw_colored_polygon(PackedVector2Array([
			(direction * 104.0) * GROUND_PROJECTION,
			(direction * 123.0 + side * 7.0) * GROUND_PROJECTION,
			(direction * 143.0) * GROUND_PROJECTION,
			(direction * 123.0 - side * 7.0) * GROUND_PROJECTION,
		]), accent)
