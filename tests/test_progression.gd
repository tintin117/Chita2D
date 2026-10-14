extends McpTestSuite
## Logic tests for XP / levels / skill ranks / items / the stats Player derives from them.

func suite_name() -> String:
	return "progression"

func _knight() -> Player:
	var p := Player.new()
	track(p)
	p.hero = Hero.by_id("knight")
	p.init_loadout()
	return p

func test_xp_curve_and_multi_level() -> void:
	var pr := Progression.new()
	var seen: Array[int] = []
	pr.leveled_up.connect(func(lv: int) -> void: seen.append(lv))
	assert_eq(pr.xp_to_next(), 20)
	pr.add_xp(20 + 53)  # level 1 -> 2 costs 20, 2 -> 3 costs 53
	assert_eq(pr.level, 3)
	assert_eq(pr.xp, 0)
	assert_eq(pr.skill_points, 2)
	assert_eq(seen, [3] as Array[int], "one signal carrying the final level")

func test_level_cap_stops_xp() -> void:
	var pr := Progression.new()
	pr.add_xp(1_000_000)
	assert_eq(pr.level, Progression.LEVEL_CAP)
	assert_eq(pr.xp, 0)
	assert_eq(pr.xp_to_next(), 0)
	assert_eq(pr.skill_points, Progression.LEVEL_CAP - 1)

func test_xp_for_kinds() -> void:
	assert_gt(Progression.xp_for("boss"), Progression.xp_for("lancer"))
	assert_gt(Progression.xp_for("nothing"), 0, "unknown kinds still give a little")

func test_rank_up_spends_points_and_respects_cap() -> void:
	var pr := Progression.new()
	assert_false(pr.rank_up(0), "no points yet")
	pr.add_xp(1_000_000)
	for i in Progression.RANK_CAP + 3:
		pr.rank_up(0)
	assert_eq(pr.ranks[0], Progression.RANK_CAP)
	assert_eq(pr.skill_points, Progression.LEVEL_CAP - 1 - (Progression.RANK_CAP - 1))
	assert_gt(pr.skill_damage_mult(0), 1.0)
	assert_true(pr.skill_cooldown_mult(0) < 1.0)

func test_grant_reward() -> void:
	var pr := Progression.new()
	pr.grant_reward("power")
	assert_eq(pr.power_stacks, 1)
	assert_eq(pr.hp_bonus(), Progression.HP_PER_POWER)
	pr.grant_reward("xp")
	assert_eq(pr.level, 2, "60 xp pays the 20 for level 2; the remaining 40 is short of 53")
	assert_eq(pr.xp, 40)

func test_level_scales_player_stats_and_spells() -> void:
	var p := _knight()
	var base_dmg: int = p.spells[0].damage
	var base_hp := p.max_hp
	assert_eq(base_hp, 130)
	p.prog.add_xp(1_000_000)
	assert_eq(p.max_hp, 130 + 9 * Progression.HP_PER_LEVEL)
	assert_gt(p.spells[0].damage, base_dmg)
	assert_gt(p.speed, 255.0)
	assert_eq(p.hp, p.max_hp, "level-up heals to full")

func test_skill_rank_scales_only_that_slot() -> void:
	var p := _knight()
	p.prog.skill_points = 1
	var d0: int = p.spells[0].damage
	var d1: int = p.spells[1].damage
	p.prog.rank_up(1)
	assert_eq(p.spells[0].damage, d0)
	assert_gt(p.spells[1].damage, d1)

func test_catalog_and_roll() -> void:
	assert_eq(Item.all().size(), 9)
	var ids := {}
	for it in Item.all():
		ids[it.id] = true
		assert_false(it.describe().is_empty(), it.id)
	assert_eq(ids.size(), 9, "unique ids")
	assert_eq(Item.by_id("ember_blade").rarity, 1)
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 7
	b.seed = 7
	for i in 20:
		assert_eq(Item.roll(a, 2), Item.roll(b, 2), "same seed, same drops")

func test_equip_applies_mods_and_only_upgrades() -> void:
	var p := _knight()
	var d: int = p.spells[0].damage
	assert_true(p.try_equip(Item.by_id("iron_blade")))
	assert_gt(p.spells[0].damage, d)
	assert_false(p.try_equip(Item.by_id("iron_blade")), "same rarity is not an upgrade")
	assert_true(p.try_equip(Item.by_id("sunfire_edge")))
	assert_eq(p.equipment["weapon"].id, "sunfire_edge")
	var hp := p.max_hp
	assert_true(p.try_equip(Item.by_id("dragon_plate")))
	assert_eq(p.max_hp, hp + 70)
	assert_eq(p.hp, p.max_hp, "gained max HP is healed")

func test_cooldown_reduction_is_capped() -> void:
	var p := _knight()
	p.try_equip(Item.by_id("phoenix_idol"))
	p.try_equip(Item.by_id("sunfire_edge"))
	assert_true(p.cooldown_mult >= 0.5)
	assert_true(p.cooldown_mult < 1.0)
