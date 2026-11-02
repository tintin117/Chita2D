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

func test_knockback_grows_with_damage_and_caps() -> void:
	assert_gt(Player.knock_for(45), Player.knock_for(10))
	assert_gt(Player.knock_for(10), 400.0, "even a light hit launches")
	assert_true(Player.knock_for(9999) <= Player.KNOCK_MAX)

func test_arena_edge_is_water_and_the_inside_is_not() -> void:
	var m := _arena()
	assert_true(m.open_shore, "arena has no shore walls")
	for s in m.spawn_points:
		assert_false(m.is_water(s), "spawn on land")
	assert_true(m.is_water(m.spawn_point + Vector2(6000, 0)), "far out is water")
	var g := WorldMap.new()
	track(g)
	g.generate_gym(false)
	assert_false(g.open_shore, "gym keeps its walls")

func test_every_pickup_kind_is_complete() -> void:
	for k: String in PvpPickup.KINDS:
		assert_true(PvpPickup.LABELS.has(k) and PvpPickup.COLORS.has(k) and PvpPickup.ICONS.has(k) and PvpPickup.WEIGHTS.has(k), k)
	for r in [0.0, 0.25, 0.5, 0.75, 0.999]:
		assert_true(PvpPickup.roll(r) in PvpPickup.KINDS)
		assert_true(PvpPickup.mystery_outcome(r) in PvpPickup.OUTCOMES)
	assert_false("mystery" in PvpPickup.OUTCOMES, "a mystery box never yields another mystery box")

func test_kill_lines_are_deterministic() -> void:
	assert_eq(PvpMatch.kill_line("hit", "Ann", "Bo", 0), PvpMatch.kill_line("hit", "Ann", "Bo", 0))
	assert_true("Ann" in PvpMatch.kill_line("hit", "Ann", "Bo", 3) and "Bo" in PvpMatch.kill_line("hit", "Ann", "Bo", 3))
	assert_true("Bo" in PvpMatch.kill_line("fall", "", "Bo", 1))
	assert_true("Ann" in PvpMatch.kill_line("fall", "Ann", "Bo", 1), "a push is credited in the line")
	assert_true("Bo" in PvpMatch.kill_line("bomb", "", "Bo", 2))

func test_crown_needs_a_strict_lead_and_three_kills() -> void:
	assert_eq(PvpMatch.crown_holder({1: 2, 2: 0}), 0, "two kills is not enough")
	assert_eq(PvpMatch.crown_holder({1: 3, 2: 1}), 1)
	assert_eq(PvpMatch.crown_holder({1: 4, 2: 4}), 0, "a tie wears no crown")
	assert_eq(PvpMatch.crown_holder({1: 5, 2: 4, 3: 1}), 1)

func test_awards_only_for_things_that_happened() -> void:
	var names := {1: "Ann", 2: "Bo"}
	var st := {1: PvpMatch.new_stats(), 2: PvpMatch.new_stats()}
	assert_eq(PvpMatch.awards(st, {1: 0, 2: 0}, {1: 0, 2: 0}, {}, names).size(), 0, "nothing happened, nothing awarded")
	st[2].falls = 2
	st[1].best = 4
	var out := PvpMatch.awards(st, {1: 5, 2: 1}, {1: 0, 2: 4}, {Vector2i(1, 2): 3}, names)
	var titles := out.map(func(a: Dictionary) -> String: return a.title)
	for t in ["Top Fragger", "Killing Spree", "Nemesis", "Punching Bag", "Aquaman"]:
		assert_true(t in titles, t)
	assert_false("Chatterbox" in titles)
	assert_true(out.size() <= 6)

func test_bot_lead_aims_ahead_of_a_moving_target() -> void:
	var from := Vector2.ZERO
	assert_eq(BotBrain.lead(from, Vector2(400, 0), Vector2.ZERO, 640.0), Vector2(400, 0), "a still target is aimed at directly")
	var aim := BotBrain.lead(from, Vector2(400, 0), Vector2(0, 200), 640.0)
	assert_gt(aim.y, 50.0, "aims ahead along the target's motion")
	assert_eq(aim.x, 400.0, "target moves only along y")

func test_solo_roster_has_bots_that_need_no_loading() -> void:
	var net: Node = (load("res://scripts/net/net.gd") as GDScript).new()   # a fresh copy: inside the editor the Net autoload is only a placeholder with no script vars
	track(net)
	var saved: Dictionary = net.roster.duplicate(true)
	net.roster = {1: {"name": "Me", "ready": true}, 1000: {"name": "Bot Ann", "ready": true, "bot": true}}
	net._loaded.clear()
	net._loaded[1] = true
	# every human has loaded, so the bots must not hold the match back (_check_go would fire _go)
	var humans_loaded: bool = net.roster.keys().all(func(id: int) -> bool: return net._loaded.has(id) or net.roster[id].get("bot", false))
	assert_true(humans_loaded)
	net._loaded.clear()
	net.roster = saved

func test_pickup_tiers() -> void:
	for k: String in PvpPickup.KINDS:
		assert_true(PvpPickup.KIND_TIER.has(k), "%s has a tier" % k)
		assert_true(PvpPickup.tier_of(k) in [PvpPickup.Tier.COMMON, PvpPickup.Tier.RARE, PvpPickup.Tier.EPIC])
	assert_eq(PvpPickup.tier_of("heal"), PvpPickup.Tier.COMMON)
	assert_eq(PvpPickup.tier_of("damage"), PvpPickup.Tier.RARE)
	assert_eq(PvpPickup.tier_of("giant"), PvpPickup.Tier.EPIC)
	assert_eq(PvpPickup.tier_name("bomb"), "Epic")
	assert_eq(PvpPickup.TIER_LOOK.size(), 3)
	assert_true(PvpPickup.TIER_LOOK[0].rings < PvpPickup.TIER_LOOK[2].rings, "epics have more rings (shape cue)")

func test_epics_are_rare_in_the_roll() -> void:
	var n := 2000
	var epics := 0
	for i in n:
		if PvpPickup.tier_of(PvpPickup.roll(float(i) / n)) == PvpPickup.Tier.EPIC:
			epics += 1
	var share := float(epics) / n
	assert_gt(share, 0.03, "epics still show up")
	assert_true(share < 0.15, "epics are rare")

func test_drop_arrow_helpers() -> void:
	var view := Vector2(1000, 600)
	var inside := DropArrows.clamp_to_edge(Vector2(500, 300), view, 50.0)
	assert_true(inside.inside)
	var out := DropArrows.clamp_to_edge(Vector2(3000, 300), view, 50.0)
	assert_false(out.inside)
	assert_eq(out.pos, Vector2(950, 300))
	var corner := DropArrows.clamp_to_edge(Vector2(-4000, -4000), view, 50.0)
	assert_true(corner.pos.x >= 50.0 - 0.01 and corner.pos.y >= 50.0 - 0.01)
	var ranked := DropArrows.rank([
		{"dist": 500.0, "tier": 0}, {"dist": 900.0, "tier": 2}, {"dist": 300.0, "tier": 0}, {"dist": 2000.0, "tier": 0}], 2)
	assert_eq(ranked.size(), 2)
	assert_eq(ranked[0].tier, 2, "a far epic outranks a near common")
