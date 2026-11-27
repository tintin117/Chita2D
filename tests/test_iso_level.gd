@tool
extends McpTestSuite
## Playability of every hand-edited arena. Run after editing a level: it fails if an edit cut off a spawn.

const PvpMatch := preload("res://scenes/pvp_match.gd")

func suite_name() -> String:
	return "iso_level"

func _level(index: int, visuals := false) -> WorldMap:
	var m := Arenas.create(index)
	track(m)
	m.generate_arena(visuals)
	return m

func _iso_levels() -> Array:
	return range(Arenas.LIST.size()).filter(func(i: int) -> bool: return Arenas.LIST[i].scene != "")

func test_spawns_are_dry_apart_and_walk_to_the_centre() -> void:
	assert_gt(_iso_levels().size(), 0)
	for level: int in _iso_levels():
		var m := _level(level)
		var id: String = Arenas.LIST[level].name
		assert_eq(m.spawn_points.size(), 8, id)
		assert_false(m.is_water(m.spawn_point), id + ": Center stands on ground")
		for i in m.spawn_points.size():
			var sp := m.spawn_points[i]
			assert_false(m.is_water(sp), "%s: spawn %d on ground" % [id, i])
			assert_true(m.is_reachable(sp), "%s: spawn %d connected" % [id, i])
			var path := m.nav_path(sp, m.spawn_point)
			assert_gt(path.size(), 1, "%s: bots can walk from spawn %d to the centre" % [id, i])
			if path.size() > 1:
				assert_true(path[path.size() - 1].distance_to(m.spawn_point) < 64.0, "%s: spawn %d's route arrives" % [id, i])
			for j in range(i + 1, m.spawn_points.size()):
				assert_gt(sp.distance_to(m.spawn_points[j]), 400.0, "%s: spawns %d,%d apart" % [id, i, j])
			for c in m.cover:
				assert_gt(sp.distance_to(c), 80.0, "%s: no prop on spawn %d" % [id, i])

func test_water_props_and_drop_spots() -> void:
	for level: int in _iso_levels():
		var m := _level(level, true)
		var id: String = Arenas.LIST[level].name
		assert_true(m.is_water(Vector2(-500, -500)), id + ": no painted ground is water")
		assert_gt(m.cover.size(), 0, id + ": props are solid")
		assert_gt(m.water_spots.size(), 0, id + ": the radar has water to draw")
		for i in 50:
			assert_false(m.is_water(m.random_open_point()), id + ": drops land on ground")

## A small or crowded map must still have room for drops away from spawns, not just the centre fallback.
func test_drops_have_room_to_spread() -> void:
	for level: int in _iso_levels():
		var m := _level(level)
		var seen := {}
		var none: Array[Vector2] = []
		for i in 30:
			seen[PvpMatch.pick_pickup_pos(m, none)] = true
		assert_gt(seen.size(), 8, "%s: only %d different drop spots in 30 tries" % [Arenas.LIST[level].name, seen.size()])

func test_every_arena_loads() -> void:
	for i in Arenas.LIST.size():
		assert_true(_level(i).spawn_points.size() == 8, Arenas.LIST[i].name)
