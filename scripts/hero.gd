class_name Hero extends Resource
## A playable hero: sprite set, base stats and the starting basic attack.
## Two attack types: "melee" (cone sweep, attack_range = reach) and "ranged" (bolts, attack_range = travel distance).
## Tune attack_range / damage / hp / speed in all() below; everything else follows from them.
## A kit is exactly two skills: the basic (LMB) and one signature skill (RMB, rmb_skill). Dash is a shared movement verb, not a skill.

const UNIT_PATH := "res://assets/tiny_swords/units/%s/%s/"
const MAX_RANGE_FOR_UI := 700.0

@export var id := ""
@export var display_name := "Hero"
@export var description := ""
@export var unit := "Monk"                 ## Tiny Swords unit folder: Monk / Warrior / Archer
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
@export var rmb_skill := "ember_field"     ## right click: shield_charge | shadow_step | ember_field | snipe_shot
@export var rmb_text := ""                 ## one line for the select card
@export var tint := Color.WHITE            ## multiplies the sprite (lets two heroes share a sprite set)
@export var basic_cd := 0.0                ## 0 = default pace (0.4s melee / 0.33s ranged)
@export var arc_angle := 2.2               ## melee sweep width (radians)
@export var back_mult := 1.0               ## melee: damage multiplier when the victim is facing away
@export var lunge := 600.0                 ## melee: step-in speed of each sweep (px/s for 0.08 s, so 600 = ~48 px; the finisher doubles it)

static var _all: Array[Hero] = []

static func all() -> Array[Hero]:
	if _all.is_empty():
		_all = [
			_make({"id": "knight", "display_name": "Knight", "unit": "Warrior", "attack_type": "melee", "attack_range": 115.0,
				"description": "Bruiser. Commit to the fight and trade blows: three sweeping slashes, the last one hits hard. Shove foes toward the water.",
				"basic_name": "Flame Slash", "basic_damage": 12, "max_hp": 130, "speed": 255.0, "finisher_mult": 1.8,
				"rmb_skill": "shield_charge", "rmb_text": "Rush forward and shove. Pinning a foe on a rock or wall hurts more."}),
			_make({"id": "rogue", "display_name": "Rogue", "unit": "Warrior", "attack_type": "melee", "attack_range": 80.0,
				"description": "Assassin. Fastest hero, rapid short stabs that hit hard from behind. Flank, burst, vanish. Dies if caught in the open.",
				"basic_name": "Backstab", "basic_damage": 7, "max_hp": 75, "speed": 310.0, "finisher_mult": 1.4,
				"basic_cd": 0.3, "arc_angle": 1.7, "back_mult": 1.8, "lunge": 500.0, "tint": Color(0.62, 0.55, 0.85),
				"rmb_skill": "shadow_step", "rmb_text": "Blink behind your target and go untargetable for a moment."}),
			_make({"id": "wizard", "display_name": "Mage", "unit": "Monk", "attack_type": "ranged", "attack_range": 380.0,
				"description": "Zoner. Rapid fire bolts, every third cast fans out three. Control the ground and the pickups, peel anyone who gets close.",
				"basic_name": "Fire Bolt", "basic_damage": 10, "max_hp": 100, "speed": 260.0, "bolt_speed": 900.0, "finisher_spread": 1,
				"rmb_skill": "ember_field", "rmb_text": "Blast a patch of ground, knocking foes back. It burns and slows for a while."}),
			_make({"id": "ranger", "display_name": "Ranger", "unit": "Archer", "attack_type": "ranged", "attack_range": 650.0,
				"description": "Marksman. Piercing arrows from far away. Kite, hold the lines, and launch foes off the island. Fragile up close.",
				"basic_name": "Flame Arrow", "basic_damage": 9, "max_hp": 80, "speed": 270.0, "bolt_speed": 1200.0, "bolt_pierce": 1, "finisher_spread": 0, "finisher_mult": 2.2,
				"rmb_skill": "snipe_shot", "rmb_text": "Charge a heavy arrow, then it fires: huge knockback. Slow while aiming."}),
		]
	return _all

## The Friendslop hero: deliberately modest (short bonk, a shove for a skill) so the drops make the difference.
## Not in all(): it is never offered on the hero pick screen and Classic bots never use it.
static var _bonker: Hero

static func bonker() -> Hero:
	if _bonker == null:
		_bonker = _make({"id": "bonker", "display_name": "Bonker", "unit": "Warrior", "attack_type": "melee", "attack_range": 95.0,
			"description": "Everyone's the same. A short bonk and a shove: the loot decides who wins.",
			"basic_name": "Bonk", "basic_damage": 9, "max_hp": 110, "speed": 265.0, "finisher_mult": 1.4,
			"basic_cd": 0.4, "arc_angle": 2.0, "lunge": 500.0,
			"rmb_skill": "shove", "rmb_text": "Slam a shockwave that launches foes away. Great near water."})
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

## The Basic: a 3-cast combo for every hero (0.4s melee / 0.33s ranged casts unless basic_cd says otherwise, longer after the finisher).
func make_basic() -> Spell:
	var s := HeroBasic.new()
	s.display_name = basic_name
	s.cooldown = basic_cd if basic_cd > 0.0 else (0.4 if attack_type == "melee" else 0.33)
	s.damage = basic_damage
	s.finisher_mult = finisher_mult
	if attack_type == "melee":
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
	return s

static func make_skill(skill_id: String) -> Spell:
	match skill_id:
		"shield_charge": return ShieldCharge.new()
		"shadow_step": return ShadowStep.new()
		"snipe_shot": return SnipeShot.new()
		"shove": return Shove.new()
	return EmberField.new()

## Slot order: basic (LMB), signature skill (RMB).
func make_kit() -> Array[Spell]:
	return [make_basic(), make_skill(rmb_skill)]

func frames(color: String) -> SpriteFrames:
	var d := UNIT_PATH % [color, unit]
	match unit:
		"Warrior":
			return SheetFrames.build({"idle": [d + "Warrior_Idle.png", 8, 8.0], "run": [d + "Warrior_Run.png", 6, 12.0],
				"cast": [d + "Warrior_Attack1.png", 4, 22.0, false], "cast2": [d + "Warrior_Attack2.png", 4, 22.0, false]})
		"Archer":
			return SheetFrames.build({"idle": [d + "Archer_Idle.png", 6, 8.0], "run": [d + "Archer_Run.png", 4, 10.0],
				"cast": [d + "Archer_Shoot.png", 8, 36.0, false]})
	return SheetFrames.build({"idle": [d + "Idle.png", 6, 8.0], "run": [d + "Run.png", 4, 10.0],
		"cast": [d + "Heal.png", 11, 44.0, false]})

## First idle frame, for the hero-select cards.
func portrait(color: String) -> Texture2D:
	return frames(color).get_frame_texture("idle", 0)
