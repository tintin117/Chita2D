extends McpTestSuite
## Logic tests for the hero roster.

func suite_name() -> String:
	return "heroes"

func test_four_heroes_with_distinct_roles() -> void:
	var heroes := Hero.all()
	assert_eq(heroes.size(), 12, "4 core heroes + Paladin, Shade, Sorcerer, Scout + Tidecaller, Rampager, Demonbound, Chaos Lord")
	var ids := heroes.map(func(h: Hero) -> String: return h.id)
	for id in ["knight", "rogue", "wizard", "ranger"]:
		assert_true(id in ids, id)
	assert_true(Hero.by_id("knight").attack_range < Hero.by_id("wizard").attack_range)
	assert_true(Hero.by_id("wizard").attack_range < Hero.by_id("ranger").attack_range)
	assert_true(Hero.by_id("rogue").attack_range < Hero.by_id("knight").attack_range, "rogue has the shortest reach")
	for h in heroes:
		assert_true(Hero.by_id("rogue").speed >= h.speed, "rogue is fastest")
		assert_true(Hero.by_id("scout").max_hp <= h.max_hp, "the Glass Cannon is the most fragile")
	var descs := {}
	for h in heroes:
		assert_gt(h.description.length(), 20, h.id + " has a card description")
		assert_gt(h.rmb_text.length(), 10, h.id + " describes its right click")
		descs[h.description] = true
	assert_eq(descs.size(), 12, "every card reads differently")

func test_hero_basic_follows_attack_range() -> void:
	for h in Hero.all():
		assert_true(h.make_basic().cooldown >= 0.3, h.id + " basic is a deliberate, not spammy, pace")
		if h.basic_spell != "":
			continue   # its own spell (Chain Lightning), not a HeroBasic
		var s := h.make_basic() as HeroBasic
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
	assert_eq(p.max_hp, 140)
	assert_eq(Hero.by_id("nobody").id, "wizard", "unknown ids fall back to the Wizard")

func test_kit_is_basic_skill_and_maybe_an_ult() -> void:
	var seen := {}
	for h in Hero.all():
		var kit := h.make_kit()
		assert_eq(kit.size(), 3 if h.ult_skill != "" else 2, h.id + " has LMB + RMB (+ F when it has an ult)")
		assert_true(kit[0] is HeroBasic or h.basic_spell != "", h.id + " basic")
		seen[kit[1].display_name] = true
		if h.rmb_cd > 0.0:
			assert_eq(kit[1].cooldown, h.rmb_cd, h.id + " configured signature cooldown")
		else:
			assert_true(kit[1].cooldown >= 5.0 and kit[1].cooldown <= 9.0, h.id + " default signature cooldown 5-9s")
	assert_eq(seen.size(), Hero.all().size(), "every hero has its own right click")
	assert_eq(Player.SLOTS.size(), 3)
	assert_eq(Progression.SLOTS, 2, "the ult has no skill ranks")

func test_rogue_kit_has_backstab_and_shadow_dance() -> void:
	var h := Hero.by_id("rogue")
	assert_eq(h.passive_name, "Stalk")
	var kit := h.make_kit()
	assert_true(kit[Player.ULT_SLOT] is SmokeScreen, "Smoke Screen replaced Shadow Dance")

func test_shadow_dance_plan_spreads_strikes() -> void:
	assert_eq(ShadowDance.plan([]), [])
	assert_eq(ShadowDance.plan(["a"]), ["a", "a"], "a lone foe takes MAX_PER_FOE strikes, no more")
	assert_eq(ShadowDance.plan(["a", "b"]), ["a", "b", "a"])
	assert_eq(ShadowDance.plan(["a", "b", "c", "d"]), ["a", "b", "c"])

func test_ult_charges_from_damage_and_caps() -> void:
	var p := Player.new()
	track(p)
	p.hero = Hero.by_id("rogue")
	p.init_loadout()
	assert_false(p.ult_ready())
	p.charge_ult(p.hero.ult_cost * 0.5)
	assert_false(p.ult_ready())
	assert_true(absf(p.ult_fraction() - 0.5) < 0.001)
	p.charge_ult(p.hero.ult_cost)
	assert_true(p.ult_ready())
	assert_eq(p.ult_charge, p.hero.ult_cost, "capped at full")
	assert_false(p.weapon_active(Player.ULT_SLOT), "the ult slot never holds a Friendslop weapon")

func test_hero_without_ult_never_charges() -> void:
	var p := Player.new()
	track(p)
	p.hero = Hero.by_id("wizard")
	p.init_loadout()
	p.charge_ult(999.0)
	assert_false(p.ult_ready())
	assert_eq(p.ult_fraction(), 0.0)

func test_rogue_backstabs_and_wizard_keeps_ember_field() -> void:
	var rb := Hero.by_id("rogue").make_basic() as HeroBasic
	assert_gt(rb.back_mult, 1.0)
	assert_eq(Hero.by_id("rogue").make_kit()[1].display_name, "Shadow Rush")
	assert_eq(Hero.by_id("wizard").make_kit()[1].display_name, "Ember Field")
	assert_eq(Hero.by_id("knight").make_kit()[1].display_name, "Rebound Shield")
	assert_eq(Hero.by_id("ranger").make_kit()[1].display_name, "Power Arrow")

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

# --- Rogue: Shadow Rush + Frozen

func _foe_at(pos: Vector2, facing: Vector2) -> Player:
	var p := Player.new()
	track(p)
	p.position = pos
	p.aim_dir = facing
	return p

func test_rogue_kit_is_rush_backstab_dance() -> void:
	var h := Hero.by_id("rogue")
	var kit := h.make_kit()
	assert_eq(kit.size(), 3, "basic, rush, ult (the passive has no slot)")
	assert_true(kit[1] is ShadowRush)
	assert_true(kit[2] is SmokeScreen)
	assert_gt(h.back_mult, 1.0, "backstab passive")

func test_shadow_rush_catches_only_the_line() -> void:
	var on_line := _foe_at(Vector2(200, 10), Vector2.LEFT)
	var off_line := _foe_at(Vector2(200, 160), Vector2.LEFT)
	var behind_start := _foe_at(Vector2(-150, 0), Vector2.LEFT)
	var foes: Array[Node2D] = [off_line, on_line, behind_start]
	var got := ShadowRush.hits(Vector2.ZERO, Vector2(ShadowRush.RANGE, 0), foes)
	assert_eq(got.size(), 1)
	assert_eq(got[0], on_line)

func test_shadow_rush_lands_past_a_foe_at_the_tip() -> void:
	var none: Array[Node2D] = []
	assert_eq(ShadowRush.length_along(Vector2.ZERO, Vector2.RIGHT, none), ShadowRush.RANGE, "nobody: the plain blink")
	var tip := _foe_at(Vector2(ShadowRush.RANGE - 10.0, 0), Vector2.LEFT)
	var foes: Array[Node2D] = [tip]
	var reach := ShadowRush.length_along(Vector2.ZERO, Vector2.RIGHT, foes)
	assert_gt(reach, tip.position.x + ShadowRush.BEHIND - 1.0, "carries on past the foe to its back")
	assert_true(reach <= ShadowRush.RANGE + ShadowRush.BEHIND)
	# a foe facing the Rogue (LEFT, the Rogue comes from the left) has the landing spot at its back
	assert_true(HeroBasic.Sweep.from_behind(tip, Vector2(reach, 0)), "rushing through a foe that faces you = behind it")

func test_freeze_holds_like_a_stun_and_never_chains() -> void:
	var p := _foe_at(Vector2.ZERO, Vector2.UP)
	p.freeze(0.8)
	assert_true(p.frozen())
	assert_eq(p._frozen_aim, Vector2.UP, "facing locked where it was")
	p.stun(1.0)
	assert_false(p.stunned(), "no stun on top of a freeze")
	p._tick_timers(0.9)
	assert_false(p.frozen())
	p.stun(1.0)
	assert_false(p.stunned(), "the thaw starts the same immunity as a stun")
	p._tick_timers(Player.STUN_IMMUNITY)
	p.stun(0.5)
	assert_true(p.stunned())
	p.freeze(0.8)
	assert_false(p.frozen(), "no freeze on top of a stun")

# --- Knight: Bulwark + Judgement

func test_knight_kit_is_charge_bulwark_judgement() -> void:
	var h := Hero.by_id("knight")
	assert_eq(h.passive_name, "Bulwark")
	assert_true(h.front_mult < 1.0)
	var kit := h.make_kit()
	assert_eq(kit.size(), 3)
	assert_true(kit[1] is ReboundShield)
	assert_true(kit[Player.ULT_SLOT] is Judgement)

func test_bulwark_reads_the_front() -> void:
	var k := _foe_at(Vector2.ZERO, Vector2.RIGHT)
	assert_true(k.faces(Vector2(100, 20)), "a hit from where he looks: blocked")
	assert_false(k.faces(Vector2(-100, 0)), "from behind: full damage (and the Rogue backstab)")
	assert_false(k.faces(Vector2(0, 100)), "from the side: full damage")

func test_judgement_lands_in_range_and_never_in_the_water() -> void:
	var dry := Callable()
	var far := Judgement.landing(Vector2.ZERO, Vector2(1000, 0), dry)
	assert_true(absf(far.length() - Judgement.RANGE) < 0.01, "capped at RANGE")
	var near := Judgement.landing(Vector2.ZERO, Vector2(200, 0), dry)
	assert_eq(near, Vector2(200, 0))
	var sea := func(p: Vector2) -> bool: return p.x > 250.0
	var shore := Judgement.landing(Vector2.ZERO, Vector2(400, 0), sea)
	assert_true(shore.x <= 250.0 + 0.01, "backed off the water toward the start")
	assert_gt(shore.x, 200.0)

func test_judgement_slam_catches_the_projected_area() -> void:
	var east := _foe_at(Vector2(Judgement.HIT_RADIUS, 0), Vector2.LEFT)
	var south := _foe_at(Vector2(0, Judgement.HIT_RADIUS * 0.5), Vector2.UP)
	var north_out := _foe_at(Vector2(0, -Judgement.HIT_RADIUS * 0.5 - 1), Vector2.DOWN)
	var west_out := _foe_at(Vector2(-Judgement.HIT_RADIUS - 1, 0), Vector2.RIGHT)
	var foes: Array[Node2D] = [east, south, north_out, west_out]
	assert_eq(Judgement.caught(Vector2.ZERO, foes), [east, south])

func test_judgement_holds_then_reaches_ground_on_impact() -> void:
	var hold_mid := Judgement.RISE + Judgement.HOLD * 0.5
	var drop_mid := Judgement.DROP + Judgement.DESCENT * 0.5
	assert_eq(Judgement.height_at(hold_mid), Judgement.HEIGHT)
	assert_eq(Judgement.pose_at(hold_mid), 4)
	assert_gt(Judgement.height_at(drop_mid), 0.0)
	assert_gt(Judgement.pose_at(drop_mid), 4)
	assert_eq(Judgement.height_at(Judgement.LEAP), 0.0)
	assert_eq(Judgement.pose_at(Judgement.LEAP), 9)

# --- Mage: Ember Field (no stun) + Kindling + Meteor

func test_mage_kit_is_ember_kindling_meteor() -> void:
	var h := Hero.by_id("wizard")
	assert_eq(h.passive_name, "Kindling")
	assert_true(h.kindling)
	var kit := h.make_kit()
	assert_eq(kit.size(), 3)
	assert_true(kit[1] is EmberField)
	assert_true(kit[Player.ULT_SLOT] is Meteor)
	assert_true(EmberField.BURST_SLOW[0] < EmberField.SLOW, "the eruption slows harder than the smoulder (it replaced the stun)")

func test_meteor_lands_in_range_and_catches_the_circle() -> void:
	assert_true(absf(Meteor.spot(Vector2.ZERO, Vector2(2000, 0)).length() - Meteor.MAX_RANGE) < 0.01)
	assert_eq(Meteor.spot(Vector2.ZERO, Vector2(300, 0)), Vector2(300, 0))
	var inside := _foe_at(Vector2(100, 0), Vector2.LEFT)
	var outside := _foe_at(Vector2(Meteor.RADIUS + 60.0, 0), Vector2.LEFT)
	var foes: Array[Node2D] = [inside, outside]
	var got := Meteor.caught(Vector2.ZERO, foes)
	assert_eq(got.size(), 1)
	assert_eq(got[0], inside)

func test_meteor_launches_outward_hardest_in_the_middle() -> void:
	var mid := Meteor.launch(Vector2(10, 0))
	var rim := Meteor.launch(Vector2(Meteor.RADIUS, 0))
	assert_gt(mid.x, 0.0, "pushed away from the centre")
	assert_gt(mid.length(), rim.length(), "dead centre launches hardest")
	assert_true(absf(rim.length() - Meteor.SHOVE * Meteor.LAUNCH_EDGE) < 0.5)
	assert_true(Meteor.launch(Vector2.ZERO).length() > 0.0, "dead centre still goes somewhere")

# --- Ranger: Power Shot (hold and release) + Steady Aim + Arrow Rain

func _ranger() -> Player:
	var p := Player.new()
	track(p)
	p.hero = Hero.by_id("ranger")
	p.init_loadout()
	return p

func test_ranger_kit_is_power_shot_steady_aim_arrow_rain() -> void:
	var h := Hero.by_id("ranger")
	assert_eq(h.passive_name, "Steady Aim")
	assert_true(h.steady_aim)
	var kit := h.make_kit()
	assert_eq(kit.size(), 3)
	assert_true(kit[1] is PowerShot)
	assert_gt(kit[1].charge_time(), 0.0, "hold and release")
	assert_true(kit[Player.ULT_SLOT] is FocusFire, "Arrow Rain moved to the Scout; Focus Fire is the WR ult")
	assert_eq(kit[0].charge_time(), 0.0, "the basic is still press to fire")

func test_power_shot_grows_with_the_draw() -> void:
	assert_gt(PowerShot.reach_at(1.0), PowerShot.reach_at(0.2))
	assert_gt(PowerShot.speed_at(1.0), PowerShot.speed_at(0.2))
	assert_gt(PowerShot.damage_at(42, 1.0), PowerShot.damage_at(42, 0.2))
	assert_gt(PowerShot.shove_at(1.0), PowerShot.shove_at(0.2))
	assert_eq(PowerShot.pierce_at(0.99), 0, "only a full draw pierces")
	assert_gt(PowerShot.pierce_at(1.0), 0)
	assert_eq(PowerShot.damage_at(42, 1.0), 42)
	assert_gt(PowerShot.damage_at(42, 0.0), 0, "a tap still hurts a little")

func test_drawing_fills_and_steady_aim_doubles_it() -> void:
	var p := _ranger()
	p.velocity = Vector2.ZERO
	assert_eq(p.draw_rate(), Player.STEADY_RATE, "standing still: twice the rate")
	p.velocity = Vector2(200, 0)
	assert_eq(p.draw_rate(), 1.0, "moving: normal rate")
	var k := Player.new()
	track(k)
	k.hero = Hero.by_id("wizard")
	assert_eq(k.draw_rate(), 1.0, "no Steady Aim, no bonus")
	p._charge_slot = 1
	p.charge_show = 0.6
	p.cancel_charge()
	assert_eq(p._charge_slot, -1)
	assert_eq(p.charge_show, 0.0, "a dropped draw hides the line everywhere")

func test_charge_spell_is_found_only_on_the_ranger() -> void:
	assert_true(_ranger().charge_spell() is PowerShot)
	var k := Player.new()
	track(k)
	k.hero = Hero.by_id("knight")
	k.init_loadout()
	assert_eq(k.charge_spell(), null)

func test_arrow_rain_circle_and_volleys() -> void:
	assert_true(absf(ArrowRain.spot(Vector2.ZERO, Vector2(3000, 0)).length() - ArrowRain.MAX_RANGE) < 0.01)
	var inside := _foe_at(Vector2(50, 50), Vector2.LEFT)
	var outside := _foe_at(Vector2(ArrowRain.RADIUS + 80.0, 0), Vector2.LEFT)
	var foes: Array[Node2D] = [inside, outside]
	assert_eq(ArrowRain.caught(Vector2.ZERO, foes).size(), 1)
	assert_eq(ArrowRain.volleys(), 10, "3 s of rain, a volley every 0.3 s")

# --- Archetype basics

func test_four_basics_read_apart() -> void:
	var k := Hero.by_id("knight").make_basic() as HeroBasic
	var r := Hero.by_id("rogue").make_basic() as HeroBasic
	var m := Hero.by_id("wizard").make_basic() as HeroBasic
	var a := Hero.by_id("ranger").make_basic() as HeroBasic
	assert_true(k.combo and not r.combo and not m.combo and not a.combo, "only the Tank has a 3-hit finisher")
	assert_gt(k.arc_angle, r.arc_angle * 2.0, "Tank cleaves wide, Assassin stabs narrow")
	assert_gt(k.cooldown, r.cooldown, "Tank is slow and heavy, Assassin quick")
	assert_gt(k.windup, r.windup, "a heavy swing telegraphs longer")
	assert_gt(m.splash, 0.0, "Artillery throws an orb that bursts")
	assert_eq(a.splash, 0.0, "Marksman shoots a plain arrow")
	assert_gt(a.bolt_speed * a.bolt_life, m.bolt_speed * m.bolt_life, "Marksman out-ranges the Artillery")
	assert_ne(a.arrow_tex, "", "a real arrow sprite, not the spell bolt")
	for h in Hero.all():
		assert_eq(h.lunge, 0.0, h.id + " plants its feet: no auto-lunge")
		assert_ne(h.archetype, "", h.id + " has an archetype")

func test_mage_orb_lands_on_the_cursor() -> void:
	var m := Hero.by_id("wizard").make_basic() as HeroBasic
	var full := m.bolt_speed * m.bolt_life
	assert_true(absf(m.orb_life(Vector2.ZERO, Vector2(200, 0)) * m.bolt_speed - 200.0) < 0.01, "bursts at the cursor")
	assert_true(absf(m.orb_life(Vector2.ZERO, Vector2(5000, 0)) * m.bolt_speed - full) < 0.01, "never past its range")
	assert_true(absf(m.orb_life(Vector2.ZERO, Vector2(10, 0)) * m.bolt_speed - 90.0) < 0.01, "a cursor on top of you still throws a little")

# --- HUD shows the whole kit; gym dummies

func test_hud_shows_basic_skill_passive_ult() -> void:
	for id in ["knight", "rogue", "wizard", "ranger"]:
		var p := Player.new()
		track(p)
		p.hero = Hero.by_id(id)
		p.init_loadout()
		var panel := HeroPanel.new()
		track(panel)
		panel.player = p
		assert_eq(panel.columns(), [0, 1, "passive", Player.ULT_SLOT], id + ": LMB, RMB, PASSIVE, ULT")
	var b := Player.new()
	track(b)
	b.hero = Hero.by_id("bonker")
	b.init_loadout()
	var bp := HeroPanel.new()
	track(bp)
	bp.player = b
	assert_eq(bp.columns(), [0, 1, "passive", Player.ULT_SLOT], "Bonker: empty passive and ult columns, filled by drops")

func test_dummy_has_a_back_and_slides_home() -> void:
	var d := Dummy.new()
	track(d)
	d.aim_dir = Vector2.LEFT
	d.position = Vector2.ZERO
	assert_true(HeroBasic.Sweep.from_behind(d, Vector2(60, 0)), "behind a left-facing dummy")
	d._physics_process(0.016)   # sets home
	d.knock = Vector2(600, 0)
	d._physics_process(0.1)
	assert_gt(d.position.x, 10.0, "a shove slides it")
	for i in 200:
		d._physics_process(0.05)
	assert_true(d.position.length() < 3.0, "then it walks back home")

func test_heroes_5_to_8_have_their_own_kits() -> void:
	var pairs := {"paladin": "knight", "shade": "rogue", "sorcerer": "wizard", "scout": "ranger"}
	var kits := {}
	for id: String in pairs:
		var h := Hero.by_id(id)
		var b := Hero.by_id(pairs[id])
		assert_eq(h.id, id, id + " exists (not the fallback)")
		assert_eq(h.base_id, pairs[id], id + " borrows its base's icons")
		assert_ne(h.archetype, b.archetype, id + " is its own archetype")
		assert_ne(h.rmb_skill, b.rmb_skill, id + " has its own right click")
		assert_ne(h.ult_skill, b.ult_skill, id + " has its own ult")
		assert_ne(h.passive_name, b.passive_name)
		assert_ne(h.units, b.units, id + " has its own sprite set")
		assert_eq(h.make_kit().size(), 3)
		kits[h.rmb_skill + h.ult_skill] = true
	assert_eq(kits.size(), 4)
	assert_eq(Hero.by_id("knight").base_id, "", "core heroes are their own base")

# --- Kindling: stacking Burn

func _hero(id: String) -> Player:
	var p := Player.new()
	track(p)
	p.hero = Hero.by_id(id)
	p.init_loadout()
	return p

func test_kindling_stacks_ticks_and_decays() -> void:
	var v := _hero("knight")
	var mage := _hero("wizard")
	v.add_burn(1, mage)
	assert_eq(v.burn, 1)
	for i in 20:
		v.add_burn(1, mage)
	assert_eq(v.burn, Player.BURN_MAX, "capped at 12")
	v._burn_tick = 999.0   # hold the damage tick (it needs the scene tree): this checks the fade only
	v._tick_burn(Player.BURN_DECAY + 0.01)
	assert_eq(v.burn, Player.BURN_MAX - 1, "a stack fades every 2 s")
	v._tick_burn(Player.BURN_DECAY)
	assert_eq(v.burn, Player.BURN_MAX - 2)
	assert_false(Hero.by_id("knight").kindling, "only the Mage lights fires")

# --- Paladin

func test_paladin_heals_on_hit_and_hits_harder_healthy() -> void:
	var p := _hero("paladin")
	var b := p.spells[0] as HammerThrow
	assert_true(b != null, "the Paladin throws his hammer")
	assert_gt(b.might, 0.0)
	assert_gt(p.hero.lifesteal, 0.0)
	p.hp = 40
	var damage := 40
	var base_heal := roundi(damage * p.hero.lifesteal)
	p.on_hit_landed(damage)
	assert_eq(p.hp, 40 + base_heal, "Hammer applies Holy Might lifesteal")
	p.guardian(3.0)
	assert_true(p.guarded())
	p.on_hit_landed(damage)
	assert_eq(p.hp, 40 + 2 * base_heal + 20, "Guardian Angel adds half on top")
	assert_eq(p.hit_blocked(null), "immune", "nothing lands while the angel is up")

func test_purification_uses_the_projected_ground_distance() -> void:
	var center := Vector2(200, 150)
	assert_eq(Purification.ground_distance(center, center + Vector2(100, 0)), 100.0)
	assert_eq(snappedf(Purification.ground_distance(center, center + Vector2(0, 58)), 0.1), 100.0)
	assert_gt(Purification.ground_distance(center, center + Vector2(0, 105)), Purification.RADIUS + Purification.HIT_MARGIN)

# --- Shade

func test_focus_crits_at_configured_streak_on_one_target_only() -> void:
	var b := _hero("shade").spells[0] as DaggerThrow
	assert_true(b != null, "the Shade's basic is the thrown dagger")
	assert_gt(b.focus_hits, 1, "Focus requires a streak")
	var a := Node.new()
	var c := Node.new()
	track(a)
	track(c)
	for i in b.focus_hits - 1:
		assert_eq(b.focus_mult(a), 1.0, "no crit before the streak is complete")
	assert_eq(b.focus_mult(a), b.crit_mult, "the completed streak crits")
	b.focus_mult(a)
	assert_eq(b.focus_mult(c), 1.0, "a new target starts over")
	assert_eq(b.focus_count(), 1)
	b.prime_focus(a)
	assert_eq(b.focus_mult(a), b.crit_mult, "prime_focus: the next throw crits")
	assert_eq(b.focus_mult(null), 1.0, "a throw at nobody breaks the streak")
	assert_eq(b.focus_count(), 0)
	assert_eq((_hero("rogue").spells[0] as HeroBasic).focus_mult(a), 1.0, "the Rogue has no Focus")

func test_riposte_parries_and_blade_fury_shrugs_holds() -> void:
	var s := _hero("shade")
	s.parry(0.5)
	assert_true(s.parrying())
	assert_eq(s.hit_blocked(null), "parry", "the next hit is cancelled and countered")
	s._tick_timers(Player.STUN_IMMUNITY + 1.0)
	assert_false(s.parrying(), "the stance ends")
	s.spin(2.5)
	s.stun(1.0)
	s.freeze(1.0)
	assert_false(s.stunned() or s.frozen(), "Blade Fury: no stun, no freeze")

# --- Sorcerer

func test_chain_lightning_jumps_and_falls_off() -> void:
	var a := _foe_at(Vector2(100, 0), Vector2.LEFT)
	var b := _foe_at(Vector2(250, 0), Vector2.LEFT)
	var c := _foe_at(Vector2(420, 0), Vector2.LEFT)
	var far := _foe_at(Vector2(1200, 0), Vector2.LEFT)
	var foes: Array[Node2D] = [far, c, b, a]
	assert_eq(ChainLightning.chain(a, foes, 3), [a, b, c] as Array[Node2D], "nearest unhit within a jump, each time")
	assert_eq(ChainLightning.chain(a, foes, 5).size(), 3, "nothing within a jump of the last link: the chain stops")
	assert_eq(ChainLightning.chain(null, foes, 3).size(), 0)
	assert_gt(ChainLightning.link_damage(11, 0), ChainLightning.link_damage(11, 2))
	assert_true(Hero.by_id("sorcerer").make_basic() is ChainLightning)

func test_thunderstorm_and_ball_lightning() -> void:
	assert_eq(Thunderstorm.strikes(), 8, "4 s, a bolt every 0.45 s")
	var a := _foe_at(Vector2(200, 0), Vector2.LEFT)
	var off := _foe_at(Vector2(200, 200), Vector2.LEFT)
	var foes: Array[Node2D] = [a, off]
	assert_eq(BallLightning.path_hits(Vector2.ZERO, Vector2(400, 0), foes), [a] as Array[Node2D])
	assert_true(absf(BallLightning.landing(Vector2.ZERO, Vector2(3000, 0)).length() - BallLightning.RANGE) < 0.01)

# --- Scout

func test_scout_is_the_glass_cannon() -> void:
	var s := _hero("scout")
	var k := _hero("ranger")
	assert_gt(s.damage_mult, k.damage_mult, "deals more")
	assert_eq(s.hero.taken_mult, 1.35, "takes 35% more")
	assert_eq(roundi(20 * s.hero.taken_mult), 27)
	assert_false(s.consume_empower())
	s.empower(2.5)
	assert_true(s.consume_empower(), "Tumble loads the next shot")
	assert_false(s.consume_empower(), "once")

func test_tumble_and_assassinate_math() -> void:
	assert_true(absf(Tumble.roll_vec(Vector2.ZERO, Vector2(900, 0), Vector2.UP).length() - Tumble.ROLL) < 0.01)
	assert_eq(Tumble.roll_vec(Vector2.ZERO, Vector2(2, 0), Vector2.UP).normalized(), Vector2.UP, "cursor on you: roll the way you face")
	assert_eq(Assassinate.shot_damage(60, 0.9), 60)
	assert_eq(Assassinate.shot_damage(60, 0.3), 90, "execute under 40%")

# --- Ult tuning round: Smoke Screen, Blade Fury immune, Razor storm, Assassinate root

func test_smoke_screen_veils_the_rogue_and_blinds_foes() -> void:
	var r := _hero("rogue")
	var k := _hero("knight")
	assert_true(SmokeScreen.inside(Vector2.ZERO, Vector2(150, 0)))
	assert_false(SmokeScreen.inside(Vector2.ZERO, Vector2(260, 0)))
	r.veil(0.2)
	assert_true(r.veiled())
	r._tick_status(0.3)
	assert_false(r.veiled(), "steps out: seen again almost at once")
	var v := _hero("ranger")
	assert_eq(v.hit_blocked(k), "", "a clear-eyed attacker always connects")
	k.smoke(0.2)
	var misses := 0
	for i in 400:
		if v.hit_blocked(k) == "miss":
			misses += 1
	assert_true(misses > 120 and misses < 280, "about half of a smoked attacker's hits miss (%d / 400)" % misses)

func test_blade_fury_takes_no_damage() -> void:
	var s := _hero("shade")
	s.spin(2.5)
	assert_eq(s.hit_blocked(null), "immune")

func test_thunderstorm_picks_the_weakest_and_shreds() -> void:
	var healthy := _hero("knight")
	var hurt := _hero("knight")
	healthy.position = Vector2(50, 0)
	hurt.position = Vector2(250, 0)
	hurt.hp = 30
	var foes: Array[Node2D] = [healthy, hurt]
	assert_eq(Thunderstorm.pick(Vector2.ZERO, foes), hurt, "the lowest health share first, even if farther")
	assert_eq(Thunderstorm.strike_damage(7, 0), 7)
	assert_eq(Thunderstorm.strike_damage(7, 5), 12, "each strike on the same foe hits harder")
	assert_eq(Thunderstorm.pick(Vector2(5000, 0), foes), null)

func test_assassinate_roots_the_scout() -> void:
	var s := _hero("scout")
	s.root(Assassinate.AIM)
	assert_true(s.rooted())
	s._tick_status(Assassinate.AIM + 0.01)
	assert_false(s.rooted())
	assert_eq(GuardianAngel.DURATION, 4.0)

# --- Round 3: Shade dagger + blade wall, Sorcerer bolt + static field, Scout rain, Ranger shackle

func test_round3_kits() -> void:
	var shade := Hero.by_id("shade").make_kit()
	assert_true(shade[0] is DaggerThrow and shade[1] is FanOfKnives and shade[2] is BladeRing)
	assert_true((shade[0] as DaggerThrow).range_px < 400.0, "short range daggers")
	var sorc := Hero.by_id("sorcerer")
	assert_true(sorc.make_kit()[1] is LightningBolt and sorc.make_kit()[2] is Thunderstorm)
	assert_eq(sorc.passive_name, "Static Charge")
	assert_gt(sorc.static_field, 0.0)
	var scout := Hero.by_id("scout").make_kit()
	assert_true(scout[1] is ArrowRain, "the Scout throws the rain now")
	assert_gt(scout[1].cooldown, ArrowRain.new().cooldown, "the signature has its own longer cooldown")
	assert_true(Hero.by_id("ranger").make_kit()[2] is FocusFire)

func test_blade_wall_is_a_line_across_the_aim() -> void:
	var e := BladeWall.ends(Vector2.ZERO, Vector2(300, 0))
	assert_true(absf(e[0].distance_to(e[1]) - BladeWall.LENGTH) < 0.01)
	assert_true(absf(e[0].x - 300.0) < 0.01 and absf(e[1].x - 300.0) < 0.01, "across the line of sight, centred on the spot")
	assert_true(BladeWall.touching(e[0], e[1], Vector2(310, 50)))
	assert_false(BladeWall.touching(e[0], e[1], Vector2(400, 0)), "a step behind it is clear")
	assert_false(BladeWall.touching(e[0], e[1], Vector2(300, BladeWall.LENGTH)), "past its end is clear")

func test_lightning_bolt_reveals_the_smoke() -> void:
	var r := _hero("rogue")
	r.veil(1.0)
	assert_true(r.veiled())
	r.reveal(LightningBolt.REVEAL)
	assert_false(r.veiled(), "revealed: the smoke no longer hides him")
	r._tick_status(LightningBolt.REVEAL + 0.1)
	r.veil(1.0)
	assert_true(r.veiled(), "once the reveal wears off the smoke works again")
	assert_true(absf(LightningBolt.spot(Vector2.ZERO, Vector2(2000, 0)).length() - LightningBolt.MAX_RANGE) < 0.01)

func test_shackleshot_ties_to_a_foe_behind() -> void:
	var first := _foe_at(Vector2(300, 0), Vector2.LEFT)
	var behind := _foe_at(Vector2(450, 20), Vector2.LEFT)
	var aside := _foe_at(Vector2(450, 200), Vector2.LEFT)
	var before := _foe_at(Vector2(200, 0), Vector2.LEFT)
	var foes: Array[Node2D] = [first, behind, aside, before]
	assert_eq(Shackleshot.partner(first, Vector2.RIGHT, foes), behind)
	var alone: Array[Node2D] = [first, aside, before]
	assert_eq(Shackleshot.partner(first, Vector2.RIGHT, alone), null, "nobody behind on the line: the short stun")

# --- Round 4: Shade daggers, fan, ring; Focus Fire; burn decay; ult nerf

func test_fan_of_knives_spreads_evenly() -> void:
	var d := FanOfKnives.directions(Vector2.RIGHT)
	assert_eq(d.size(), FanOfKnives.KNIVES)
	assert_true(absf(d[0].angle_to(d[d.size() - 1]) - FanOfKnives.SPREAD) < 0.001)
	assert_true(absf(d[2].angle()) < 0.001, "the middle knife goes straight")

func test_blade_ring_is_a_small_circle_round_the_shade() -> void:
	assert_true(BladeRing.RADIUS < 160.0, "small: it hugs the Shade")
	assert_true(BladeRing.in_ring(Vector2.ZERO, Vector2(40, 0)))
	assert_true(BladeRing.in_ring(Vector2.ZERO, Vector2(BladeRing.RADIUS, 0)))
	assert_false(BladeRing.in_ring(Vector2.ZERO, Vector2(BladeRing.RADIUS + 60.0, 0)))

func test_focus_fire_status() -> void:
	var r := _hero("ranger")
	var t := _foe_at(Vector2(300, 0), Vector2.LEFT)
	assert_false(r.focus_firing())
	r.focus_fire_on(t, FocusFire.DURATION)
	assert_true(r.focus_firing())
	r._tick_status(FocusFire.DURATION + 0.01)
	assert_false(r.focus_firing())

func test_ults_cost_about_one_per_life() -> void:
	assert_eq(Player.ULT_TAKEN, 0.35)
	assert_eq(Player.BURN_DECAY, 1.2, "Kindling stacks fade every 1.2 s")
	for h in Hero.all():
		assert_true(h.ult_cost >= 140.0, h.id + "'s ult is not cheap")
		var u := h.make_kit()[Player.ULT_SLOT]
		assert_true(u.ult_lock() >= 1.5, h.id)
	assert_gt(Thunderstorm.new().ult_lock(), Thunderstorm.DURATION, "a lasting ult never pays for the next one")

# --- Paladin hammer (Dawnbreaker) + shore guards

func test_paladin_hammer_goes_out_hangs_and_returns() -> void:
	var b := Hero.by_id("paladin").make_basic() as HammerThrow
	assert_true(b.range_px <= 300.0, "short range")
	assert_true(b.cooldown >= 0.8, "a bit of cooldown")
	var turn := HammerThrow.turn_time(b.range_px)
	assert_true(absf(HammerThrow.out_offset(Vector2.RIGHT, b.range_px, turn).x - b.range_px) < 0.01, "at full reach when it turns")
	assert_true(HammerThrow.out_offset(Vector2.RIGHT, b.range_px, turn * 0.5).x < b.range_px, "still flying out halfway")
	assert_eq(HammerThrow.out_offset(Vector2.RIGHT, b.range_px, turn + 5.0).x, b.range_px, "never past its reach")
