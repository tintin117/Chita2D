extends McpTestSuite
## Logic tests for the hero roster.

func suite_name() -> String:
	return "heroes"

func test_three_heroes_cover_melee_mid_and_long() -> void:
	var heroes := Hero.all()
	assert_eq(heroes.size(), 3)
	assert_eq(heroes[0].attack_type, "melee")
	assert_eq(heroes[1].attack_type, "ranged")
	assert_eq(heroes[2].attack_type, "ranged")
	assert_true(heroes[0].attack_range < heroes[1].attack_range)
	assert_true(heroes[1].attack_range < heroes[2].attack_range)

func test_hero_basic_follows_attack_range() -> void:
	for h in Hero.all():
		var s := h.make_basic() as HeroBasic
		assert_eq(s.cooldown, 0.28, h.id + " keeps the fast first-version pace")
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
