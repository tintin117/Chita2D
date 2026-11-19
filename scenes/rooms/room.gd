class_name Room extends Node2D
## Grass island on water, built from the isometric tileset (see WorldMap.iso_ground). Origin = top-left of island.

const TILE := 64
const INSET := 44.0  ## wall inset from island edge (px)

@export var size_tiles := Vector2i(22, 13)

func pixel_size() -> Vector2:
	return Vector2(size_tiles * TILE)

func center() -> Vector2:
	return pixel_size() / 2.0

func _ready() -> void:
	z_index = -10
	var px := pixel_size()
	WorldMap.iso_ground(self, Rect2(-1200, -800, px.x + 2400, px.y + 1600), Rect2(Vector2.ZERO, px).has_point)

	var walls := StaticBody2D.new()
	walls.collision_layer = 1 | Player.WALL_MASK   # a dash passes rocks but never the room walls
	walls.collision_mask = 0
	var inner := Rect2(Vector2.ZERO, px).grow(-INSET)
	var t := 200.0
	for r in [
		Rect2(inner.position.x - t, inner.position.y - t, inner.size.x + 2 * t, t),
		Rect2(inner.position.x - t, inner.end.y, inner.size.x + 2 * t, t),
		Rect2(inner.position.x - t, inner.position.y, t, inner.size.y),
		Rect2(inner.end.x, inner.position.y, t, inner.size.y),
	]:
		var cs := CollisionShape2D.new()
		var rs := RectangleShape2D.new()
		rs.size = r.size
		cs.shape = rs
		cs.position = r.get_center()
		walls.add_child(cs)
	add_child(walls)
