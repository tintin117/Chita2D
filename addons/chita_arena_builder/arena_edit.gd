@tool
extends RefCounted
## Placement and validation shared by the dock and headless checks.

const ARENA_SCRIPT := preload("res://scripts/world/iso_level.gd")
const PROP := preload("res://scenes/levels/iso_prop.tscn")
const TILE_SET := preload("res://scenes/levels/iso_tileset.tres")
const ATLAS_SOURCE := 0
const COVER_RADIUS := ARENA_SCRIPT.PROP_R
const MIN_SPAWN_GAP := 400.0

static func is_arena(root: Node) -> bool:
	return is_instance_valid(root) and root is ARENA_SCRIPT

static func atlas_cell(id: int) -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i(id % 11, id / 11)

static func cell_at(layer: TileMapLayer, viewport_point: Vector2, canvas: Transform2D) -> Vector2i:
	return layer.local_to_map((canvas * layer.global_transform).affine_inverse() * viewport_point)

static func snapped_point(layer: TileMapLayer, world_point: Vector2) -> Vector2:
	return layer.to_global(layer.map_to_local(layer.local_to_map(layer.to_local(world_point))))

static func on_ground(ground: TileMapLayer, world_point: Vector2) -> bool:
	return ground.get_cell_source_id(ground.local_to_map(ground.to_local(world_point))) != -1

static func make_prop(id: int, solid: bool, at: Vector2) -> Sprite2D:
	var prop := PROP.instantiate() as Sprite2D
	prop.set("tile", id)
	prop.set("solid_radius", COVER_RADIUS if solid else 0.0)
	prop.position = at
	prop.name = "Cover" if solid else "Decor"
	return prop

static func cover_footprints(arena: Node2D) -> Array[Vector3]:
	var footprints: Array[Vector3] = []
	var layer: TileMapLayer = arena.get_node("Props")
	for cell in layer.get_used_cells():
		var at := layer.to_global(layer.map_to_local(cell))
		footprints.append(Vector3(at.x, at.y, COVER_RADIUS))
	for child in arena.get_node("FreeProps").get_children():
		if child is Node2D and child.get("solid_radius") != null:
			var radius: float = child.get("solid_radius")
			if radius > 0.0:
				footprints.append(Vector3(child.global_position.x, child.global_position.y, radius))
	return footprints

## Each exposed diamond edge borders water according to the same Ground layer used in the match.
static func shore_segments(ground: TileMapLayer) -> PackedVector2Array:
	var segments := PackedVector2Array()
	var half := Vector2(ground.tile_set.tile_size) * 0.5
	for cell in ground.get_used_cells():
		var at := ground.map_to_local(cell)
		for neighbor in ground.get_surrounding_cells(cell):
			if ground.get_cell_source_id(neighbor) != -1:
				continue
			var side := (ground.map_to_local(neighbor) - at).sign()
			segments.append(ground.to_global(at + Vector2(side.x * half.x, 0)))
			segments.append(ground.to_global(at + Vector2(0, side.y * half.y)))
	return segments

## Build the match's own navigation on a disposable scene copy using the current unsaved edits.
static func validate_arena(arena: Node2D) -> Dictionary:
	var level := arena.duplicate() as WorldMap
	var errors: Array[String] = []
	var routes: Array[PackedVector2Array] = []
	level.generate_arena(false)
	var center_wet := level.is_water(level.spawn_point)
	if center_wet:
		errors.append("Crown center is in water.")
	if level.spawn_points.size() != 8:
		errors.append("Expected eight spawn markers. Found %d." % level.spawn_points.size())
	for i in level.spawn_points.size():
		var point := level.spawn_points[i]
		var name := str(level.get_node("Spawns").get_child(i).name)
		var route := PackedVector2Array()
		if level.is_water(point):
			errors.append("%s spawn is in water." % name)
		elif not center_wet:
			route = level.nav_path(point, level.spawn_point)
			if route.size() < 2 or route[0].distance_to(point) > 64.0 or route[-1].distance_to(level.spawn_point) > 64.0:
				errors.append("%s spawn has no walkable route to the crown." % name)
				route.clear()
		routes.append(route)
		for j in range(i + 1, level.spawn_points.size()):
			if point.distance_to(level.spawn_points[j]) <= MIN_SPAWN_GAP:
				var other := str(level.get_node("Spawns").get_child(j).name)
				errors.append("%s and %s spawns must be more than 400 px apart." % [name, other])
	level.free()
	return {"errors": errors, "routes": routes}
