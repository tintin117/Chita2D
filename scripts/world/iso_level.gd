@tool  # ponytail: only so the in-editor test runner can run it, like WorldMap; it does nothing in the editor
extends WorldMap
## A hand-painted arena (scenes/levels/iso_arena.tscn). The scene is the level: gameplay is read from what is placed.
##   Ground     a tile = standing ground; no tile = deadly water
##   Props      a tile = solid (blocks walking and shots, a dash goes through)
##   Water, Decor   looks only
##   FreeProps  iso_prop.tscn instances, placed off the grid; solid if solid_radius > 0
##   Spawns     markers; the first half is team 0
##   Center     the crown and the rare drops
## See docs/iso_level_editing.md.

const PROP_R := 20.0   ## collision radius of a Props tile (world px)

@export var crown_hold_radius := 200.0   ## bots holding the crown stay this close to Center
@export var walled_arena := false       ## a separately authored wall encloses the painted playing surface

var _ground: TileMapLayer
var _radii: Array[float] = []   ## collision radius of each `cover` entry

func is_water(pos: Vector2) -> bool:
	return _ground.get_cell_source_id(_ground.local_to_map(_ground.transform.affine_inverse() * pos)) == -1

func hold_radius() -> float:
	return crown_hold_radius

func generate_arena(build_visuals := true) -> void:
	_ground = $Ground
	_begin_fixed(ARENA_HALF)   # resets the base map's lists; its plateau is replaced by the painted ground below
	open_shore = not walled_arena
	cover_r = PROP_R
	spawn_point = $Center.position
	gate_pos = spawn_point
	for m: Node2D in $Spawns.get_children():
		spawn_points.append($Spawns.transform * m.position)

	_radii.clear()
	var props: TileMapLayer = $Props
	for c in props.get_used_cells():
		_add_cover(props.transform * props.map_to_local(c), PROP_R)
	for p: Node2D in $FreeProps.get_children():
		var r: float = p.get("solid_radius") if p.get("solid_radius") != null else 0.0
		if r > 0.0:
			_add_cover($FreeProps.transform * p.position, r)

	water_spots.clear()
	var radar_half := ARENA_HALF * TILE - Vector2.ONE * TILE / 2.0
	for y in SIZE.y:
		for x in SIZE.x:
			var at := center_of(Vector2i(x, y))
			var wet := is_water(at)
			_land[y * SIZE.x + x] = 0 if wet else 1
			var off := (at - spawn_point).abs()
			if wet and off.x <= radar_half.x and off.y <= radar_half.y:
				water_spots.append(at)

	_compute_core()
	var inner := _core.duplicate()   # land all round: where drops may fall
	_core = _land.duplicate()        # every ground cell is walkable (narrow bridges must connect)
	_bfs(cell_of(spawn_point))
	_free.clear()
	for y in SIZE.y:
		for x in SIZE.x:
			var i := y * SIZE.x + x
			if inner[i] == 1 and _dist[i] >= 0 and _clear_of_cover(center_of(Vector2i(x, y)), 24.0):
				_free.append(Vector2i(x, y))
	if _free.is_empty():
		_free.append(cell_of(spawn_point))
	for p in spawn_points + ([spawn_point] as Array[Vector2]):
		if is_water(p) or not is_reachable(p):
			push_warning("iso level: the marker at %s is not on ground connected to Center" % p)

	_build_nav()
	if build_visuals:
		var body := StaticBody2D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		for i in cover.size():
			var cs := CollisionShape2D.new()
			var circle := CircleShape2D.new()
			circle.radius = _radii[i]
			cs.shape = circle
			cs.position = cover[i]
			body.add_child(cs)
		add_child(body)
		_owned.append(body)

func _add_cover(at: Vector2, radius: float) -> void:
	cover.append(at)
	_radii.append(radius)

func _clear_of_cover(at: Vector2, margin: float) -> bool:
	for i in cover.size():
		if at.distance_to(cover[i]) < _radii[i] + margin:
			return false
	return true

## The base map's bot grid, over the painted ground instead of the Colosseum's shapes.
func _build_nav() -> void:
	var area := Rect2(spawn_point, Vector2.ZERO)
	for c in _ground.get_used_cells():
		area = area.expand(_ground.transform * _ground.map_to_local(c))
	_nav_origin = area.position
	var cells := Vector2i((area.size / NAV_CELL).ceil())
	nav = AStarGrid2D.new()
	nav.region = Rect2i(Vector2i.ZERO, cells)
	nav.cell_size = Vector2(NAV_CELL, NAV_CELL)
	nav.offset = _nav_origin + Vector2(NAV_CELL, NAV_CELL) / 2.0
	nav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	nav.update()
	for y in cells.y:
		for x in cells.x:
			var at := nav_point(Vector2i(x, y))
			var solid := not _clear_of_cover(at, NAV_MARGIN)
			for o: Vector2 in [Vector2.ZERO, Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
				solid = solid or is_water(at + o * NAV_MARGIN)
			nav.set_point_solid(Vector2i(x, y), solid)
