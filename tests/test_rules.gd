@tool
extends McpTestSuite
## Logic tests for the slot-machine rules and the tension clock (pure data, no scene).

func suite_name() -> String:
	return "rules"

func test_rules_stack_multiplicatively_and_reset() -> void:
	var r := RuleSet.new()
	r.apply("adrenaline")
	r.apply("adrenaline")
	assert_true(absf(r.speed - 1.5625) < 0.0001, "1.25 x 1.25")
	assert_eq(r.active.size(), 2)
	r.reset()
	assert_eq(r.speed, 1.0)
	assert_eq(r.active.size(), 0)

func test_glass_cannon_trades_hp_for_damage() -> void:
	var r := RuleSet.new()
	r.apply("glass_cannon")
	assert_gt(r.damage, 1.0)
	assert_true(r.hp < 1.0)

func test_every_rule_changes_something() -> void:
	for id: String in RuleSet.RULES:
		var r := RuleSet.new()
		r.apply(id)
		assert_true(r.speed != 1.0 or r.damage != 1.0 or r.hp != 1.0 or r.attack_rate != 1.0, id)

func test_apply_emits_changed() -> void:
	var r := RuleSet.new()
	var hits := [0]
	r.changed.connect(func() -> void: hits[0] += 1)
	r.apply("brute")
	r.reset()
	assert_eq(hits[0], 2)

func test_roll_never_repeats_the_last_rule() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var seen := {}
	for i in 200:
		var id := RuleSet.roll(rng, "brute")
		assert_ne(id, "brute")
		seen[id] = true
	assert_eq(seen.size(), RuleSet.RULES.size() - 1, "every other rule can come up")

func test_tension_levels_up_once_per_level_time() -> void:
	var t := Tension.new()
	track(t)
	var levels: Array[int] = []
	t.level_reached.connect(func(lv: int) -> void: levels.append(lv))
	t.advance(Tension.LEVEL_TIME - 1.0)
	assert_eq(levels.size(), 0)
	t.advance(1.0)
	assert_eq(levels, [1] as Array[int])
	t.advance(Tension.LEVEL_TIME * 2.0)   # a long gap crosses two levels
	assert_eq(levels, [1, 2, 3] as Array[int])
	assert_eq(t.level, 3)

func test_tension_progress_and_skip() -> void:
	var t := Tension.new()
	track(t)
	t.advance(Tension.LEVEL_TIME * 0.25)
	assert_true(absf(t.progress() - 0.25) < 0.001)
	t.skip_level()
	assert_eq(t.level, 1)
	assert_true(t.progress() < 0.001, "skipping lands exactly on the new level")
