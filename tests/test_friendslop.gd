@tool
extends McpTestSuite
## Friendslop: mode config, the Bonker, weapon pickups by tier, catch-up and weapon expiry (no networking).

const PvpMatch := preload("res://scenes/pvp_match.gd")

func suite_name() -> String:
	return "friendslop"

func test_mode_config() -> void:
	assert_true(GameMode.valid("classic") and GameMode.valid("friendslop"))
	assert_false(GameMode.valid("nope"))
	assert_eq(GameMode.cfg("nope").name, "Classic", "unknown modes fall back to Classic")
	assert_eq(GameMode.next("classic"), "crown")
	assert_eq(GameMode.next("crown"), "friendslop")
	assert_eq(GameMode.next("friendslop"), "classic")
	assert_true(GameMode.is_crown("crown"))
	assert_false(GameMode.is_crown("classic") or GameMode.is_crown("friendslop"))
	var c := GameMode.cfg("classic")
	var f := GameMode.cfg("friendslop")
	assert_true(c.hero_pick and not f.hero_pick, "Friendslop skips the hero pick")
	assert_eq(f.hero, "bonker")
	assert_true(f.pickup_every < c.pickup_every, "drops come faster")
	assert_gt(f.max_pickups, c.max_pickups, "more drops at once")
	assert_true(f.spawn_clear < c.spawn_clear, "drops spread beyond the centre")
	assert_eq(c.pickup_every, PvpMatch.PICKUP_EVERY, "Classic's numbers match the match constants")
	assert_eq(c.max_pickups, PvpMatch.MAX_PICKUPS)
	assert_eq(f.drop_after_deaths, 0, "Friendslop drops from the first second")
	assert_true(f.channel.is_empty() and f.pickup_life == 0.0, "Friendslop: walk over it, it never despawns")
	assert_false(f.events, "Friendslop has its slot machine, no match event")
	assert_eq(c.kill_limit, Net.DEFAULT_SETTINGS.kill_limit, "Classic's limit matches the lobby default")

func test_bonker_is_modest_and_hidden_from_the_pick() -> void:
	var b := Hero.by_id("bonker")
	assert_eq(b.id, "bonker")
	assert_eq(b.attack_type, "melee")
	for h in Hero.all():
		assert_ne(h.id, "bonker", "never offered on the pick screen")
		assert_true(b.basic_damage <= Hero.by_id("knight").basic_damage, "bonker's basic is no stronger than the knight's")
		assert_true(b.max_hp <= Hero.by_id("knight").max_hp, "nor tankier")
	var kit := b.make_kit()
	assert_eq(kit.size(), 2)
	assert_true(kit[0] is HeroBasic and kit[1] is Hook)
	assert_true(kit[1].damage < 8, "the hook is for catching, not damage")

func test_weapon_tables_agree() -> void:
	var ids := FsWeapon.ids()
	assert_eq(ids.size(), PvpPickup.FS_WEAPONS.size())
	for id: String in ids:
		assert_true(id in PvpPickup.FS_WEAPONS, id)
		for dict in [PvpPickup.COLORS, PvpPickup.LABELS, PvpPickup.ICONS, PvpPickup.KIND_TIER, PvpPickup.FS_WEIGHTS]:
			assert_true(dict.has(id), "%s present in pickup tables" % id)
		var w := FsWeapon.make(id)
		assert_eq(w.slot, 0, "%s goes on LMB: RMB is always the Hook" % id)
		assert_gt(w.uses, 0)
		assert_true(w.time >= 10.0 and w.time <= 15.0, "%s lasts ~10-15 s" % id)
	assert_true(ids.size() >= 6 and ids.size() <= 9)

func test_tier_strength_ordering() -> void:
	var by_tier := [[], [], []]
	for id: String in FsWeapon.ids():
		by_tier[PvpPickup.tier_of(id)].append(id)
	for t in 3:
		assert_gt(by_tier[t].size(), 0, "tier %d has weapons" % t)
	for id: String in by_tier[0]:
		assert_true(FsWeapon.make(id).damage < 20, "common weapons are light")
	for id: String in by_tier[2]:
		assert_true(id in ["rocket", "meteor", "gatling"])
	assert_true(FsWeapon.make("rocket").damage > FsWeapon.make("hammer").damage, "epic hits harder than rare")

func test_roll_fs_hits_every_kind_and_respects_tiers() -> void:
	var seen := {}
	var tiers := [0, 0, 0]
	var n := 4000
	for i in n:
		var k := PvpPickup.roll_fs((i + 0.5) / n)
		seen[k] = seen.get(k, 0) + 1
		tiers[PvpPickup.tier_of(k)] += 1
	for k: String in PvpPickup.FS_WEIGHTS:
		assert_true(seen.has(k), "%s can drop" % k)
	assert_true(seen.has("giant") and seen.has("chicken") and seen.has("bomb") and seen.has("mystery"), "chaos pickups stay in rotation")
	assert_gt(tiers[0], tiers[2] * 2, "commons far outnumber epics")
	assert_true(float(tiers[2]) / n > 0.08 and float(tiers[2]) / n < 0.2, "epics are rare, not absent")

func test_catchup_boost_shifts_tiers_up() -> void:
	var base := 0
	var boosted := 0
	var n := 4000
	for i in n:
		if PvpPickup.tier_of(PvpPickup.roll_fs((i + 0.5) / n)) == PvpPickup.Tier.EPIC:
			base += 1
		if PvpPickup.tier_of(PvpPickup.roll_fs((i + 0.5) / n, 1.0)) == PvpPickup.Tier.EPIC:
			boosted += 1
	assert_gt(boosted, base, "a trailing player sees more epics")
	assert_true(float(boosted) / base < 2.6, "but it is a nudge, not a guarantee")

func test_catchup_picks_the_trailer() -> void:
	assert_eq(PvpMatch.catchup({1: 5}).peer, 0, "alone: nobody trails")
	assert_eq(PvpMatch.catchup({1: 3, 2: 3}).boost, 0.0, "tied: no bias")
	var c := PvpMatch.catchup({1: 8, 2: 2, 3: 5})
	assert_eq(c.peer, 2)
	assert_eq(c.boost, 1.0)
	c = PvpMatch.catchup({1: 4, 2: 3})
	assert_eq(c.peer, 2)
	assert_true(c.boost > 0.0 and c.boost < 0.5, "one kill behind = tiny bias")

func test_mystery_box_can_hold_a_weapon_only_in_friendslop() -> void:
	var classic := {}
	var fs := {}
	for i in 200:
		classic[PvpPickup.mystery_outcome(i / 200.0)] = true
		fs[PvpPickup.mystery_outcome(i / 200.0, true)] = true
	for id in PvpPickup.FS_WEAPONS:
		assert_false(classic.has(id))
		assert_true(fs.has(id))

func test_drop_positions_spread_with_friendslop_clearances() -> void:
	var m := WorldMap.new()
	track(m)
	m.generate_arena(false)
	var f := GameMode.cfg("friendslop")
	var taken: Array[Vector2] = []
	var far := 0.0
	for i in 40:
		var p := PvpMatch.pick_pickup_pos(m, taken, f.spawn_clear, f.apart)
		assert_true(m.is_reachable(p))
		for s in m.spawn_points:
			assert_gt(p.distance_to(s), f.spawn_clear - 1.0)
		far = maxf(far, p.distance_to(m.spawn_point))
		taken = [p]
	var near_pos := PvpMatch.pick_pickup_pos_near(m, [], Vector2.ZERO, f.spawn_clear, f.apart)
	assert_true(m.is_reachable(near_pos))

func _player(hero := "bonker") -> Player:
	var p := Player.new()
	track(p)
	p.hero = Hero.by_id(hero)
	p.init_loadout()
	return p

func test_weapon_equip_slot_and_replace() -> void:
	var p := _player()
	assert_false(p.weapon_active(0))
	assert_true(p.spell_in(0) is HeroBasic, "no weapon: the hero's own basic")
	p.apply_pickup("hammer")
	assert_true(p.weapon_active(0) and not p.weapon_active(1))
	assert_eq(p.spell_in(0).id, "hammer")
	p.apply_pickup("rocket")   # every weapon is LMB: replaces the hammer, the Hook stays
	assert_eq(p.spell_in(0).id, "rocket")
	assert_false(p.weapon_active(1))
	assert_true(p.spell_in(1) is Hook, "RMB is always the Hook")

func test_weapon_expires_by_uses_and_time_and_death() -> void:
	var p := _player()
	p.apply_pickup("rocket")
	var w: FsWeapon = p.weapons[0]
	w.uses = 1
	w.uses -= 1
	assert_false(p.weapon_active(0), "no uses left")
	assert_true(p.spell_in(0) is HeroBasic, "back to the Bonk")
	p.apply_pickup("slingshot")
	assert_true(p.weapon_active(0))
	p.weapons[0].until = Time.get_ticks_msec() / 1000.0 - 0.1
	assert_false(p.weapon_active(0), "time ran out")
	p.apply_pickup("hammer")
	p.clear_weapons()   # what dying does
	assert_false(p.weapon_active(0) or p.weapon_active(1), "weapons are lost on death")

func test_loot_tables_agree() -> void:
	for k: String in FsLoot.passive_kinds() + FsLoot.ult_kinds():
		for dict in [PvpPickup.COLORS, PvpPickup.LABELS, PvpPickup.ICONS, PvpPickup.KIND_TIER, PvpPickup.FS_WEIGHTS]:
			assert_true(dict.has(k), "%s present in pickup tables" % k)
	for k: String in PvpPickup.FS_WEIGHTS:
		if k.begins_with("pas_"):
			assert_true(FsLoot.is_passive(k), k)
		if k.begins_with("ult_"):
			assert_true(FsLoot.is_ult(k), k)
			assert_eq(PvpPickup.tier_of(k), PvpPickup.Tier.EPIC)
	for uid: String in FsLoot.ULTS:
		assert_ne(FsLoot.ult_text(FsLoot.ULTS[uid]), "", uid + " has a text from its hero")
	assert_false(FsLoot.is_ult("ult"), "the classic Ult spark is not an ult drop")

func test_bonker_starts_with_empty_passive_and_ult() -> void:
	var p := _player()
	assert_ne(p.hero, Hero.bonker(), "each Bonker writes drops onto its own Hero copy")
	assert_eq(p.hero.passive_name, "")
	assert_eq(p.spells.size(), 2)
	assert_false(p.ult_ready())
	p.charge_ult(999.0)
	assert_false(p.ult_ready(), "no ult to charge")

func test_passive_drop_applies_swaps_and_clears() -> void:
	var p := _player()
	var other := _player()
	p.apply_pickup("pas_vampire")
	assert_eq(p.hero.passive_name, "Vampire")
	assert_eq(p.hero.lifesteal, 0.25)
	assert_eq(other.hero.lifesteal, 0.0, "only the taker gets it")
	assert_eq(Hero.bonker().lifesteal, 0.0, "the shared Bonker is untouched")
	var dmg := p.spells[0].damage
	p.apply_pickup("pas_glass")   # a new passive swaps the old one out
	assert_eq(p.hero.passive_name, "Glass Cannon")
	assert_eq(p.hero.lifesteal, 0.0)
	assert_gt(p.spells[0].damage, dmg, "Glass Cannon hits harder")
	p.clear_passive()   # what dying does
	assert_eq(p.hero.passive_name, "")
	assert_eq(p.hero.damage_dealt, 1.0)
	assert_eq(p.spells[0].damage, dmg)

func test_stalk_drop_gives_the_bonk_a_backstab() -> void:
	var p := _player()
	assert_eq(p.spells[0].back_mult, 1.0)
	p.apply_pickup("pas_stalk")
	assert_true(p.hero.stalk)
	assert_eq(p.spells[0].back_mult, 1.8, "the Bonk backstabs now")
	p.clear_passive()
	assert_false(p.hero.stalk)
	assert_eq(p.spells[0].back_mult, 1.0, "and stops on death")

func test_passive_clear_never_touches_a_picked_hero() -> void:
	var p := _player("knight")
	p.clear_passive()
	assert_eq(p.hero.passive_name, "Bulwark")

func test_ult_drop_is_ready_one_use_and_never_charges() -> void:
	var p := _player()
	p.apply_pickup("ult_meteor")
	assert_eq(p.spells.size(), 3)
	assert_true(p.spells[Player.ULT_SLOT] is Meteor)
	assert_true(p.ult_ready(), "ready right away")
	assert_false(p.ult_slot_empty())
	p.ult_charge = 0.0   # what the cast does
	p.charge_ult(999.0)
	assert_false(p.ult_ready(), "a drop ult never charges back")
	assert_true(p.ult_slot_empty())
	p.apply_pickup("ult_angel")   # the next ult drop fills it again
	assert_true(p.spells[Player.ULT_SLOT] is GuardianAngel and p.ult_ready())
	assert_eq(p.spells.size(), 3)
	p.clear_drop_ult()   # what dying does
	assert_true(p.ult_slot_empty())

func test_weapon_time_left_matches_def() -> void:
	var p := _player()
	p.apply_pickup("frost_gun")
	var w: FsWeapon = p.weapons[0]
	assert_true(w.seconds_left() > w.time - 1.0 and w.seconds_left() <= w.time)
