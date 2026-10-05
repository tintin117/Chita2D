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

func test_each_hero_has_its_own_right_click_and_special() -> void:
	var seen_rmb := {}
	var seen_special := {}
	for h in Hero.all():
		var kit := h.make_kit()
		assert_eq(kit.size(), 4)
		seen_rmb[kit[1].display_name] = true
		seen_special[kit[3].display_name] = true
		assert_gt(kit[3].charge_cost, 0.0, h.id + " special spends the signature meter")
	assert_eq(seen_rmb.size(), 3, "three different right-click skills")
	assert_eq(seen_special.size(), 3, "three different specials")

func test_wizard_keeps_blast_and_meteor_barrage() -> void:
	var kit := Hero.by_id("wizard").make_kit()
	assert_eq(kit[1].display_name, "Blast")
	assert_eq(kit[3].display_name, "Meteor Barrage")
