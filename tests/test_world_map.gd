@tool
extends McpTestSuite
## Logic tests for the procedural map (data only, no visuals except the last test).

const SEEDS := [1, 2, 3, 7, 42, 99, 123, 2024, 31337, 777777]

func suite_name() -> String:
	return "world_map"

func _gen(s: int, visuals := false) -> WorldMap:
	var m := WorldMap.new()
	track(m)
	m.generate(s, visuals)
	return m

func test_same_seed_same_map() -> void:
	var a := _gen(42)
	var b := _gen(42)
	assert_eq(a.spawn_point, b.spawn_point)
	assert_eq(a.gate_pos, b.gate_pos)
	assert_eq(a.camps, b.camps)
	assert_eq(a.objective_sites, b.objective_sites)
	assert_true(_gen(43).gate_pos != a.gate_pos or _gen(43).camps != a.camps, "different seed, different map")

func test_key_points_are_reachable_land() -> void:
	for s in SEEDS:
		var m := _gen(s)
		assert_true(m.is_reachable(m.spawn_point), "spawn %d" % s)
		assert_true(m.is_reachable(m.gate_pos), "gate %d" % s)
		assert_gt(m.spawn_point.distance_to(m.gate_pos), 2000.0, "gate far from spawn %d" % s)
		for c in m.camps:
			assert_true(m.is_reachable(c.pos), "camp %d" % s)
		for p in m.objective_sites:
			assert_true(m.is_reachable(p), "site %d" % s)
		for i in 10:
			assert_true(m.is_reachable(m.random_open_point()), "open point %d" % s)

func test_camps_cover_all_tiers_and_keep_spacing() -> void:
	for s in SEEDS:
		var m := _gen(s)
		var tiers := {}
		for c in m.camps:
			tiers[c.tier] = true
			assert_gt(c.pos.distance_to(m.spawn_point), 600.0, "camp not on spawn %d" % s)
		assert_eq(tiers.size(), 3, "all three tiers present, seed %d" % s)
		assert_true(m.camps.size() >= 8, "enough camps, seed %d" % s)
		for i in m.camps.size():
			for j in range(i + 1, m.camps.size()):
				assert_true(m.camps[i].pos.distance_to(m.camps[j].pos) >= 600.0, "camp spacing %d" % s)
		assert_true(m.objective_sites.size() >= 4, "enough sites, seed %d" % s)

func test_builds_visuals_and_collision() -> void:
	var m := _gen(42, true)
	assert_gt(m.get_child_count(), 10, "ground plus decor nodes")

func test_trees_are_only_the_border() -> void:
	for s in [1, 42, 99]:
		var m := _gen(s)
		var trees := 0
		for d in m._decor:
			if d.kind == "tree":
				trees += 1
				assert_false(m._is_core(m.cell_of(d.pos)) and m._open2(m.cell_of(d.pos)), "tree inside open ground, seed %d" % s)
		assert_gt(trees, 300, "a real tree line, seed %d" % s)

func test_layout_is_chambers_and_alcoves() -> void:
	for s in SEEDS:
		var m := _gen(s)
		var kinds := {}
		for c in m.chambers:
			kinds[c.kind] = kinds.get(c.kind, 0) + 1
		assert_eq(kinds.get("spawn"), 1)
		assert_eq(kinds.get("gate"), 1)
		assert_eq(kinds.get("camp"), 10, "seed %d" % s)
		assert_true(kinds.get("alcove", 0) >= 4, "alcoves, seed %d" % s)
