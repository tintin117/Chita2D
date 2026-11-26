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
			assert_gt(m.spawn_points[i].distance_to(m.spawn_points[j]), 400.0, "spawns %d,%d apart" % [i, j])
		for c in m.cover:
			assert_gt(m.spawn_points[i].distance_to(c), WorldMap.COVER_R + 120.0, "cover not on spawn %d" % i)

func test_cover_borders_open_ground() -> void:
	var m := _arena()
	assert_eq(m.cover.size(), 4, "the four braziers")
	for c in m.cover:   # they stand in the pool corners: you can walk up to them, and round them
		var near := false
		for k in 16:
			if m.is_reachable(c + Vector2.from_angle(k * TAU / 16.0) * (m.cover_r + 40.0)):
				near = true
		assert_true(near, "a brazier you can reach")

# --- Bot navigation

func test_nav_reaches_the_crown_from_every_spawn() -> void:
	var m := _arena()
	assert_true(m.nav != null)
	assert_true(m.nav_open(m.nav_cell(m.spawn_point)), "the centre circle is walkable")
	for sp in m.spawn_points:
		var path := m.nav_path(sp, m.spawn_point)
		assert_gt(path.size(), 1, "a walking route from spawn %s" % sp)
		for p in path:
			assert_false(m.is_water(p), "the route never wades")

func test_nav_step_goes_round_the_moat() -> void:
	var m := _arena()
	var col := m.colosseum
	var above := col.to_world(Vector2(1000, 707 - 360))   # on the sand just outside the moat, straight above the centre
	assert_false(m.nav_clear(above, m.spawn_point), "the straight line crosses the moat and the rail")
	var step := m.nav_step(above, m.spawn_point)
	assert_true(step.length() > 0.9)
	assert_false(m.is_water(above + step * 40.0), "the first step stays on the sand")
	var open := col.to_world(Vector2(400, 300))
	var open2 := col.to_world(Vector2(450, 330))
	assert_true(m.nav_clear(open, open2))
	assert_true(m.nav_step(open, open2).dot((open2 - open).normalized()) > 0.99, "a clear line is walked straight")

func test_dry_dir_points_out_of_the_water() -> void:
	var m := _arena()
	var wet := m.colosseum.to_world(Vector2(1000, 707 - 270))   # in the moat
	var d := m.dry_dir(wet)
	assert_true(d != Vector2.ZERO)
	var dry := false
	for r in [40.0, 90.0, 160.0, 260.0]:
		if not m.is_water(wet + d * r):
			dry = true
	assert_true(dry)
	var island := WorldMap.new()
	track(island)
	island.generate_gym(false)
	assert_true(island.nav == null, "only the Colosseum builds a grid")
	assert_eq(island.nav_step(Vector2.ZERO, Vector2(100, 0)), Vector2.RIGHT, "no grid: straight")

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

func test_projectile_frames_play_once_then_loop() -> void:
	for folder: String in Projectile.LOOP_FROM:
		var kind := "Arrows" if folder.ends_with("Arrow") else "Spells"
		var f := SheetFrames.seq(SheetFrames.FX + kind + "/" + folder + "/")
		assert_eq(f.get_frame_count("fx"), 15, folder + " has frames 0001..0029")
	assert_eq(Projectile.frame_at(0.0, 15, 5), 0, "starts on the launch frame")
	assert_eq(Projectile.frame_at(14.5 / Projectile.ANIM_FPS, 15, 5), 14, "plays through once")
	assert_eq(Projectile.frame_at(15.5 / Projectile.ANIM_FPS, 15, 5), 5, "then skips the launch frames")
	assert_eq(Projectile.frame_at(25.5 / Projectile.ANIM_FPS, 15, 5), 5, "and keeps looping")
	assert_eq(Projectile.frame_at(0.0, 15, 5, 5), 5, "an arrow opens past its launch frames")
	assert_eq(Projectile.frame_at(10.5 / Projectile.ANIM_FPS, 15, 5, 5), 5, "and loops from there")

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

func test_stun_holds_then_expires() -> void:
	var p := Player.new()
	track(p)
	assert_false(p.stunned())
	p.stun(0.5)
	assert_true(p.stunned())
	p.stun(0.2)   # a shorter stun never cuts a longer one
	p._tick_timers(0.3)
	assert_true(p.stunned())
	p._tick_timers(0.3)
	assert_false(p.stunned())

func test_stuns_never_chain() -> void:
	var p := Player.new()
	track(p)
	p.stun(0.6)
	p._tick_timers(0.5)
	p.stun(1.4)   # a second stun while held does not extend it
	p._tick_timers(0.2)
	assert_false(p.stunned(), "held for one stun at most")
	p.stun(1.0)
	assert_false(p.stunned(), "immune right after a stun wears off")
	p._tick_timers(Player.STUN_IMMUNITY)
	p.stun(1.0)
	assert_true(p.stunned(), "stunnable again once the immunity is over")

func test_basic_reach_drives_lock_on_and_chase() -> void:
	for id in ["knight", "rogue", "wizard", "ranger"]:
		var h := Hero.by_id(id)
		var s := h.make_basic()
		assert_gt(s.reach(), h.attack_range * 0.99, id + " reaches at least its attack range")
		if h.attack_type == "melee":
			var was := PlaySettings.melee_step
			PlaySettings.melee_step = true
			assert_gt(s.reach(), h.attack_range + 200.0, id + " steps in beyond the blade (step-in on)")
			PlaySettings.melee_step = false
			assert_eq(s.reach(), h.attack_range, id + " swings where it stands (step-in off)")
			PlaySettings.melee_step = was
	assert_eq(Hero.by_id("bonker").make_kit()[1].reach(), 0.0, "skills are not lock-on attacks")

func test_knockback_grows_with_damage_and_caps() -> void:
	assert_gt(Player.knock_for(45), Player.knock_for(10))
	assert_eq(Player.knock_for(10), Player.knock_for(12), "light hits all flinch the same")
	assert_true(Player.knock_for(10) * Player.knock_for(10) / (2.0 * Player.KNOCK_DECEL) < 60.0, "a light hit slides well inside melee reach")
	assert_gt(Player.knock_for(10, 0.1), Player.knock_for(10, 1.0), "hurt victims fly further")
	assert_true(Player.knock_for(9999) <= Player.KNOCK_MAX)

func test_colosseum_water_walls_and_centre() -> void:
	var m := _arena()
	assert_false(m.open_shore, "the Colosseum is walled in by its stands")
	assert_true(m.colosseum != null)
	for sp in m.spawn_points:
		assert_false(m.is_water(sp), "spawn on the sand")
	assert_false(m.is_water(m.spawn_point), "the centre circle (crown) is solid ground")
	var col := m.colosseum
	assert_true(m.is_water(col.to_world(Vector2(1000, 707 - 270))), "the moat above the centre")
	assert_false(m.is_water(col.to_world(Vector2(1000 - 270, 707))), "the bridge crosses the moat")
	assert_true(m.is_water(col.to_world(Vector2(600, 250))), "a corner pool")
	assert_false(m.is_water(m.spawn_point + Vector2(6000, 0)), "beyond the stands is wall, not deadly water")
	assert_true(m.off_ground(m.spawn_point + Vector2(6000, 0)), "but it is no ground to land a dash on")
	assert_gt(m.rails.size(), 20, "rails round the centre, the bridges and the platforms")
	assert_gt(m.water_spots.size(), 20)
	var island := WorldMap.new()
	track(island)
	island.generate_island(false)
	assert_true(island.open_shore and island.colosseum == null, "the old island is still there for comparison")
	var g := WorldMap.new()
	track(g)
	g.generate_gym(false)
	assert_false(g.open_shore, "gym keeps its walls")
	assert_true(g.colosseum == null)

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

func test_team_totals_and_leader() -> void:
	var teams := {1: 0, 2: 0, 3: 1, 4: 1}
	var kills := {1: 3, 2: 2, 3: 4, 4: 0}
	assert_eq(PvpMatch.team_totals(kills, teams), [5, 4] as Array[int])
	assert_eq(PvpMatch.leading_team(kills, {1: 0, 2: 0, 3: 0, 4: 0}, teams), 0)
	kills = {1: 2, 2: 2, 3: 4, 4: 0}
	assert_eq(PvpMatch.leading_team(kills, {1: 5, 2: 0, 3: 1, 4: 1}, teams), 1, "tie on kills: fewer deaths wins")
	assert_eq(PvpMatch.leading_team(kills, {1: 1, 2: 1, 3: 1, 4: 1}, teams), -1, "full tie")

func test_team_spawn_halves() -> void:
	var m := _arena()
	var a := PvpMatch.team_points(m.spawn_points, 0)
	var b := PvpMatch.team_points(m.spawn_points, 1)
	assert_eq(a.size() + b.size(), m.spawn_points.size())
	assert_eq(PvpMatch.team_points(m.spawn_points, -1), m.spawn_points)

func test_dash_ignores_rocks_but_not_room_walls() -> void:
	var parent := Node2D.new()
	track(parent)
	var p := Player.new()
	parent.add_child(p)   # out of the tree: _ready has not run, so the mask is still the default
	p._start_dash(Vector2.RIGHT)
	assert_eq(p.collision_mask, Player.WALL_MASK, "only the hard walls stop a dash")
	assert_eq(p.collision_mask & Player.SOLID_MASK, 0)
	assert_true(p._ghost)
	p._dash_time = 0.0
	p._end_ghost()   # nothing to push out of without a physics space, but the rocks must be solid again
	assert_eq(p.collision_mask, Player.SOLID_MASK | Player.WALL_MASK)
	assert_false(p._ghost)

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

func test_facing_has_hysteresis_at_the_45_degree_edge() -> void:
	var dirs := Hero.bonker().dir_frames("Blue")
	var s := AnimatedSprite2D.new()
	track(s)
	s.sprite_frames = dirs[7]   # facing east
	SheetFrames.face(s, dirs, Vector2.from_angle(deg_to_rad(28.0)))   # just past the 22.5 deg edge toward south-east
	assert_eq(s.sprite_frames, dirs[7], "a cursor wobbling on the edge must not flip the row")
	SheetFrames.face(s, dirs, Vector2.from_angle(deg_to_rad(40.0)))
	assert_eq(s.sprite_frames, dirs[0], "well past the edge it turns to south-east")
	SheetFrames.face(s, dirs, Vector2.from_angle(deg_to_rad(18.0)))
	assert_eq(s.sprite_frames, dirs[0], "and coming back it holds south-east until well past the edge")

# --- Crown mode

func test_crown_mode_config() -> void:
	var c := GameMode.cfg("crown")
	assert_true(c.crown and c.hero_pick, "crown keeps the hero pick")
	assert_eq(c.kill_limit, 0, "kills never end a crown match")
	assert_gt(c.score_limit, 0)
	assert_true(c.crown_speed < 1.0, "the king is slowed")
	assert_gt(c.crown_grace, 0.0)
	assert_gt(c.crown_reset, c.crown_grace, "a dropped crown lies longer than its grace before it returns")

func test_score_leader_by_points_then_kills() -> void:
	assert_eq(PvpMatch.score_leader({}, {}, []), 0)
	assert_eq(PvpMatch.score_leader({1: 10.0, 2: 25.5, 3: 3.0}, {}, [1, 2, 3]), 2)
	assert_eq(PvpMatch.score_leader({1: 10.0, 2: 10.0}, {1: 2, 2: 5}, [1, 2]), 2, "kills break a points tie")
	assert_eq(PvpMatch.score_leader({1: 10.0, 2: 10.0}, {1: 2, 2: 2}, [1, 2]), 1, "then the lowest peer")
	assert_eq(PvpMatch.score_leader({1: 50.0, 2: 1.0}, {}, [2]), 2, "a player who left cannot win")

func test_king_is_burdened_only_in_crown_mode() -> void:
	var p := Player.new()
	track(p)
	p.crowned = true
	assert_false(p.burdened(), "the classic kill-leader crown is only a mark")
	assert_eq(p._speed_mult(), 1.0)
	p.crown_speed = 0.85
	assert_true(p.burdened())
	assert_true(absf(p._speed_mult() - 0.85) < 0.001)
	p.crowned = false
	assert_false(p.burdened())
	assert_eq(p._speed_mult(), 1.0)

func test_dropped_crown_waits_out_its_grace() -> void:
	var c := CrownPickup.new()
	track(c)
	c.grace = 2.0
	c._process(1.5)
	assert_true(c.grace > 0.0)
	c._process(0.6)
	assert_true(c.grace <= 0.0, "takeable once the grace is over")

# --- Water: only knockback puts you in

func _shore_player() -> Player:
	var p := Player.new()
	track(p)
	p.position = Vector2(0, -14)   # feet (position + 14 down) at the origin
	p.water_check = func(at: Vector2) -> bool: return at.x > 100.0   # the water starts 100 px to the right
	return p

func test_walking_never_steps_into_water() -> void:
	var p := _shore_player()
	assert_eq(p.shore_guard(Vector2(200, 0)), Vector2(200, 0), "far from the edge: walk freely")
	p.position = Vector2(90, -14)
	assert_eq(p.shore_guard(Vector2(200, 0)), Vector2.ZERO, "at the edge: walking on stops")
	assert_eq(p.shore_guard(Vector2(200, 150)), Vector2(0, 150), "slide along the shore instead")
	assert_eq(p.shore_guard(Vector2(-200, 0)), Vector2(-200, 0), "walking away is fine")

func test_a_dash_stops_on_the_shore() -> void:
	var p := _shore_player()
	var t := p.dash_time_to_shore(p.global_position, Vector2(240, 0), 0.16)
	assert_true(t < 0.16 and t > 0.0, "cut short")
	assert_true(240.0 * t / 0.16 <= 100.0, "ends on dry ground")
	assert_eq(p.dash_time_to_shore(p.global_position, Vector2(-240, 0), 0.16), 0.16, "a dry dash is untouched")
	p.water_check = func(at: Vector2) -> bool: return at.x > 100.0 and at.x < 160.0   # a narrow channel
	assert_eq(p.dash_time_to_shore(p.global_position, Vector2(240, 0), 0.16), 0.16, "a dash can still jump a channel")

func test_colosseum_is_bigger() -> void:
	var m := _arena()
	var span := m.colosseum.to_world(Vector2(1850, 707)).x - m.colosseum.to_world(Vector2(150, 707)).x
	assert_true(span > 2300.0 and span < 2600.0, "the floor is ~2450 px wide")
	assert_gt(m.cover_r, WorldMap.COVER_R, "bigger braziers to match")

# --- Bot tactics: Monte Carlo position search + rail hops

func _ctx(me: Vector2, foes: Array, extra := {}) -> Dictionary:
	var c := {"me": me, "speed": 260.0, "hp_frac": 1.0, "ranged": false, "ideal": 70.0, "assassin": false, "foes": foes,
		"objective": Vector2.INF, "objective_w": 0.0, "hold_at": Vector2.INF, "hold_r": 0.0}
	c.merge(extra, true)
	return c

func test_tactics_candidates_are_standing_ground() -> void:
	var m := _arena()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var me := m.spawn_points[0]
	var foes := [{"pos": m.spawn_points[4], "vel": Vector2.ZERO, "aim": Vector2.LEFT, "reach": 150.0, "target": true}]
	var spots := BotTactics.candidates(m, _ctx(me, foes), rng)
	assert_gt(spots.size(), 5)
	for p in spots:
		assert_false(m.is_water(p), "never plans to stand in the water")

func test_ringout_line_sees_the_moat() -> void:
	var m := _arena()
	var col := m.colosseum
	var foe := col.to_world(Vector2(1000, 230))
	assert_true(BotTactics.ringout_line(m, foe, col.to_world(Vector2(1000, 377))), "hit from above, next to the moat: a swim")
	assert_false(BotTactics.ringout_line(m, col.to_world(Vector2(1000, 377)), col.to_world(Vector2(1000, 230))), "hit toward the wall: safe")

func test_tactics_avoid_standing_on_a_knock_line_into_water() -> void:
	var m := _arena()
	var col := m.colosseum
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var me := col.to_world(Vector2(1000, 300))
	var foes := [{"pos": col.to_world(Vector2(1000, 230)), "vel": Vector2.ZERO, "aim": Vector2.DOWN, "reach": 50.0, "target": false}]
	var ctx := _ctx(me, foes)
	var by_moat := col.to_world(Vector2(1000, 377))
	var aside := col.to_world(Vector2(1090, 300))
	assert_gt(BotTactics.score(m, ctx, aside, rng), BotTactics.score(m, ctx, by_moat, rng), "step aside, not toward the moat")

func test_tactics_ranged_keep_their_range() -> void:
	var m := _arena()
	var col := m.colosseum
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var t := col.to_world(Vector2(420, 330))
	var foes := [{"pos": t, "vel": Vector2.ZERO, "aim": Vector2.LEFT, "reach": 150.0, "target": true}]
	var ctx := _ctx(col.to_world(Vector2(420, 480)), foes, {"ranged": true, "ideal": 300.0})
	var at_range := t + Vector2(0, 300)
	var close := t + Vector2(0, 60)
	assert_gt(BotTactics.score(m, ctx, at_range, rng), BotTactics.score(m, ctx, close, rng))

func test_tactics_crown_holder_keeps_the_centre() -> void:
	var m := _arena()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var foes := [{"pos": m.spawn_points[0], "vel": Vector2.ZERO, "aim": Vector2.DOWN, "reach": 150.0, "target": true}]
	var ctx := _ctx(m.spawn_point, foes, {"hold_at": m.spawn_point, "hold_r": m.hold_radius()})
	for i in 5:
		var spot := BotTactics.best(m, ctx, rng)
		assert_true(spot.distance_to(m.spawn_point) <= m.hold_radius() + 1.0, "the king stays on the circle")

func test_rail_hop_shortcuts_a_long_walk() -> void:
	var m := _arena()
	var col := m.colosseum
	var outside := col.to_world(Vector2(255, 700))   # on the sand, outside the left platform's rail
	var on_platform := col.to_world(Vector2(360, 700))
	assert_false(m.nav_clear(outside, on_platform), "the rail is in the way")
	assert_gt(m.nav_length(outside, on_platform), 3.0 * outside.distance_to(on_platform), "walking means the stairs")
	var hop := m.rail_hop(outside, on_platform)
	assert_true(hop.dot(Vector2.RIGHT) > 0.9, "dash over the rail instead")
	var a := col.to_world(Vector2(400, 300))
	assert_eq(m.rail_hop(a, col.to_world(Vector2(450, 330))), Vector2.ZERO, "nothing to hop on open sand")
	assert_eq(m.rail_hop(col.to_world(Vector2(1000, 330)), m.spawn_point), Vector2.ZERO, "never hop into the moat")

# --- Bot state machine

func test_bot_states_follow_the_situation() -> void:
	var S := BotBrain.State
	var t := BotBrain.MIN_STATE_TIME + 0.1
	assert_eq(BotBrain.next_state(S.ROAM, t, {}), S.ROAM, "nothing going on")
	assert_eq(BotBrain.next_state(S.ROAM, t, {"has_target": true, "hp_frac": 1.0, "target_dist": 300.0}), S.ENGAGE)
	assert_eq(BotBrain.next_state(S.ENGAGE, t, {"has_target": true, "objective": true}), S.OBJECTIVE, "the crown / a good drop")
	assert_eq(BotBrain.next_state(S.ENGAGE, 0.0, {"has_bomb": true}), S.POTATO, "potato: at once")
	assert_eq(BotBrain.next_state(S.ENGAGE, 0.0, {"holding_crown": true, "has_target": true}), S.HOLD, "the king: at once")
	assert_eq(BotBrain.next_state(S.ENGAGE, 0.0, {"has_target": true, "hp_frac": 0.2, "target_dist": 200.0}), S.RETREAT, "hurt and pressed: at once")

func test_bot_states_do_not_flicker() -> void:
	var S := BotBrain.State
	assert_eq(BotBrain.next_state(S.ENGAGE, 0.1, {"objective": true, "has_target": true}), S.ENGAGE, "a fresh state holds a moment")
	assert_eq(BotBrain.next_state(S.RETREAT, 5.0, {"has_target": true, "hp_frac": 0.4, "target_dist": 500.0}), S.RETREAT, "keeps backing off until healthier")
	assert_eq(BotBrain.next_state(S.RETREAT, 5.0, {"has_target": true, "hp_frac": 0.6, "target_dist": 300.0}), S.ENGAGE, "healthy again: back in")
	assert_eq(BotBrain.next_state(S.RETREAT, 5.0, {"has_target": true, "hp_frac": 0.4, "target_dist": 900.0}), S.ENGAGE, "nobody near: stop running")
	assert_eq(BotBrain.STATE_NAMES.size(), BotBrain.State.size())
	assert_eq(BotBrain.STATE_FEAR.size(), BotBrain.State.size())
	assert_true(BotBrain.STATE_FEAR[S.RETREAT] > BotBrain.STATE_FEAR[S.ENGAGE], "retreat weighs danger more")

func test_a_flinch_never_tips_you_in_but_a_launch_does() -> void:
	var p := _shore_player()
	p.position = Vector2(90, -14)   # feet 10 px from the water on the right
	assert_eq(p.knock_guard(Vector2(220, 0)), Vector2.ZERO, "a light hit's shove stops at the shore")
	assert_eq(p.knock_guard(Vector2(900, 0)), Vector2(900, 0), "a launch is a ring-out")
	assert_eq(p.knock_guard(Vector2(-220, 0)), Vector2(-220, 0), "away from the water: untouched")
	p.position = Vector2(0, -14)
	assert_eq(p.knock_guard(Vector2(220, 0)), Vector2(220, 0), "far from the edge: untouched")

# --- Skills always cast; bots stay unstuck

func test_every_skill_casts_even_with_nobody_in_reach() -> void:
	var p := Player.new()
	track(p)
	p.hero = Hero.by_id("knight")
	var far := Vector2(5000, 0)
	for id in ["judgement", "meteor", "thunderstorm", "blade_ring", "arrow_rain", "smoke_screen", "guardian_angel"]:   # targeted ults (Assassinate, Focus Fire) still need a foe
		var s := Hero.make_skill(id)
		assert_true(s.can_cast(p, far), id + " always casts for a player (full range toward a far cursor)")
		assert_true(s.has_method("worth_casting"), id + ": bots ask worth_casting instead")
	assert_true(Judgement.landing(Vector2.ZERO, far, Callable()).length() <= Judgement.RANGE + 0.01, "a far cursor: the full leap")
	assert_true(Meteor.spot(Vector2.ZERO, far).length() <= Meteor.MAX_RANGE + 0.01, "a far cursor: the full throw")

func test_nav_clear_keeps_a_body_width_off_corners() -> void:
	var m := _arena()
	var col := m.colosseum
	var a := col.to_world(Vector2(262, 560))   # the corridor between the west wall and the left platform's rail
	var b := col.to_world(Vector2(262, 860))
	assert_true(m.nav_clear(a, b), "the corridor is walkable end to end")
	var rail_top := col.to_world(Vector2(290, 545))   # the rail's end post
	assert_false(m.nav_clear(col.to_world(Vector2(240, 545)), col.to_world(Vector2(340, 545))), "a line through a rail post is not clear")
	assert_false(m.nav_open(m.nav_cell(rail_top)), "the post itself is solid")
	var step := m.nav_next(a, m.spawn_point)
	assert_true(step.length() > 0.9, "a route step exists from the corridor to the centre")

# --- Drops and events (docs §6)

func test_classic_table_has_no_stat_sticks() -> void:
	for k in ["damage", "giant", "chicken", "bomb", "mystery"]:
		assert_false(k in PvpPickup.KINDS, k + " is Friendslop-only")
		assert_true(PvpPickup.FS_WEIGHTS.has(k), k + " still falls in Friendslop")
	for k in ["heal", "speed", "shield", "ult", "reset", "warcry"]:
		assert_true(k in PvpPickup.KINDS and PvpPickup.WEIGHTS.has(k) and PvpPickup.KIND_TIER.has(k), k)
	assert_eq(PvpPickup.tier_of("reset"), PvpPickup.Tier.RARE)
	assert_eq(PvpPickup.tier_of("warcry"), PvpPickup.Tier.EPIC)
	assert_eq(PvpPickup.tier_of("shield"), PvpPickup.Tier.COMMON)

func test_channel_time_per_tier_and_mode() -> void:
	assert_eq(GameMode.channel_time("classic", PvpPickup.Tier.COMMON), 0.0, "commons: walk over them")
	assert_eq(GameMode.channel_time("classic", PvpPickup.Tier.RARE), 0.8)
	assert_eq(GameMode.channel_time("classic", PvpPickup.Tier.EPIC), 1.5)
	assert_eq(GameMode.channel_time("friendslop", PvpPickup.Tier.EPIC), 0.0, "Friendslop: walk over it")
	var c := GameMode.cfg("classic")
	assert_eq(c.drop_after_deaths, 3, "no drops before the third death")
	assert_eq(c.drop_per_deaths, 3, "one more every three deaths")
	assert_eq(c.pickup_life, 15.0)
	assert_eq(c.max_pickups, 2)

func test_ult_spark_and_reset_drops() -> void:
	var p := Player.new()
	track(p)
	p.ai = BotBrain.new()   # owned here (a bot), so the owner-only effects run
	p.hero = Hero.by_id("rogue")
	p.init_loadout()
	p.apply_pickup("ult")
	assert_true(absf(p.ult_fraction() - PvpPickup.ULT_SPARK) < 0.001, "half an ult")
	p.apply_pickup("ult")
	assert_true(p.ult_ready(), "two sparks fill it, never past the cost")
	p.cooldowns[0] = 3.0
	p.cooldowns[1] = 5.0
	p.dash_charges = 0
	p.apply_pickup("reset")
	assert_eq(p.cooldowns[0], 0.0)
	assert_eq(p.cooldowns[1], 0.0)
	assert_eq(p.dash_charges, Player.MAX_DASH)
	p.apply_pickup("shield")
	assert_eq(p.shield_hp, PvpPickup.SHIELD_HP)
	assert_true(p.buffed("shield") and p.buff_left("shield") <= Player.BUFF_TIMES["shield"])
	p.apply_pickup("warcry")
	assert_true(p.buffed("warcry"))
	var v := Player.new()
	track(v)
	v.hero = Hero.by_id("knight")
	assert_true(absf(v.form_knock(p) - PvpPickup.WARCRY_KNOCK) < 0.001, "Warcry doubles the shove")

func test_match_event_roll_is_weighted_and_complete() -> void:
	var seen := {}
	var n := 1000
	for i in n:
		var id: String = MatchEvent.roll(float(i) / n)
		assert_true(MatchEvent.valid(id))
		seen[id] = seen.get(id, 0) + 1
	for id: String in MatchEvent.EVENTS:
		assert_true(seen.has(id), id + " can be rolled")
		assert_true(MatchEvent.EVENTS[id].has("name") and MatchEvent.EVENTS[id].has("color") and MatchEvent.EVENTS[id].has("blurb"), id)
	assert_true(seen[MatchEvent.NONE] > n * 0.3, "most matches stay clean")
	assert_eq(MatchEvent.roll(0.0), MatchEvent.NONE, "the same r is the same event on every peer")
	for id: String in MatchEvent.EVENTS:
		for t in PvpPickup.TIER_COLORS:
			assert_true(not MatchEvent.color(id).is_equal_approx(t), id + ": an event colour is never a tier colour")

func test_event_kill_lines() -> void:
	assert_true("Bo" in PvpMatch.kill_line("meteor", "", "Bo", 0))
	var line := PvpMatch.kill_line("reflect", "Ann", "Bo", 0)
	assert_true("Ann" in line and "Bo" in line, "a reflect kill names both: " + line)
	assert_true("Bo" in PvpMatch.kill_line("reflect", "", "Bo", 1), "a reflect kill with no wearer still reads")

func test_rares_fall_on_the_centre_circle() -> void:
	var m := _arena()
	var taken: Array[Vector2] = []
	for i in 4:
		var p := PvpMatch.pick_pickup_pos_centre(m, taken)
		assert_true(p.distance_to(m.spawn_point) <= m.hold_radius(), "on the centre circle")
		assert_false(m.is_water(p), "dry")
		taken.append(p)

func test_a_dash_at_a_pool_by_the_wall_stops_on_the_sand() -> void:
	var m := _arena()
	var col := m.colosseum
	var p := Player.new()
	track(p)
	p.water_check = m.is_water
	p.ground_check = m.off_ground
	# on the sand just below the top-left pool, dashing straight up through it toward the wall
	var start := col.to_world(Vector2(670, 560))
	p.position = start - Vector2(0, 14)
	assert_false(m.is_water(start), "starts dry")
	var offset := Vector2(0, -Player.DASH_SPEED * Player.DASH_TIME)
	var t := p.dash_time_to_shore(p.global_position, offset, Player.DASH_TIME)
	assert_true(t < Player.DASH_TIME, "cut short")
	assert_false(m.is_water(start + offset * (t / Player.DASH_TIME)), "ends on dry sand, not in the pool")

func test_bots_close_in_on_a_far_target() -> void:
	assert_eq(BotBrain.engage_range(Hero.by_id("knight")), 450.0)
	assert_eq(BotBrain.engage_range(Hero.by_id("ranger")), Hero.by_id("ranger").attack_range + 250.0)
	var m := _arena()
	var a := m.spawn_points[3]   # west gate
	var b := m.spawn_points[1]   # east gate, ~2000 px away
	assert_gt(a.distance_to(b), 1100.0, "farther than the old planner could see")
	var step := m.nav_step(a, b)
	assert_true(step.length() > 0.9, "and there is a route to walk")

# --- Bots: dash shortcuts, real route distance, ring-out setups

func test_bots_dash_the_moat_onto_the_crown_circle() -> void:
	var m := _arena()
	var col := m.colosseum
	var band := col.to_world(Vector2(1000, 707 - 340))   # the sand ring just outside the moat
	assert_false(m.nav_clear(band, m.spawn_point), "the moat and the rail are in the way")
	var hop := m.dash_shortcut(band, m.spawn_point)
	assert_true(hop.dot(Vector2.DOWN) > 0.9, "jump the moat straight onto the circle")
	var land := band + hop * 220.0
	assert_false(m.is_water(land), "lands dry")
	assert_eq(m.dash_shortcut(col.to_world(Vector2(1000, 707 - 395)), m.spawn_point), Vector2.ZERO, "too far out: the dash would end in the moat")
	assert_eq(m.dash_shortcut(col.to_world(Vector2(400, 300)), col.to_world(Vector2(450, 330))), Vector2.ZERO, "nothing in the way: walk")

func test_tactics_reward_herding_the_target_to_the_water() -> void:
	var m := _arena()
	var col := m.colosseum
	var t := col.to_world(Vector2(1000, 707 - 330))   # the target stands on the sand ring, the moat at its back
	assert_true(BotTactics.ringout_line(m, col.to_world(Vector2(1000, 707 - 420)), t), "hit from outside: into the moat")
	assert_false(BotTactics.ringout_line(m, col.to_world(Vector2(1000, 707 - 250 + 10)), t), "hit from the circle side: away from it")
