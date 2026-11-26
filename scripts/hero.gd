class_name Hero extends Resource
## A playable hero: sprite set, base stats and the starting basic attack.
## Two attack types: "melee" (cone sweep, attack_range = reach) and "ranged" (bolts, attack_range = travel distance).
## Tune attack_range / damage / hp / speed in all() below; everything else follows from them.
## A kit is the basic (LMB), one signature skill (RMB, rmb_skill), a passive (no button: it changes how the others
## behave) and, for heroes that have one, an ult (F / E, ult_skill) charged by dealing and taking damage instead of a
## cooldown. Dash is a shared movement verb, not a skill. Kits roll out hero by hero: see docs/design_pillars_and_crown_mode.md.

const UNIT_PATH := "res://assets/isometric_character/%s/"
const COLOR_ORDER := ["Blue", "Yellow", "Red", "Black"]   ## Player.COLORS; picks units[i % size]
const MAX_RANGE_FOR_UI := 700.0

@export var id := ""
@export var display_name := "Hero"
@export var description := ""
@export var units: Array = ["3Wizard"]      ## isometric_character folders, picked by player colour so look-alikes differ
@export var attack_type := "ranged"        ## "melee" | "ranged"
@export var attack_range := 380.0          ## px
@export var basic_name := "Fire Bolt"
@export var basic_damage := 10
@export var max_hp := 100
@export var speed := 260.0
@export var bolt_speed := 640.0
@export var bolt_pierce := 0
@export var finisher_spread := 1           ## extra bolt pairs on the 3rd cast (1 = 3 bolts)
@export var finisher_mult := 1.0           ## damage multiplier on the 3rd cast
@export var rmb_skill := "ember_field"     ## right click: shield_charge | shadow_rush | shadow_step | ember_field | power_shot | snipe_shot | hook
@export var rmb_text := ""                 ## one line for the select card
@export var passive_name := ""             ## the passive is behaviour baked into the kit (Rogue: back_mult); this names it for the UI
@export var passive_text := ""
@export var ult_skill := ""                ## "" = no ult yet (slot 2 stays empty) | shadow_dance
@export var ult_text := ""
@export var ult_cost := 150.0              ## charge to fill the ult: 1 per damage dealt, Player.ULT_TAKEN per damage taken (~1 ult per life)
@export var tint := Color.WHITE            ## multiplies the sprite (lets two heroes share a sprite set)
@export var basic_cd := 0.0                ## 0 = default pace (0.4s melee / 0.33s ranged)
@export var arc_angle := 2.2               ## melee sweep width (radians)
@export var back_mult := 1.0               ## melee: damage multiplier when the victim is facing away
@export var steady_aim := false            ## Ranger Steady Aim: a hold-and-release spell draws Player.STEADY_RATE x faster standing still
@export var kindling := false              ## Mage Kindling: every hit adds a Burn stack to the target (Player.add_burn)
@export var lifesteal := 0.0               ## share of damage dealt that heals you (Paladin)
@export var might := 0.0                   ## basic: + this x your current HP as damage (Paladin Holy Might)
@export var focus_hits := 0                ## basic: the Nth hit in a row on the same target crits (Shade Focus); 0 = off
@export var crit_mult := 2.5
@export var damage_dealt := 1.0            ## all your damage x this (Scout Glass Cannon)
@export var taken_mult := 1.0              ## damage you take x this (Scout Glass Cannon)
@export var static_field := 0.0            ## every hit also deals this share of the target's current HP (Sorcerer)
@export var rmb_cd := 0.0                  ## > 0: overrides the RMB spell's own cooldown (Arrow Rain is an ult spell, 0.6 s, on the Ranger)
@export var basic_spell := ""              ## a basic that is its own spell instead of HeroBasic (Sorcerer: chain_lightning)
@export var front_mult := 1.0              ## damage this hero TAKES from hits on the side it faces (Knight Bulwark: 0.75)
@export var lunge := 0.0                   ## melee: step-in speed of each sweep (px/s for 0.08 s); 0 = plant your feet (the default now)
@export var base_id := ""                  ## heroes 5-8: the core hero they are built on (defaults + skill icons until they get their own)
@export var archetype := ""                ## Tank | Assassin | Marksman | Artillery: one word for the card, see docs
@export var combo := true                  ## basic: 3rd cast in a row is a finisher (Knight). false = every cast the same
@export var windup := 0.1                  ## melee basic: telegraph before the swing turns live (heavier = longer)
@export var splash := 0.0                  ## ranged basic: > 0 = an orb that bursts at the cursor in this radius (Mage)
@export var basic_color := Color(1.0, 0.5, 0.15)   ## the basic's swing / orb colour
@export var basic_arrow := ""              ## ranged basic: arrow sprite ("" = spell bolt)

static var _all: Array[Hero] = []

static func all() -> Array[Hero]:
	if _all.is_empty():
		_all = [
			_make({"id": "knight", "display_name": "Knight", "units": ["1Knight"], "attack_type": "melee",
				"archetype": "Tank", "attack_range": 125.0,
				"description": "Tank. Slow, wide, heavy cleaves that hit everyone in front; the third one launches. Takes hits head-on, charges in, pins foes on rocks.",
				"basic_name": "Cleave", "basic_damage": 14, "max_hp": 140, "speed": 245.0, "finisher_mult": 1.8,
				"basic_cd": 0.5, "arc_angle": 2.7, "windup": 0.16, "basic_color": Color(1.0, 0.45, 0.15),
				"rmb_skill": "shield_charge", "rmb_text": "Rush forward and stun. Pinning a foe on a rock or wall stuns longer and hurts more.",
				"front_mult": 0.75,
				"passive_name": "Bulwark", "passive_text": "Hits from the front deal 25% less. Face your threat; a Rogue has to get behind you.",
				"ult_skill": "judgement", "ult_cost": 180.0,
				"ult_text": "Leap to the cursor over rocks and slam down: heavy damage, 1 s stun, shove out. Walk out of the circle to dodge."}),
			_make({"id": "rogue", "display_name": "Rogue", "units": ["7DeathKnight"], "attack_type": "melee", "attack_range": 80.0,
				"archetype": "Assassin",
				"description": "Assassin. Fastest hero. Quick narrow stabs, all the same, that hit for 1.8x from behind. Flank, burst, vanish. Dies if caught in the open.",
				"basic_name": "Stab", "basic_damage": 7, "max_hp": 75, "speed": 315.0, "combo": false,
				"basic_cd": 0.3, "arc_angle": 1.0, "windup": 0.04, "back_mult": 1.8, "basic_color": Color(0.75, 0.35, 1.0),
				"rmb_skill": "shadow_rush", "rmb_text": "Blink through a line. Everyone you pass is Frozen: can't move, dash or turn, but can still swing forward.",
				"passive_name": "Backstab", "passive_text": "Every hit from behind deals 1.8x. Rush through a foe that faces you and you land at its frozen back. In your Smoke Screen every stab is a backstab.",
				"ult_skill": "smoke_screen", "ult_cost": 140.0,
				"ult_text": "A cloud of smoke for 4.5 s: foes inside miss half their hits; you inside are invisible and every stab is a backstab."}),
			_make({"id": "wizard", "display_name": "Mage", "units": ["3Wizard"], "attack_type": "ranged",
				"archetype": "Artillery", "attack_range": 420.0,
				"description": "Artillery caster. Every basic is a spell: a fire orb you throw at a spot that bursts and hits everyone there. Burn the ground, call the meteor. Soft up close.",
				"basic_name": "Fire Orb", "basic_damage": 14, "max_hp": 95, "speed": 255.0, "bolt_speed": 800.0, "finisher_spread": 0,
				"basic_cd": 0.6, "combo": false, "splash": 70.0, "basic_color": Color(1.0, 0.45, 0.1),
				"rmb_skill": "ember_field", "rmb_text": "Blast a patch of ground: foes hit are slowed hard. It burns and slows for a while.",
				"kindling": true,
				"passive_name": "Kindling", "passive_text": "Every hit you land adds a Burn stack: 1 damage per second each, up to 12. One stack fades every 2 s.",
				"ult_skill": "meteor", "ult_cost": 160.0,
				"ult_text": "Call a meteor on the cursor. 1 s later it hits hard and launches everyone in the circle: knock them into the water."}),
			_make({"id": "ranger", "display_name": "Ranger", "units": ["2Archer", "9Longbow"], "attack_type": "ranged", "attack_range": 650.0,
				"archetype": "Marksman",
				"description": "Marksman. One long fast arrow at a time, piercing a foe. Longest reach; draw a Power Shot to blow them off the island. Fragile up close.",
				"basic_name": "Arrow", "basic_damage": 11, "max_hp": 80, "speed": 270.0, "bolt_speed": 1300.0, "bolt_pierce": 1, "finisher_spread": 0,
				"basic_cd": 0.45, "combo": false, "basic_color": Color(0.95, 0.9, 0.75), "basic_arrow": "res://assets/isometric_projecttile/Arrows/Arrow/0015.png",
				"rmb_skill": "power_shot", "rmb_text": "Hold to draw, release to fire. Aim freely while drawing. Longer draw = harder, farther, more knockback; full draw pierces.",
				"steady_aim": true,
				"passive_name": "Steady Aim", "passive_text": "Standing still while drawing Power Shot fills it twice as fast. Plant your feet, or kite with a slower draw.",
				"ult_skill": "focus_fire", "ult_cost": 150.0,
				"ult_text": "Focus Fire: for 4 s your arrows fly at one foe by themselves, 3x as fast, each 70% as hard. Keep moving."}),
		]
		# Heroes 5-8: own kits. base_id = the core hero whose skill icons they borrow until they get their own art.
		_all.append_array([
			_clone("knight", {"id": "paladin", "display_name": "Paladin", "units": ["4Paladin"], "tint": Color(1.0, 0.92, 0.6),
				"archetype": "Holy Tank", "attack_type": "ranged", "attack_range": 260.0,
				"description": "Holy Tank. Health is damage and damage is health: the thrown Hammer hits going out and coming back and heals you, Purification heals you and burns everyone near.",
				"basic_spell": "hammer_throw", "basic_name": "Hammer", "basic_damage": 12, "basic_cd": 0.85,
				"max_hp": 150, "speed": 240.0, "basic_color": Color(1.0, 0.85, 0.3),
				"lifesteal": 0.25, "might": 0.08, "front_mult": 1.0,
				"rmb_skill": "purification", "rmb_text": "Heal 30 and deal 30 to every foe around you.",
				"passive_name": "Holy Might", "passive_text": "Your Hammer deals +8% of your current HP on each of its two hits, and a quarter of all your damage heals you.",
				"ult_skill": "guardian_angel", "ult_cost": 170.0,
				"ult_text": "3 s of taking no damage; your hits heal you for half. Back off and wait it out."}),
			_clone("rogue", {"id": "shade", "display_name": "Shade", "units": ["8DarkLord"], "tint": Color(0.65, 1.0, 0.75),
				"archetype": "Duelist", "attack_type": "ranged", "attack_range": 330.0,
				"description": "Duelist. Throws daggers at short range: stay on one target and every 4th dagger is a sure crit. A fan of knives slows them, a ring of blades traps them.",
				"basic_spell": "dagger_throw", "basic_name": "Dagger", "basic_damage": 9, "basic_cd": 0.4,
				"max_hp": 95, "speed": 290.0, "back_mult": 1.0, "basic_color": Color(0.3, 1.0, 0.55),
				"focus_hits": 4, "crit_mult": 2.5,
				"rmb_skill": "fan_of_knives", "rmb_text": "A fan of 5 knives toward the cursor: each one hits and slows.",
				"passive_name": "Focus", "passive_text": "Every 4th dagger in a row at the same target is a 2.5x crit. Switching target starts over.",
				"ult_skill": "blade_ring", "ult_cost": 150.0,
				"ult_text": "A small ring of blades orbits you for 3.5 s: anyone close is cut and slowed. Keep throwing daggers."}),
			_clone("wizard", {"id": "sorcerer", "display_name": "Sorcerer", "units": ["6Mage"], "tint": Color(0.7, 0.8, 1.25),
				"archetype": "Storm Caster", "attack_range": 380.0,
				"description": "Storm Caster. Lightning that jumps from foe to foe and eats a slice of their health every hit. Bolts from the sky find anyone hiding.",
				"basic_spell": "chain_lightning", "basic_name": "Chain Lightning", "basic_damage": 11, "basic_cd": 0.45,
				"max_hp": 90, "speed": 260.0, "kindling": false, "basic_color": Color(0.55, 0.75, 1.0),
				"static_field": 0.05,
				"rmb_skill": "lightning_bolt", "rmb_text": "A bolt from the sky on the cursor: damage, slow, and it reveals anyone in a Smoke Screen.",
				"passive_name": "Static Field", "passive_text": "Every hit you land also deals 5% of the target's current HP: tanks feel it most.",
				"ult_skill": "thunderstorm", "ult_cost": 180.0,
				"ult_text": "For 3.5 s a storm follows you: every 0.45 s a bolt hits the weakest foe within 320, harder each time it hits the same one."}),
			_clone("ranger", {"id": "scout", "display_name": "Scout", "units": ["5CamoArcher"], "tint": Color(1.0, 0.75, 0.7),
				"archetype": "Glass Cannon", "attack_range": 520.0,
				"description": "Glass Cannon. The most damage and the least health in the game. Fast short arrows, a rain of arrows to zone, and a sniper ult. Never get caught.",
				"basic_name": "Quick Shot", "basic_damage": 8, "max_hp": 60, "speed": 290.0, "bolt_speed": 1400.0, "bolt_pierce": 0,
				"basic_cd": 0.3, "combo": false, "basic_color": Color(1.0, 0.55, 0.5), "steady_aim": false,
				"damage_dealt": 1.35, "taken_mult": 1.35,
				"rmb_skill": "arrow_rain", "rmb_cd": 9.0,
				"rmb_text": "Rain arrows on the cursor for 3 s: everyone inside keeps taking hits and is slowed. Leave or bleed.",
				"passive_name": "Glass Cannon", "passive_text": "You deal 35% more damage and take 35% more.",
				"ult_skill": "assassinate", "ult_cost": 140.0,
				"ult_text": "Root yourself and lock a laser on a foe for 1 s, then a huge shot (1.5x under 40% HP). A dash at the right time dodges it."}),
		])
	return _all

## A hero built on a core hero: a copy of `base` with `props` on top. Its own kit lives in `props`; what it does not
## override (sprite sheet layout, basic type, range defaults) comes from the base, and so do its skill icons.
static func _clone(base: String, props: Dictionary) -> Hero:
	var src: Hero = null
	for h in _all:
		if h.id == base:
			src = h
	var h := src.duplicate() as Hero
	h.base_id = base
	for k: String in props:
		h.set(k, props[k])
	return h

## The Friendslop hero: deliberately modest (short bonk, a hook for a skill) so the drops make the difference.
## Not in all(): it is never offered on the hero pick screen and Classic bots never use it.
static var _bonker: Hero

static func bonker() -> Hero:
	if _bonker == null:
		_bonker = _make({"id": "bonker", "display_name": "Bonker", "units": ["4Paladin", "1Knight", "7DeathKnight", "8DarkLord"], "attack_type": "melee", "attack_range": 95.0,
			"description": "Everyone's the same. A short bonk and a hook: the loot decides who wins.",
			"basic_name": "Bonk", "basic_damage": 9, "max_hp": 110, "speed": 265.0, "finisher_mult": 1.4,
			"basic_cd": 0.4, "arc_angle": 2.0,
			"rmb_skill": "hook", "rmb_text": "Throw a hook: the first foe it touches is dragged to you and stunned."})
	return _bonker

static func by_id(hero_id: String) -> Hero:
	if hero_id == "bonker":
		return bonker()
	for h in all():
		if h.id == hero_id:
			return h
	return all()[2]   # the Mage is the fallback

static func _make(props: Dictionary) -> Hero:
	var h := Hero.new()
	for k: String in props:
		h.set(k, props[k])
	return h

## The Basic, shaped by the archetype: pace, reach, width, combo or not, orb or arrow (see docs/design_pillars_and_crown_mode.md).
func make_basic() -> Spell:
	if basic_spell != "":   # a basic that is its own spell (Chain Lightning): it keeps the hero's name, damage and pace
		var own := make_skill(basic_spell)
		own.display_name = basic_name
		own.damage = basic_damage
		if basic_cd > 0.0:
			own.cooldown = basic_cd
		if "range_px" in own:
			own.range_px = attack_range
		if "might" in own:
			own.might = might
		if "focus_hits" in own:
			own.focus_hits = focus_hits
			own.crit_mult = crit_mult
		return own
	var s := HeroBasic.new()
	s.display_name = basic_name
	s.cooldown = basic_cd if basic_cd > 0.0 else (0.4 if attack_type == "melee" else 0.33)
	s.damage = basic_damage
	s.finisher_mult = finisher_mult
	s.combo = combo
	s.fx_color = basic_color
	s.might = might
	s.focus_hits = focus_hits
	s.crit_mult = crit_mult
	if attack_type == "melee":
		s.windup = windup
		s.mode = "arc"
		s.radius = attack_range
		s.arc_angle = arc_angle
		s.back_mult = back_mult
		s.lunge_speed = lunge
	else:
		s.mode = "bolt"
		s.sfx = "shoot"
		s.bolt_speed = bolt_speed
		s.bolt_life = attack_range / bolt_speed    # travel distance == attack_range
		s.bolt_pierce = bolt_pierce
		s.bolt_radius = 20.0 if bolt_pierce == 0 else 16.0
		s.finisher_spread = finisher_spread
		s.splash = splash
		s.arrow_tex = basic_arrow
		if splash > 0.0:
			s.sfx = "swing"   # a throw, not a shot
			s.bolt_radius = 15.0
	return s

static func make_skill(skill_id: String) -> Spell:
	match skill_id:
		"shield_charge": return ShieldCharge.new()
		"shadow_step": return ShadowStep.new()   # the old Rogue RMB (blink behind + stun); kept for A/B, no hero uses it now
		"shadow_rush": return ShadowRush.new()
		"judgement": return Judgement.new()
		"meteor": return Meteor.new()
		"purification": return Purification.new()
		"guardian_angel": return GuardianAngel.new()
		"riposte": return Riposte.new()
		"blade_fury": return BladeFury.new()
		"chain_lightning": return ChainLightning.new()
		"ball_lightning": return BallLightning.new()
		"thunderstorm": return Thunderstorm.new()
		"tumble": return Tumble.new()
		"assassinate": return Assassinate.new()
		"stifling_dagger": return StiflingDagger.new()
		"blade_wall": return BladeWall.new()
		"lightning_bolt": return LightningBolt.new()
		"shackleshot": return Shackleshot.new()   # Ranger ult before Focus Fire; kept for A/B
		"dagger_throw": return DaggerThrow.new()
		"fan_of_knives": return FanOfKnives.new()
		"blade_ring": return BladeRing.new()
		"focus_fire": return FocusFire.new()
		"hammer_throw": return HammerThrow.new()
		"power_shot": return PowerShot.new()
		"arrow_rain": return ArrowRain.new()
		"snipe_shot": return SnipeShot.new()   # the old Ranger RMB (locked line, stun); kept for A/B, no hero uses it now
		"hook": return Hook.new()
		"shadow_dance": return ShadowDance.new()   # the old Rogue ult (blink strikes); kept for A/B, no hero uses it now
		"smoke_screen": return SmokeScreen.new()
	return EmberField.new()

## Slot order: basic (LMB), signature skill (RMB), then the ult (F) when the hero has one.
func make_kit() -> Array[Spell]:
	var kit: Array[Spell] = [make_basic(), make_skill(rmb_skill)]
	if rmb_cd > 0.0:
		kit[1].cooldown = rmb_cd
	if ult_skill != "":
		kit.append(make_skill(ult_skill))
	return kit

## One SpriteFrames per facing (see SheetFrames.face). Sword units swing Melee/Melee2, the rest Attack1/Attack2.
func dir_frames(color: String) -> Array[SpriteFrames]:
	var d := UNIT_PATH % units[maxi(COLOR_ORDER.find(color), 0) % units.size()]
	var hit := "Melee" if ResourceLoader.exists(d + "Melee.png") else "Attack1"
	var hit2 := "Melee2" if hit == "Melee" else "Attack2"
	var anims := {"idle": [d + "Idle.png", 15, 12.0], "run": [d + "Run.png", 15, 24.0],
		"cast": [d + hit + ".png", 15, 30.0, false], "cast2": [d + hit2 + ".png", 15, 30.0, false]}
	for a: String in Player.RUN_ANIMS:   # backpedal / strafe sheets; a unit without one falls back to "run" (Player._run_anim)
		if not anims.has(a) and ResourceLoader.exists(d + Player.RUN_SHEETS[a]):
			anims[a] = [d + Player.RUN_SHEETS[a], 15, 24.0]
	return SheetFrames.build_dirs(anims)

## Facing the camera (south).
func frames(color: String) -> SpriteFrames:
	return dir_frames(color)[1]

## First idle frame, for the hero-select cards.
func portrait(color: String) -> Texture2D:
	return frames(color).get_frame_texture("idle", 0)
