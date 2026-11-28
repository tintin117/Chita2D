extends McpTestSuite

class TestMap extends WorldMap:
	var shore_x := INF

	func is_water(pos: Vector2) -> bool:
		return pos.x > shore_x

	func make_grid(columns: int, rows: int) -> void:
		nav = AStarGrid2D.new()
		nav.region = Rect2i(0, 0, columns, rows)
		nav.cell_size = Vector2.ONE * NAV_CELL
		nav.offset = Vector2.ONE * NAV_CELL * 0.5
		nav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		nav.update()

class TestArena extends Node2D:
	var _map := TestMap.new()
	var _pickups: Dictionary = {}
	var _crown_obj: CrownPickup
	var _cm := false

class TestPlayer extends Player:
	func _ready() -> void:
		add_to_group("players")
		init_loadout()
		_sprite = AnimatedSprite2D.new()
		_sprite.sprite_frames = SpriteFrames.new()
		_sprite.sprite_frames.add_animation("idle")
		add_child(_sprite)
		set_physics_process(false)

func suite_name() -> String:
	return "bot_regressions"

func _arena() -> TestArena:
	var arena := TestArena.new()
	track(arena)
	arena.add_child(arena._map)
	(Engine.get_main_loop() as SceneTree).root.add_child(arena)
	return arena

func _player(arena: TestArena, at: Vector2, id := "ranger") -> Player:
	var p := TestPlayer.new()
	p.position = at
	p.hero = Hero.by_id(id)
	arena.add_child(p)
	return p

func _bot(arena: TestArena, at := Vector2.ZERO, id := "ranger") -> Player:
	var p := _player(arena, at, id)
	p.ai = BotBrain.new()
	p.ai.setup(p, arena, 1.0)
	p.ai.mood = BotBrain.Mood.AGGRO
	return p

func test_dodge_supersedes_tactical_dash_and_shore_rescue_supersedes_both() -> void:
	var arena := _arena()
	arena._map.shore_x = 150.0
	var p := _bot(arena, Vector2(120, 40))
	var bot := p.ai
	bot._try_dash(Vector2.RIGHT, 1.0)
	bot._try_dash(Vector2.DOWN, 1.0, BotBrain.DashPriority.DODGE)
	bot._try_dash(Vector2.RIGHT, 1.0)
	assert_eq(bot._dash_dir, Vector2.DOWN, "a dodge wins over a tactical request")
	p.velocity = Vector2.RIGHT * 200.0
	bot._safety()
	assert_eq(bot._dash_priority, BotBrain.DashPriority.RESCUE)
	assert_eq(bot._dash_dir, Vector2.LEFT, "dash away from the shore")
	assert_true(bot.take_dash())
	assert_false(bot.take_dash(), "each request is consumed once")

func test_removed_pickup_interrupts_the_state_dwell_between_decisions() -> void:
	var arena := _arena()
	var p := _bot(arena)
	var drop := PvpPickup.new()
	drop.position = Vector2(200, 0)
	drop.kind = "damage"
	arena.add_child(drop)
	arena._pickups[drop.id] = drop
	var bot := p.ai
	bot._state_t = BotBrain.MIN_STATE_TIME
	bot._react = 0.0
	bot.think(0.01)
	assert_eq(bot.state, BotBrain.State.OBJECTIVE)
	assert_eq(bot._objective, drop)
	arena._pickups.erase(drop.id)
	bot._react = 0.25
	bot.think(0.01)
	assert_eq(bot.state, BotBrain.State.ROAM)
	assert_eq(bot._last_goal, Vector2.INF)
	assert_eq(bot.move, Vector2.ZERO)

func test_death_clears_active_intent_before_the_next_physics_tick() -> void:
	var p := _bot(_arena())
	var bot := p.ai
	bot._set_state(BotBrain.State.ENGAGE)
	bot.move = Vector2.RIGHT
	bot._steer = Vector2.RIGHT
	bot.held[1] = true
	bot._try_dash(Vector2.RIGHT, 1.0)
	p._charge_slot = 1
	p._die()
	assert_eq(bot.state, BotBrain.State.ROAM)
	assert_eq(bot.move, Vector2.ZERO)
	assert_eq(bot._steer, Vector2.ZERO)
	assert_false(bot.holding())
	assert_false(bot.take_dash())
	assert_eq(p._charge_slot, -1)

func test_engage_reassesses_immediately_when_its_target_dies() -> void:
	var arena := _arena()
	var p := _bot(arena)
	var foe := _player(arena, Vector2(250, 0), "knight")
	var bot := p.ai
	bot._set_state(BotBrain.State.ENGAGE)
	bot._target = foe
	bot._react = 0.25
	bot._retarget = 0.7
	bot.held[0] = true
	foe.down = true
	bot.think(0.01)
	assert_eq(bot._target, null)
	assert_false(bot.holding(), "the held attack is dropped before Player can cast it")

func test_engage_retargets_on_the_tick_its_foe_becomes_hidden() -> void:
	var arena := _arena()
	var p := _bot(arena)
	var foe := _player(arena, Vector2(250, 0), "knight")
	var alternate := _player(arena, Vector2(0, 250), "knight")
	var bot := p.ai
	bot._set_state(BotBrain.State.ENGAGE)
	bot._target = foe
	bot._react = 0.25
	bot._retarget = 0.7
	foe.veil(2.0)
	bot.think(0.01)
	assert_eq(bot._target, alternate, "an eligible alternate can replace the hidden foe immediately")

func test_engage_keeps_its_attack_between_decisions_while_the_foe_is_visible() -> void:
	var arena := _arena()
	var p := _bot(arena)
	var foe := _player(arena, Vector2(250, 0), "knight")
	_player(arena, Vector2(0, 100), "knight")
	var bot := p.ai
	bot._set_state(BotBrain.State.ENGAGE)
	bot._target = foe
	bot._react = 0.25
	bot._retarget = 0.7
	bot.held[0] = true
	bot.think(0.01)
	assert_eq(bot._target, foe)
	assert_true(bot.held[0])
	assert_true(is_equal_approx(bot._react, 0.24), "the normal reaction cadence still applies")

func test_drawn_power_shot_is_cancelled_when_its_target_picks_up_the_bomb() -> void:
	var arena := _arena()
	var p := _bot(arena)
	var foe := _player(arena, Vector2(400, 0), "knight")
	var bot := p.ai
	bot._set_state(BotBrain.State.ENGAGE)
	bot._target = foe
	bot._charge_target = foe
	bot._react = 0.25
	p._charge_slot = 1
	p.charge_show = 0.8
	foe.has_bomb = true
	bot.think(0.01)
	assert_eq(p._charge_slot, -1)
	assert_eq(p.cooldowns[1], 0.0)
	assert_false(bot.holding())

func test_bot_searches_last_sighting_and_gives_up_a_moving_hidden_rogue() -> void:
	var arena := _arena()
	var p := _bot(arena, Vector2.ZERO, "knight")
	var foe := _player(arena, Vector2(320, 0), "rogue")
	foe.break_stalk()
	p.ai._set_state(BotBrain.State.ENGAGE)
	p.ai._decide()
	assert_eq(p.ai._target, foe)
	var last_seen := foe.global_position
	foe.veil(3.0)
	foe.position = Vector2(320, 240)
	p.ai.think(0.01)
	assert_eq(p.ai.state, BotBrain.State.ROAM)
	assert_eq(p.ai._target, null)
	assert_eq(p.ai._last_goal, last_seen)
	assert_false(p.ai.holding())
	foe.position = Vector2(500, -200)
	p.ai.think(0.4)
	assert_eq(p.ai._last_goal, last_seen, "moving in smoke cannot move the search destination")
	p.ai._search_t = 0.01
	p.ai._react = 0.25
	p.ai.think(0.02)
	assert_eq(p.ai._last_goal, Vector2.INF, "the search expires")

func test_looter_leaves_the_last_sighting_when_rogue_enters_smoke() -> void:
	var arena := _arena()
	var p := _bot(arena)
	p.ai.mood = BotBrain.Mood.LOOTER
	var foe := _player(arena, Vector2(320, 0), "rogue")
	foe.break_stalk()
	p.ai._set_state(BotBrain.State.ENGAGE)
	p.ai._decide()
	foe.veil(2.0)
	p.ai.think(0.01)
	assert_eq(p.ai._target, null)
	assert_eq(p.ai._last_goal, Vector2.INF)

func test_bot_spell_aim_requires_a_noticeable_rogue_shimmer() -> void:
	var arena := _arena()
	var p := _bot(arena)
	var foe := _player(arena, Vector2(230, 0), "rogue")
	assert_true(foe.stalking())
	assert_false(foe.hidden_from(p), "a faint shimmer is visible here")
	assert_eq(Spell.pick_foe(p, foe.position, Vector2.RIGHT, 50.0, 0.4, 500.0), null)
	foe.position.x = 140.0
	assert_eq(Spell.pick_foe(p, foe.position, Vector2.RIGHT, 50.0, 0.4, 500.0), foe)
	foe.veil(2.0)
	assert_false(p.ai.can_see_foe(foe))
	var pact := _bot(arena, Vector2(0, 40), "pactknight")
	assert_true(pact.ai.can_see_foe(foe), "Darkvision can still reveal a foe in smoke")

func test_bot_focus_volley_pauses_when_rogue_enters_smoke() -> void:
	var arena := _arena()
	var p := _bot(arena)
	var foe := _player(arena, Vector2(130, 0), "rogue")
	p.focus_fire_on(foe, FocusFire.DURATION)
	foe.veil(2.0)
	assert_false(p._try_focus_fire())
	assert_true(p.focus_firing(), "the rest of the Focus Volley window is preserved")
	assert_eq(p.cooldowns[0], 0.0)

func test_cautious_bot_gives_up_a_stalled_chase_before_aggro_bot() -> void:
	var arena := _arena()
	var p := _bot(arena, Vector2.ZERO, "knight")
	var foe := _player(arena, Vector2(400, 0), "rogue")
	foe.break_stalk()
	foe.hp = 1
	var bot := p.ai
	bot.mood = BotBrain.Mood.CAUTIOUS
	bot._set_state(BotBrain.State.ENGAGE)
	bot._decide()
	bot.think(0.01)
	bot.think(1.6)
	assert_eq(bot._target, null)
	assert_eq(bot._passed_target, foe)
	assert_eq(bot.state, BotBrain.State.ROAM)
	bot.think(BotBrain.CHASE_RECONSIDER)
	assert_eq(bot._target, foe, "the bot can reconsider a visible foe after a break")
	bot.reset_intent()
	bot._set_state(BotBrain.State.ENGAGE)
	bot._decide()
	bot.think(0.01)
	foe.position.x = 340.0
	bot.think(1.6)
	assert_eq(bot._target, foe, "closing the gap resets chase patience")
	foe.position.x = 400.0
	bot.reset_intent()
	bot.mood = BotBrain.Mood.AGGRO
	bot._set_state(BotBrain.State.ENGAGE)
	bot._decide()
	bot.think(0.01)
	bot.think(1.6)
	assert_eq(bot._target, foe, "Aggro gives the chase longer")

func test_distant_wounded_rogue_loses_to_a_nearby_fight() -> void:
	var arena := _arena()
	var p := _bot(arena, Vector2.ZERO, "knight")
	var rogue := _player(arena, Vector2(750, 0), "rogue")
	rogue.break_stalk()
	rogue.hp = 1
	var nearby := _player(arena, Vector2(0, 220), "knight")
	p.ai._decide()
	assert_eq(p.ai._target, nearby)

func test_power_shot_stays_committed_when_a_foe_moves_inside_start_range() -> void:
	var arena := _arena()
	var p := _bot(arena)
	var foe := _player(arena, Vector2(400, 0), "knight")
	var bot := p.ai
	bot._target = foe
	bot._attack(p.position, foe.position, 400.0, Vector2.ZERO)
	p._try_cast()
	assert_eq(p._charge_slot, 1)
	bot._target = _player(arena, Vector2(0, 350), "knight")
	foe.position.x = 140.0
	p.charge_show = 0.3
	bot._continue_charge()
	assert_true(bot.held[1], "too early to release a useful shot")
	assert_true(bot._aim_goal.x > 100.0, "the draw keeps tracking the original foe after a retarget")
	p.charge_show = 0.7
	bot._continue_charge()
	assert_false(bot.held[1], "release a useful draw against a foe closing into melee")
	assert_eq(p._charge_slot, 1, "Player still owns the actual release")

func test_power_shot_cancels_through_cover_without_spending_cooldown() -> void:
	var arena := _arena()
	var p := _bot(arena)
	var foe := _player(arena, Vector2(400, 0), "knight")
	var bot := p.ai
	bot._target = foe
	bot._attack(p.position, foe.position, 400.0, Vector2.ZERO)
	p._try_cast()
	assert_eq(p._charge_slot, 1)
	arena._map.cover.append(Vector2(200, 0))
	bot._continue_charge()
	assert_eq(p._charge_slot, -1)
	assert_eq(p.cooldowns[1], 0.0)
	assert_false(bot.holding())

func test_tactics_rejects_a_disconnected_spot_and_accepts_a_viable_dash() -> void:
	var arena := _arena()
	var m := arena._map
	m.make_grid(18, 7)
	for x in range(4, 7):
		for y in 7:
			m.nav.set_point_solid(Vector2i(x, y), true)
	var me := m.nav_point(Vector2i(2, 3))
	var goal := m.nav_point(Vector2i(9, 3))
	var ctx := {"me": me, "objective": goal, "objective_w": 100.0}
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	assert_eq(BotTactics.score(m, ctx, goal, rng), -INF)
	assert_true(BotTactics.best(m, ctx, rng).x < 128.0)
	ctx.dash_px = BotBrain.DASH_DISTANCE
	assert_true(is_finite(BotTactics.score(m, ctx, goal, rng)))
	assert_eq(m.dash_shortcut(me, goal, BotBrain.DASH_DISTANCE), Vector2.RIGHT)

func test_blocked_walk_uses_a_cached_route_and_marks_stalled_goal() -> void:
	var arena := _arena()
	var m := arena._map
	m.make_grid(12, 10)
	for y in 6:
		m.nav.set_point_solid(Vector2i(5, y), true)
	var start := m.nav_point(Vector2i(2, 2))
	var goal := m.nav_point(Vector2i(8, 2))
	var p := _bot(arena, start)
	p.dash_charges = 0
	var bot := p.ai
	assert_true(bot._go(start, goal).y > 0.0, "route heads toward the opening")
	var route := bot._route
	assert_true(route.size() > 2)
	bot._go(start + Vector2(0, 8), goal + Vector2(4, 0))
	assert_eq(bot._route, route, "same goal cell keeps the original route")
	bot._check_progress(start, Vector2.DOWN)
	bot._mark_t = 0.61
	assert_true(bot._check_progress(start, Vector2.DOWN))
	assert_eq(bot._route_dist(start, goal), INF, "try a different goal after a stall")
	assert_eq(bot._go(start, goal), Vector2.ZERO)

func test_crown_holder_returns_to_center_instead_of_chasing_distant_foe() -> void:
	var arena := _arena()
	arena._cm = true
	arena._map.spawn_point = Vector2.ZERO
	var p := _bot(arena, Vector2(500, 0), "knight")
	p.crowned = true
	var foe := _player(arena, Vector2(1500, 0))
	var bot := p.ai
	bot._target = foe
	bot._set_state(BotBrain.State.HOLD)
	bot._rng.seed = 13
	var want := bot._tactical(p.position, foe.position, 1000.0, [foe], 1.0)
	assert_true(want.x < 0.0)
	assert_true(bot._spot.distance_to(arena._map.spawn_point) <= arena._map.hold_radius())

func _engage(p: Player, foe: Player) -> void:
	p.ai._set_state(BotBrain.State.ENGAGE)
	p.ai._target = foe
	p.ai._attack(p.position, foe.position, p.position.distance_to(foe.position), Vector2.ZERO)

func test_rogue_only_rushes_when_he_can_land_a_follow_up_backstab() -> void:
	var arena := _arena()
	var p := _bot(arena, Vector2.ZERO, "rogue")
	var foe := _player(arena, Vector2(160, 0), "knight")
	foe.aim_dir = Vector2.LEFT
	_engage(p, foe)
	assert_false(p.ai.holding(), "the full blink would overshoot Stab range")
	foe.position.x = 310.0
	_engage(p, foe)
	assert_true(p.ai.held[1], "the blink crosses the foe and lands within reach behind it")
	arena._map.shore_x = 365.0
	_engage(p, foe)
	assert_false(p.ai.holding(), "save the rush when its destination is wet")
	arena._map.shore_x = INF
	foe.aim_dir = Vector2.RIGHT
	_engage(p, foe)
	assert_false(p.ai.holding(), "rushing from the back would land in front")

func test_rogue_closes_from_stalk_and_spends_the_opening_between_bursts() -> void:
	var arena := _arena()
	var p := _bot(arena, Vector2.ZERO, "rogue")
	var foe := _player(arena, Vector2(155, 0), "knight")
	foe.aim_dir = Vector2.LEFT
	p.ai._target = foe
	p.ai._set_state(BotBrain.State.ENGAGE)
	p.ai._bursting = false
	assert_gt(p.ai._tactical(p.position, foe.position, 155.0, [foe], 1.0).x, 0.0)
	foe.position.x = 85.0
	_engage(p, foe)
	assert_true(p.ai.held[0], "Stalk can produce an opener even between bursts")
	p.break_stalk()
	p.position.x = 150.0
	foe._frozen_left = ShadowRush.FREEZE
	var want := p.ai._tactical(p.position, foe.position, 65.0, [foe], 1.0)
	assert_eq(want, Vector2.ZERO, "stay at the frozen target's back")
	_engage(p, foe)
	assert_true(p.ai.held[0], "follow the Rush with a Stab")

func test_rogue_saves_smoke_until_it_can_cover_him_and_the_foe() -> void:
	var arena := _arena()
	var p := _bot(arena, Vector2.ZERO, "rogue")
	var foe := _player(arena, Vector2(300, 0), "knight")
	p.break_stalk()
	p.ult_charge = p.hero.ult_cost
	p.cooldowns[1] = 2.0
	_engage(p, foe)
	assert_false(p.ai.held[Player.ULT_SLOT], "save Smoke when Rogue is still approaching")
	foe.position.x = 150.0
	_engage(p, foe)
	assert_true(p.ai.held[Player.ULT_SLOT])
	var center := SmokeScreen.spot(p.position, p.ai._aim_goal)
	assert_true(SmokeScreen.inside(center, p.position))
	assert_true(SmokeScreen.inside(center, foe.position))

func _set_bait_test_dash(foe: Player, active: bool) -> void:
	foe._ghost = active
	foe._dash_time = Player.DASH_TIME if active else 0.0
	foe._dash_speed = Player.DASH_SPEED

func _prepare_bait(p: Player, foe: Player) -> void:
	p.ai._set_state(BotBrain.State.ENGAGE)
	p.ai._target = foe
	_set_bait_test_dash(foe, true)
	p.ai._tick_bait(0.01)
	_set_bait_test_dash(foe, false)
	p.ai._tick_bait(0.01)
	_engage(p, foe)

func test_engage_baits_with_a_basic_and_punishes_after_a_new_dash_ends() -> void:
	var arena := _arena()
	var p := _bot(arena)
	var foe := _bot(arena, Vector2(400, 0), "knight")
	var bot := p.ai
	_prepare_bait(p, foe)
	assert_eq(bot.held, [true, false, false])
	assert_eq(bot._bait, BotBrain.Bait.BASIC, "a prior dash can prompt the bait")

	_set_bait_test_dash(foe, true)
	bot._tick_bait(0.01)
	bot.on_spell_cast(0)
	bot._tick_bait(0.01)
	assert_eq(bot._bait, BotBrain.Bait.WATCH, "a dash already in progress when the basic fires does not count")
	_set_bait_test_dash(foe, false)
	bot._tick_bait(0.01)
	_engage(p, foe)
	assert_false(bot.holding(), "wait to see what the opponent does")

	_set_bait_test_dash(foe, true)
	bot._tick_bait(0.01)
	_engage(p, foe)
	assert_false(bot.holding(), "wait out the dash itself")
	_set_bait_test_dash(foe, false)
	bot._tick_bait(0.01)
	_engage(p, foe)
	assert_eq(bot.held, [false, true, false])
	bot.on_spell_cast(1)
	assert_eq(bot._bait, BotBrain.Bait.NONE, "the signature consumes the opening")
	assert_false(bot.holding())

func test_engage_punish_respects_cover_cooldown_and_lost_sight() -> void:
	var arena := _arena()
	var p := _bot(arena)
	var foe := _player(arena, Vector2(400, 0), "knight")
	var bot := p.ai
	_prepare_bait(p, foe)
	bot.on_spell_cast(0)
	_set_bait_test_dash(foe, true)
	bot._tick_bait(0.01)
	_set_bait_test_dash(foe, false)
	bot._tick_bait(0.01)
	arena._map.cover.append(Vector2(200, 0))
	_engage(p, foe)
	assert_false(bot.holding())
	arena._map.cover.clear()
	p.cooldowns[1] = 0.02
	_engage(p, foe)
	assert_false(bot.holding())
	p.cooldowns[1] = 0.0
	_engage(p, foe)
	assert_true(bot.held[1], "take the opening once the signature is ready")
	foe.veil(1.0)
	bot.think(0.01)
	assert_eq(bot._bait, BotBrain.Bait.NONE)
	assert_false(bot.holding())

func test_engage_bait_expires_when_the_foe_keeps_their_dash() -> void:
	var arena := _arena()
	var p := _bot(arena)
	var foe := _player(arena, Vector2(400, 0), "knight")
	_prepare_bait(p, foe)
	p.ai.on_spell_cast(0)
	p.ai._tick_bait(BotBrain.DODGE_WINDOW + 0.01)
	assert_eq(p.ai._bait, BotBrain.Bait.NONE)
	_engage(p, foe)
	assert_eq(p.ai._bait, BotBrain.Bait.NONE, "a retry delay gives ordinary attacks a chance")

func test_harder_bots_notice_more_baited_dashes_and_aggro_commits_most_often() -> void:
	var arena := _arena()
	var p := _bot(arena)
	var foe := _player(arena, Vector2(400, 0), "knight")
	var bot := p.ai
	var punish_counts: Array[int] = []
	for profile in [[0.3, BotBrain.Mood.AGGRO], [0.6, BotBrain.Mood.AGGRO], [0.9, BotBrain.Mood.AGGRO], [0.9, BotBrain.Mood.CAUTIOUS], [0.9, BotBrain.Mood.LOOTER]]:
		bot.setup(p, arena, profile[0])
		bot.mood = profile[1]
		bot._rng.seed = 32941
		var commits := 0
		for i in 160:
			bot._bait_retry = 0.0
			_prepare_bait(p, foe)
			bot.on_spell_cast(0)
			_set_bait_test_dash(foe, true)
			bot._tick_bait(0.01)
			if bot._bait == BotBrain.Bait.PUNISH:
				commits += 1
			_set_bait_test_dash(foe, false)
			bot._clear_bait()
			bot._tick_bait(0.01)
		punish_counts.append(commits)
	assert_true(punish_counts[0] < punish_counts[1] and punish_counts[1] < punish_counts[2])
	assert_true(punish_counts[2] > punish_counts[3] and punish_counts[3] > punish_counts[4])

func test_engage_favors_the_faster_shot_against_a_moving_target() -> void:
	var arena := _arena()
	var p := _bot(arena)
	var foe := _player(arena, Vector2(450, 0), "knight")
	p.velocity = Vector2.RIGHT * p.speed
	foe.velocity = Vector2.DOWN * foe.speed
	_engage(p, foe)
	assert_eq(p.ai.held, [true, false, false], "the basic has a better chance than the drawn shot")
	p.ai._set_state(BotBrain.State.HOLD)
	p.ai._attack(p.position, foe.position, 450.0, Vector2.ZERO)
	assert_eq(p.ai.held, [false, true, false], "other states keep their attack priority")

func test_engage_uses_anchor_slam_before_the_tide_when_the_combo_is_open() -> void:
	var arena := _arena()
	arena._map.shore_x = 175.0
	var p := _bot(arena, Vector2.ZERO, "tidecaller")
	var foe := _player(arena, Vector2(110, 0), "knight")
	p.ult_charge = p.hero.ult_cost
	_engage(p, foe)
	assert_eq(p.ai.held, [false, true, false], "apply weaken before spending the ult")
	foe.weaken(KeelSlam.WEAK_TIME)
	_engage(p, foe)
	assert_eq(p.ai.held, [false, false, true], "take the follow-up while weaken lasts")
	foe._weak_left = 0.01
	_engage(p, foe)
	assert_eq(p.ai.held, [false, true, false], "refresh weaken if it expires before the wave arrives")

func test_easier_bots_more_often_rush_a_viable_attack_and_miss_the_follow_up() -> void:
	var arena := _arena()
	arena._map.shore_x = 175.0
	var p := _bot(arena, Vector2.ZERO, "tidecaller")
	var foe := _player(arena, Vector2(110, 0), "knight")
	p.ult_charge = p.hero.ult_cost
	foe.weaken(KeelSlam.WEAK_TIME)
	p.ai._target = foe
	var missed_follow_ups: Array[int] = []
	for difficulty in [0.3, 0.6, 0.9]:
		p.ai.setup(p, arena, difficulty)
		p.ai._rng.seed = 2381
		var misses := 0
		for i in 256:
			var slot := p.ai._engage_attack(Vector2(0, 8), foe.position, 110.0, true, false)
			if slot != Player.ULT_SLOT:
				misses += 1
		missed_follow_ups.append(misses)
	assert_gt(missed_follow_ups[0], missed_follow_ups[1], "Easy rushes more often than Normal")
	assert_gt(missed_follow_ups[1], missed_follow_ups[2], "Normal still makes occasional mistakes")
	assert_eq(missed_follow_ups[2], 0, "Hard takes this clear combo window every time")

func test_difficulty_scales_shot_lead_and_preserves_easy_aim_error() -> void:
	var arena := _arena()
	var p := _bot(arena)
	var foe := _player(arena, Vector2(400, 0), "knight")
	var basic := p.spell_in(0)
	var imperfect_aim := Vector2.from_angle(0.12)
	foe.velocity = Vector2.DOWN * foe.speed
	p.ai._target = foe
	var lead_offsets: Array[float] = []
	var aim_errors: Array[float] = []
	for difficulty in [0.3, 0.6, 0.9]:
		p.ai.setup(p, arena, difficulty)
		lead_offsets.append(p.ai._aim_for(basic, p.position, foe.position).y)
		aim_errors.append(absf(basic.aim(p, imperfect_aim).angle()))
	assert_true(lead_offsets[0] < lead_offsets[1] and lead_offsets[1] < lead_offsets[2])
	assert_true(is_equal_approx(aim_errors[0], 0.12), "Easy shots keep their imperfect aim")
	assert_true(aim_errors[0] > aim_errors[1] and aim_errors[1] > aim_errors[2])

func test_engage_opens_a_charge_only_if_the_control_window_is_long_enough() -> void:
	var arena := _arena()
	var p := _bot(arena)
	var foe := _player(arena, Vector2(450, 0), "knight")
	p.velocity = Vector2.RIGHT * p.speed
	foe.velocity = Vector2.DOWN * foe.speed
	foe._rooted_left = 0.2
	_engage(p, foe)
	assert_eq(p.ai.held, [true, false, false], "brief control favors the fast attack")
	foe._rooted_left = 2.0
	_engage(p, foe)
	assert_eq(p.ai.held, [false, true, false], "long control lets the committed shot land")

func test_engage_prefers_an_attack_that_can_launch_the_foe_into_water() -> void:
	var arena := _arena()
	var p := _bot(arena)
	var foe := _player(arena, Vector2(450, 0), "knight")
	p.velocity = Vector2.RIGHT * p.speed
	foe.velocity = Vector2.DOWN * foe.speed
	_engage(p, foe)
	assert_eq(p.ai.held, [true, false, false])
	arena._map.shore_x = 515.0
	_engage(p, foe)
	assert_eq(p.ai.held, [true, false, false], "water does not outweigh a low chance of landing the launch")
	foe.velocity *= 0.2
	_engage(p, foe)
	assert_eq(p.ai.held, [false, true, false], "the launch can reach water, the basic cannot")
	arena._map.rails.append(PackedVector2Array([Vector2(500, -500), Vector2(500, 800)]))
	_engage(p, foe)
	assert_eq(p.ai.held, [true, false, false], "a rail intercepts the launch")

func test_engage_excludes_cooldowns_and_attacks_that_cannot_land() -> void:
	var arena := _arena()
	var p := _bot(arena)
	var foe := _player(arena, Vector2(400, 0), "knight")
	p.cooldowns[1] = 2.0
	_engage(p, foe)
	assert_eq(p.ai.held, [true, false, false])
	arena._map.cover.append(Vector2(200, 0))
	_engage(p, foe)
	assert_false(p.ai.holding(), "cover vetoes the only ready shot")
	arena._map.cover.clear()
	foe._angel_left = 2.0
	_engage(p, foe)
	assert_false(p.ai.holding(), "the only ready shot would arrive during immunity")

func test_attack_utility_reads_the_real_finisher_window() -> void:
	var arena := _arena()
	var p := _bot(arena, Vector2.ZERO, "knight")
	var foe := _player(arena, Vector2(110, 0), "ranger")
	p.ai._target = foe
	var basic := p.spell_in(0) as HeroBasic
	var from := p.position + Vector2(0, 8)
	basic._combo = 2
	basic._last_msec = Time.get_ticks_msec()
	var active := p.ai._attack_utility(0, basic, from, foe.position, foe.position)
	basic._last_msec -= HeroBasic.COMBO_WINDOW_MSEC + 10
	var expired := p.ai._attack_utility(0, basic, from, foe.position, foe.position)
	assert_gt(active, expired, "value falls when the live combo expires")

func test_engage_saves_meteor_for_a_credible_opening() -> void:
	var arena := _arena()
	var p := _bot(arena, Vector2.ZERO, "wizard")
	var foe := _player(arena, Vector2(300, 0), "knight")
	p.ult_charge = p.hero.ult_cost
	p.cooldowns[0] = 2.0
	p.cooldowns[1] = 2.0
	foe.velocity = Vector2.DOWN * foe.speed
	foe.hp = 16
	_engage(p, foe)
	assert_false(p.ai.holding(), "low target health does not make a telegraphed Meteor reliable")
	foe.velocity = Vector2.ZERO
	foe._rooted_left = 2.0
	_engage(p, foe)
	assert_eq(p.ai.held, [false, false, true], "spend it when the target will still be in the impact area")

func test_engage_checks_the_aimed_target_is_inside_tide_reach() -> void:
	var arena := _arena()
	var p := _bot(arena, Vector2.ZERO, "tidecaller")
	p.hp = 15
	p.ult_charge = p.hero.ult_cost
	var far := _player(arena, Vector2(1200, 0), "knight")
	_player(arena, Vector2(0, 100), "ranger")
	_engage(p, far)
	assert_false(p.ai.holding(), "a nearby bystander does not make an out-of-range shot worth casting")
