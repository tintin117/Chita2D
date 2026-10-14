@tool  # ponytail: only so the in-editor test runner can instantiate it; it does nothing in the editor
class_name MapDiscovery extends Node
## Tracks which map cells the players have been near. Only the minimap reads it (no in-world fog):
## explored land is lit there, and camps / objective sites / the gate show up once explored.

signal changed  ## new cells were explored

const SIGHT := 576.0     ## px, 9 cells
const TICK := 0.1

var explored := PackedByteArray()
var _seen := PackedByteArray()  ## within sight as of the last update (minimap enemy dots)
var _t := 0.0

func setup() -> void:
	explored.resize(WorldMap.SIZE.x * WorldMap.SIZE.y)
	explored.fill(0)
	_seen = explored.duplicate()

func is_explored(pos: Vector2) -> bool:
	var i := _index(pos)
	return i >= 0 and explored[i] == 1

func is_visible_now(pos: Vector2) -> bool:
	var i := _index(pos)
	return i >= 0 and _seen[i] == 1

## Explore everything within SIGHT of pos. Returns true if that revealed new cells.
func reveal(pos: Vector2) -> bool:
	var grew := _mark(pos)
	if grew:
		changed.emit()
	return grew

func _process(delta: float) -> void:
	_t += delta
	if _t < TICK or explored.is_empty():
		return
	_t = 0.0
	_seen.fill(0)
	var grew := false
	for p: Player in get_tree().get_nodes_in_group("players"):
		if not p.down:
			grew = _mark(p.global_position) or grew
	if grew:
		changed.emit()

func _index(pos: Vector2) -> int:
	var c := Vector2i((pos / WorldMap.TILE).floor())
	if c.x < 0 or c.y < 0 or c.x >= WorldMap.SIZE.x or c.y >= WorldMap.SIZE.y:
		return -1
	return c.y * WorldMap.SIZE.x + c.x

func _mark(pos: Vector2) -> bool:
	var grew := false
	var c := Vector2i((pos / WorldMap.TILE).floor())
	var r := ceili(SIGHT / WorldMap.TILE)
	for y in range(maxi(c.y - r, 0), mini(c.y + r + 1, WorldMap.SIZE.y)):
		for x in range(maxi(c.x - r, 0), mini(c.x + r + 1, WorldMap.SIZE.x)):
			if ((Vector2(x, y) + Vector2(0.5, 0.5)) * WorldMap.TILE).distance_to(pos) > SIGHT:
				continue
			var i := y * WorldMap.SIZE.x + x
			_seen[i] = 1
			if explored[i] == 0:
				explored[i] = 1
				grew = true
	return grew
