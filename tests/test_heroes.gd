extends McpTestSuite
## Logic tests for the hero roster.

func suite_name() -> String:
	return "heroes"

func test_four_heroes_with_distinct_roles() -> void:
	var heroes := Hero.all()
	assert_eq(heroes.size(), 4)
	var ids := heroes.map(func(h: Hero) -> String: return h.id)
	for id in ["knight", "rogue", "wizard", "ranger"]:
		assert_true(id in ids, id)
	assert_true(Hero.by_id("knight").attack_range < Hero.by_id("wizard").attack_range)
	assert_true(Hero.by_id("wizard").attack_range < Hero.by_id("ranger").attack_range)
	assert_true(Hero.by_id("rogue").attack_range < Hero.by_id("knight").attack_range, "rogue has the shortest reach")
	for h in heroes:
		assert_true(Hero.by_id("rogue").speed >= h.speed, "rogue is fastest")
		assert_true(Hero.by_id("rogue").max_hp <= h.max_hp, "rogue is the most fragile")
	var descs := {}
	for h in heroes:
		assert_gt(h.description.length(), 20, h.id + " has a card description")
		assert_gt(h.rmb_text.length(), 10, h.id + " describes its right click")
		descs[h.description] = true
	assert_eq(descs.size(), 4, "every card reads differently")

func test_hero_basic_follows_attack_range() -> void:
	for h in Hero.all():
		var s := h.make_basic() as HeroBasic
		assert_true(s.cooldown >= 0.3, h.id + " basic is a deliberate, not spammy, pace")
		if h.attack_type == "melee":
			assert_eq(s.mode, "arc")
			assert_eq(s.radius, h.attack_range)
		else:
			assert_eq(s.mode, "bolt")
			assert_true(absf(s.bolt_life * s.bolt_speed - h.attack_range) < 0.01, h.id + " bolt travels attack_range")

func test_player_takes_hero_stats() -> void:
	var p := Player.new()
	track(p)
	p.hero = Hero.by_id("knight")
	p.max_hp = p.hero.max_hp
	assert_eq(p.max_hp, 130)
	assert_eq(Hero.by_id("nobody").id, "wizard", "unknown ids fall back to the Wizard")

func test_kit_is_exactly_basic_and_one_skill() -> void:
	var seen := {}
	for h in Hero.all():
		var kit := h.make_kit()
		assert_eq(kit.size(), 2, h.id + " has LMB + RMB only")
		assert_true(kit[0] is HeroBasic)
		seen[kit[1].display_name] = true
		assert_true(kit[1].cooldown >= 5.0 and kit[1].cooldown <= 8.0, h.id + " skill cooldown 5-8s")
	assert_eq(seen.size(), 4, "four different right-click skills")
	assert_eq(Player.SLOTS.size(), 2)
	assert_eq(Progression.SLOTS, 2)

func test_rogue_backstabs_and_wizard_keeps_ember_field() -> void:
	var rb := Hero.by_id("rogue").make_basic() as HeroBasic
	assert_gt(rb.back_mult, 1.0)
	assert_eq(Hero.by_id("rogue").make_kit()[1].display_name, "Shadow Step")
	assert_eq(Hero.by_id("wizard").make_kit()[1].display_name, "Ember Field")
	assert_eq(Hero.by_id("knight").make_kit()[1].display_name, "Shield Charge")
	assert_eq(Hero.by_id("ranger").make_kit()[1].display_name, "Snipe Shot")

func test_from_behind() -> void:
	var v := Player.new()
	track(v)
	v.aim_dir = Vector2.RIGHT
	v.position = Vector2.ZERO
	assert_true(HeroBasic.Sweep.from_behind(v, Vector2(-60, 0)), "attacker behind a right-facing victim")
	assert_false(HeroBasic.Sweep.from_behind(v, Vector2(60, 0)), "attacker in front")

func test_shadow_step_lands_behind_the_target() -> void:
	var v := Player.new()
	track(v)
	v.aim_dir = Vector2.LEFT
	v.position = Vector2(300, 0)
	var foes: Array[Node2D] = [v]
	var d := ShadowStep.destination(Vector2.ZERO, Vector2(300, 10), foes)
	assert_gt(d.x, 300.0, "past a left-facing target = behind it")
	var hop := ShadowStep.destination(Vector2.ZERO, Vector2(900, 0), foes)
	assert_true(absf(hop.length() - ShadowStep.HOP) < 0.01, "no target near the cursor: a short hop")
