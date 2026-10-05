class_name Room extends Node2D
## Grass island on water, built from the Tiny Swords tileset (3x3 nine-patch). Origin = top-left of island.

const TILE := 64
const INSET := 44.0  ## wall inset from island edge (px)
const TILESET := "res://assets/tiny_swords/terrain/Tilemap_color1.png"
const WATER := "res://assets/tiny_swords/terrain/Water Background color.png"

@export var size_tiles := Vector2i(22, 13)

func pixel_size() -> Vector2:
	return Vector2(size_tiles * TILE)

func center() -> Vector2:
	return pixel_size() / 2.0

func _ready() -> void:
	z_index = -10
	var px := pixel_size()
	var water := Sprite2D.new()
	water.texture = load(WATER)
	water.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	water.centered = false
	water.region_enabled = true
	water.region_rect = Rect2(0, 0, px.x + 2400, px.y + 1600)
	water.position = Vector2(-1200, -800)
	add_child(water)

	var src := TileSetAtlasSource.new()
	src.texture = load(TILESET)
	src.texture_region_size = Vector2i(TILE, TILE)
	for x in 3:
		for y in 3:
			src.create_tile(Vector2i(x, y))
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	ts.add_source(src)
	var layer := TileMapLayer.new()
	layer.tile_set = ts
	for x in size_tiles.x:
		for y in size_tiles.y:
			var cx := 0 if x == 0 else (2 if x == size_tiles.x - 1 else 1)
			var cy := 0 if y == 0 else (2 if y == size_tiles.y - 1 else 1)
			layer.set_cell(Vector2i(x, y), 0, Vector2i(cx, cy))
	add_child(layer)

	var walls := StaticBody2D.new()
	walls.collision_layer = 1
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
