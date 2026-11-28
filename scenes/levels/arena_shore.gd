@tool
extends Node2D
## Exposed faces below the 2:1 ground plane. Ground remains the source of the walkable edge.

@export var stone := Color("#354641"):
	set(value):
		stone = value
		queue_redraw()

@onready var _ground: TileMapLayer = $"../Ground"

func _ready() -> void:
	_ground.changed.connect(queue_redraw)

func _draw() -> void:
	if not is_instance_valid(_ground) or not _ground.tile_set:
		return
	var half := Vector2(_ground.tile_set.tile_size) * 0.5
	var to_shore := global_transform.affine_inverse() * _ground.global_transform
	for cell in _ground.get_used_cells():
		var at := _ground.map_to_local(cell)
		for neighbor in _ground.get_surrounding_cells(cell):
			var side := (_ground.map_to_local(neighbor) - at).sign()
			if side.y <= 0.0 or _ground.get_cell_source_id(neighbor) != -1:
				continue
			var a := to_shore * (at + Vector2(side.x * half.x, 0.0))
			var b := to_shore * (at + Vector2(0.0, half.y))
			var depth := Vector2(0.0, 14.0)
			var shade := stone.darkened(0.22) if side.x > 0.0 else stone
			draw_colored_polygon(PackedVector2Array([a, b, b + depth, a + depth]), shade)
			draw_line(a + Vector2(0.0, 2.0), b + Vector2(0.0, 2.0), shade.lightened(0.22), 2.0)
			draw_line(a + depth, b + depth, shade.darkened(0.4), 2.0)
