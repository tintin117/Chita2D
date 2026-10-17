@tool
extends McpTestSuite
## Logic tests for the PvP arena and respawn picking (no networking).

const PvpMatch := preload("res://scenes/pvp_match.gd")

func suite_name() -> String:
	return "pvp"

func _arena() -> WorldMap:
	var m := WorldMap.new()
	track(m)
	m.generate_arena(false)
	return m

func test_arena_is_identical_every_time() -> void:
	var a := _arena()
	var b := _arena()
	assert_eq(a.spawn_points, b.spawn_points)
	assert_eq(a.cover, b.cover)
	assert_eq(a._decor, b._decor, "every peer must grow the same trees")

func test_eight_spawns_are_reachable_and_apart() -> void:
	var m := _arena()
	assert_eq(m.spawn_points.size(), 8)
	for i in 8:
		assert_true(m.is_reachable(m.spawn_points[i]), "spawn %d on open ground" % i)
		for j in range(i + 1, 8):
			assert_gt(m.spawn_points[i].distance_to(m.spawn_points[j]), 500.0, "spawns %d,%d apart" % [i, j])
		for c in m.cover:
			assert_gt(m.spawn_points[i].distance_to(c), WorldMap.COVER_R + 120.0, "cover not on spawn %d" % i)

func test_cover_is_on_open_ground() -> void:
	var m := _arena()
	assert_gt(m.cover.size(), 8)
	for c in m.cover:
		assert_true(m.is_reachable(c))

func test_respawn_picks_the_spawn_farthest_from_opponents() -> void:
	var points: Array[Vector2] = [Vector2(0, 0), Vector2(1000, 0), Vector2(2000, 0)]
	var others: Array[Vector2] = [Vector2(100, 0), Vector2(1100, 0)]
	assert_eq(PvpMatch.farthest_spawn(points, others), Vector2(2000, 0))
	others = [Vector2(2000, 0)]
	assert_eq(PvpMatch.farthest_spawn(points, others), Vector2(0, 0))

func test_gym_is_a_small_open_room() -> void:
	var m := WorldMap.new()
	track(m)
	m.generate_gym(false)
	assert_true(m.is_reachable(m.spawn_point), "centre is open ground")
	assert_true(m.is_reachable(m.spawn_point + Vector2(-260, 0)), "hero spawn beside the dummy")
	assert_true(m.cover.is_empty() and m.spawn_points.is_empty())
	assert_false(m.is_reachable(m.spawn_point + Vector2(2000, 0)), "room is small")

func test_dummy_is_hittable_and_never_down() -> void:
	var d := Dummy.new()
	track(d)
	assert_false(d.down)
	assert_true(d.has_method("take_damage"))

func test_pickups_spawn_central_and_clear() -> void:
	var m := _arena()
	var taken: Array[Vector2] = []
	for i in 50:
		var p := PvpMatch.pick_pickup_pos(m, taken)
		assert_true(m.is_reachable(p), "pickup on open ground")
		for s in m.spawn_points:
			assert_gt(p.distance_to(s), PvpMatch.PICKUP_SPAWN_CLEAR - 1.0, "pickup away from spawns")
		for c in m.cover:
			assert_gt(p.distance_to(c), PvpMatch.PICKUP_COVER_CLEAR - 1.0, "pickup off the cover")
		taken = [p]

func test_buffs_expire() -> void:
	var p := Player.new()
	track(p)
	assert_false(p.buffed("damage"))
	p.buffs["damage"] = Time.get_ticks_msec() / 1000.0 + 5.0
	assert_true(p.buffed("damage"))
	p.buffs["damage"] = Time.get_ticks_msec() / 1000.0 - 1.0
	assert_false(p.buffed("damage"))
