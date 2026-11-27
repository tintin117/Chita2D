extends McpTestSuite
## Logic tests for heroes 9-13 (Tidecaller, Rampager, Demonbound, Chaos Lord, secret Pactknight), the Knight's
## Rebound Shield and the Rogue's Stalk.

func suite_name() -> String:
	return "new_heroes"

func _hero(id: String) -> Player:
	var p := Player.new()
	track(p)
	p.hero = Hero.by_id(id)
	p.init_loadout()
	return p

func test_roster_and_secret() -> void:
	for id in ["tidecaller", "rampager", "demonbound", "chaoslord"]:
		assert_eq(Hero.by_id(id).id, id)
	assert_eq(Hero.by_id("pactknight").id, "pactknight", "the secret hero resolves by id (online picks)")
	assert_false(Hero.secret() in Hero.all(), "bots never take the secret hero")
	assert_eq(Hero.by_id("rampager").attack_type, "melee")
	assert_eq(Hero.by_id("demonbound").attack_type, "ranged")
	assert_eq(Hero.by_id("pactknight").attack_type, "ranged")
	assert_false(Hero.by_id("rampager").stalk, "the clone of the Rogue does not fade")
	assert_false(Hero.by_id("shade").stalk)
	assert_eq(Hero.by_id("demonbound").make_basic().splash, 0.0)
	assert_eq((Hero.by_id("pactknight").make_basic() as HeroBasic).splash, 0.0, "not a Mage orb")
	assert_gt((Hero.by_id("pactknight").make_basic() as HeroBasic).pull, 0.0)

func test_kits_wire_up() -> void:
	assert_true(Hero.by_id("knight").make_kit()[1] is ReboundShield)
	var t := Hero.by_id("tidecaller").make_kit()
	assert_true(t[1] is KeelSlam and t[2] is EbbAndFlow)
	var r := Hero.by_id("rampager").make_kit()
	assert_true(r[1] is WildOrb and r[2] is FaultLine)
	var d := Hero.by_id("demonbound").make_kit()
	assert_true(d[1] is MirrorTorment and d[2] is Fiendform)
	var c := Hero.by_id("chaoslord").make_kit()
	assert_true(c[1] is RiftBolt and c[2] is Stillwake)
	var p := Hero.secret().make_kit()
	assert_true(p[1] is Cluckcurse and p[2] is StarvingDark)

func test_chaos_roll_stays_in_range_and_is_seeded() -> void:
	var c := _hero("chaoslord")
	c.rng.seed = 42
	var a := Chaos.roll(c)
	c.rng.seed = 42
	assert_eq(Chaos.roll(c), a, "same seed, same roll on every peer")
	for i in 200:
		var r := Chaos.roll(c)
		assert_true(r >= Chaos.LO and r <= Chaos.HI)

func test_breaker_wave_band_and_cooldown() -> void:
	var r := BreakerWave.reach_for(Hero.by_id("tidecaller").attack_range)
	assert_true(absf(r - (Hero.by_id("tidecaller").attack_range + BreakerWave.BASE_LENGTH) / 2.0) < 0.01, "the mean of the swing and the old wave")
	assert_true(BreakerWave.on_front(Vector2(150, 0), Vector2.RIGHT, 2.3, 160.0), "on the front, straight ahead")
	assert_false(BreakerWave.on_front(Vector2(-150, 0), Vector2.RIGHT, 2.3, 160.0), "behind him: outside the swing's arc")
	assert_false(BreakerWave.on_front(Vector2(60, 0), Vector2.RIGHT, 2.3, 160.0), "already passed")
	var t := _hero("tidecaller")
	assert_true(t.wave_ready())
	t._wave_cd = Player.WAVE_CD
	assert_false(t.wave_ready())
	t.wave_refund(BreakerWave.REFUND)
	t._tick_status(Player.WAVE_CD - BreakerWave.REFUND + 0.01)
	assert_true(t.wave_ready(), "a hit pays back part of the wait")
	assert_false(_hero("knight").wave_ready())

func test_ebb_return_covers_the_gaps() -> void:
	var step := TAU / EbbAndFlow.SPOKES
	var gap := Vector2.from_angle(step * 0.5) * 200.0   # between two outgoing lines
	var out_hit := false
	var in_hit := false
	for i in EbbAndFlow.SPOKES:
		out_hit = out_hit or EbbAndFlow.on_spoke(gap, i * step, 0.0, EbbAndFlow.LENGTH)
		in_hit = in_hit or EbbAndFlow.on_spoke(gap, (i + 0.5) * step, 0.0, EbbAndFlow.LENGTH)
	assert_false(out_hit, "the gap dodges the burst out")
	assert_true(in_hit, "but not the rush back in")
	assert_eq(Hero.by_id("tidecaller").ult_taken_mult, 2.0)

func test_fault_line_catches_the_line_only() -> void:
	assert_true(FaultLine.delay() > 1.5, "the crack creeps: plenty of time to step off")
	assert_true(FaultLine.caught(Vector2.ZERO, Vector2.RIGHT, Vector2(400, 40)))
	assert_false(FaultLine.caught(Vector2.ZERO, Vector2.RIGHT, Vector2(400, 120)))
	assert_false(FaultLine.caught(Vector2.ZERO, Vector2.RIGHT, Vector2(FaultLine.LENGTH + 100.0, 0)))

func test_mirror_torment_uses_the_victims_own_attack() -> void:
	var k := _hero("knight")
	var e := MirrorTorment.echo(k)
	assert_eq(e[0], roundi(k.spells[0].damage * MirrorTorment.SHARE))
	assert_true(e[1] >= MirrorTorment.MIN_GAP)

func test_hex_blocks_casting_and_slows() -> void:
	var p := _hero("knight")
	var base := p._speed_mult()
	p.hex(Cluckcurse.TIME)
	assert_true(p.hexed())
	assert_true(p._speed_mult() < base)
	p._tick_status(Cluckcurse.TIME + 0.01)
	assert_false(p.hexed())

func test_time_stop_ignores_stun_immunity_then_grants_it() -> void:
	var p := _hero("knight")
	p._stun_immune = 1.0
	p.stun(1.0)
	assert_false(p.stunned(), "a normal stun is refused during the immunity")
	p.chrono_hold(1.0)
	assert_true(p.stunned() and p.time_stopped(), "stopped time is not")
	p._tick_stun(1.01)
	assert_false(p.time_stopped())
	assert_true(p._stun_immune > 0.0, "and the immunity follows it")

func test_weaken_and_brace_flags() -> void:
	var p := _hero("knight")
	p.weaken(KeelSlam.WEAK_TIME)
	assert_true(p.weakened())
	p._tick_status(KeelSlam.WEAK_TIME + 0.01)
	assert_false(p.weakened())

func test_darkvision_sees_a_faded_rogue_up_close() -> void:
	var rogue := _hero("rogue")
	var pact := _hero("pactknight")
	var other := _hero("knight")
	rogue.position = Vector2.ZERO
	pact.position = Vector2(Player.DARKVISION - 20.0, 0)
	other.position = Vector2(Player.STALK_SEEN + 50.0, 0)
	assert_true(rogue.stalking(), "fresh: faded")
	assert_true(rogue.hidden_from(other), "far: unseen")
	assert_false(rogue.hidden_from(pact), "Darkvision")
	rogue.break_stalk()
	assert_false(rogue.stalking(), "an attack or a hit breaks it")

func test_fiendform_and_long_malice() -> void:
	var d := _hero("demonbound")
	assert_false(d.fiended())
	d.fiend(Fiendform.TIME)
	assert_true(d.fiended())
	var b := d.spells[0] as HeroBasic
	assert_true(d.hero.fel_trail, "Hellwalker")
	assert_false(b.homing, "a skillshot")
	assert_true(Fiendform.DOUBLE_CHANCE > 0.5, "Demon Form: usually a second bolt")

func test_fel_trail_covers_where_he_walked() -> void:
	var t := FelTrail.new()
	track(t)
	t.add(Vector2.ZERO, FelTrail.THIN)
	t.add(Vector2(200, 0), FelTrail.THICK)
	assert_true(t.covers(Vector2(10, 0)))
	assert_false(t.covers(Vector2(10, 40)), "a walk trail is thin")
	assert_true(t.covers(Vector2(200, 35)), "a dash trail is thick")

func test_basic_hits_only_flinch() -> void:
	var v := _hero("knight")
	var a := _hero("tidecaller")
	Player.basic_hit = true
	v.take_damage(15, Vector2(-50, 0), false, a)
	Player.basic_hit = false
	assert_eq(v.knock, Vector2.ZERO, "a basic never pushes")
	v._iframes = 0.0
	v.take_damage(30, Vector2(-50, 0), false, a)
	assert_gt(v.knock.length(), 0.0, "a skill still launches")

func test_illusion_orb_vanish() -> void:
	var r := _hero("rampager")
	r.vanish(1.0)
	assert_true(r.vanished() and r.phased(), "inside the orb: gone and untouchable")
	r.end_vanish()
	assert_false(r.vanished())

func test_rebound_shield_bounces_to_the_nearest_unhit_foe() -> void:
	assert_eq(ReboundShield.MAX_HITS, 3)
	assert_true(ReboundShield.FALLOFF[2] < ReboundShield.FALLOFF[0], "each bounce weaker")

func test_ranger_arrow_is_a_skillshot_but_scout_homes() -> void:
	assert_false((Hero.by_id("ranger").make_basic() as HeroBasic).homing)
	assert_true((Hero.by_id("scout").make_basic() as HeroBasic).homing)

func test_six_seven_secret_and_kit() -> void:
	var h := Hero.by_id("sixseven")
	assert_eq(h.id, "sixseven")
	assert_eq(h.display_name, "Six Seven")
	assert_eq(h.attack_type, "ranged")
	assert_eq(h.max_hp, 67)
	assert_false(h in Hero.all(), "a secret: bots never take it")
	var kit := h.make_kit()
	assert_true(kit[0] is PacketLoss and kit[1] is SixSeven and kit[2] is ConnectionLost)
	assert_eq(SixSeven.RANGE, 267.0)
	assert_eq(SixSeven.STUN, 0.67)

func test_67_lives_saves_at_67_once_per_67s() -> void:
	var c := _hero("sixseven")
	var foe := _hero("knight")
	c.hp = 10
	c.take_damage(50, Vector2(-50, 0), false, foe)
	assert_eq(c.hp, mini(Player.LIVES_HP, c.max_hp), "the killing blow leaves 67 HP")
	assert_false(c.lives_ready())
	assert_eq(Player.LIVES_CD, 67.0)
	c._lives_guard = 0.0
	c._iframes = 0.0
	c.take_damage(500, Vector2(-50, 0), false, foe)
	assert_eq(c.hp, 0, "the second one inside the 67 s is not saved")

func test_packet_seeks_the_closest_foe() -> void:
	var c := _hero("sixseven")
	var near := _hero("knight")
	var far := _hero("rogue")
	near.position = Vector2(100, 0)
	far.position = Vector2(300, 0)
	assert_eq(PacketLoss.seek(c, Vector2.ZERO, null), near)
	assert_eq(PacketLoss.seek(c, Vector2.ZERO, far), far, "a locked foe in range wins")

func test_bot_moods_change_when_they_retreat() -> void:
	var S := BotBrain.State
	var hurt := {"has_target": true, "hp_frac": 0.35, "target_dist": 200.0}
	var cautious := hurt.duplicate()
	cautious["retreat_hp"] = BotBrain.MOOD_RETREAT[BotBrain.Mood.CAUTIOUS]
	var aggro := hurt.duplicate()
	aggro["retreat_hp"] = BotBrain.MOOD_RETREAT[BotBrain.Mood.AGGRO]
	assert_eq(BotBrain.next_state(S.ENGAGE, 5.0, cautious), S.RETREAT, "the careful one backs off at 35%")
	assert_eq(BotBrain.next_state(S.ENGAGE, 5.0, aggro), S.ENGAGE, "the brawler keeps swinging")

func test_bots_see_a_combo_window() -> void:
	var p := _hero("knight")
	assert_false(BotBrain._disabled(p))
	p.hex(1.0)
	assert_true(BotBrain._disabled(p), "a chicken cannot answer")
