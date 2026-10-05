class_name Hero extends Resource
## A playable hero: sprite set, base stats and the starting basic attack.
## Two attack types: "melee" (cone sweep, attack_range = reach) and "ranged" (bolts, attack_range = travel distance).
## Tune attack_range / damage / hp / speed in all() below; everything else follows from them.
## Every hero shares the rest of the kit (Blast, Fire Wave, Meteor Barrage) for now.

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

static var _all: Array[Hero] = []

static func all() -> Array[Hero]:
	if _all.is_empty():
		_all = [
			_make({"id": "knight", "display_name": "Knight", "unit": "Warrior", "attack_type": "melee", "attack_range": 115.0,
				"description": "Sweeping flame slashes at close range. Tough and hard-hitting.", "basic_name": "Flame Slash",
				"basic_damage": 12, "max_hp": 130, "speed": 255.0, "finisher_mult": 1.8}),
			_make({"id": "wizard", "display_name": "Wizard", "unit": "Monk", "attack_type": "ranged", "attack_range": 380.0,
				"description": "Rapid fire bolts at mid range; every third cast fans out three.", "basic_name": "Fire Bolt",
				"basic_damage": 10, "max_hp": 100, "speed": 260.0, "bolt_speed": 640.0, "finisher_spread": 1}),
			_make({"id": "ranger", "display_name": "Ranger", "unit": "Archer", "attack_type": "ranged", "attack_range": 650.0,
				"description": "Fast piercing shots from far away. Fragile, but never needs to get close.", "basic_name": "Flame Arrow",
				"basic_damage": 9, "max_hp": 80, "speed": 275.0, "bolt_speed": 900.0, "bolt_pierce": 1, "finisher_spread": 0, "finisher_mult": 2.2}),
		]
	return _all

static func by_id(hero_id: String) -> Hero:
	for h in all():
		if h.id == hero_id:
			return h
	return all()[1]

static func _make(props: Dictionary) -> Hero:
	var h := Hero.new()
	for k: String in props:
		h.set(k, props[k])
	return h

## The starting Basic: same fast 3-cast combo for every hero (0.28s casts, 0.6s after the finisher).
func make_basic() -> Spell:
	var s := HeroBasic.new()
	s.display_name = basic_name
	s.cooldown = 0.28
	s.damage = basic_damage
	s.finisher_mult = finisher_mult
	if attack_type == "melee":
		s.mode = "arc"
		s.radius = attack_range
		s.lunge_speed = 300.0
	else:
		s.mode = "bolt"
		s.bolt_speed = bolt_speed
		s.bolt_life = attack_range / bolt_speed    # travel distance == attack_range
		s.bolt_pierce = bolt_pierce
		s.bolt_radius = 10.0 if bolt_pierce == 0 else 8.0
		s.finisher_spread = finisher_spread
	return s

func frames(color: String) -> SpriteFrames:
	var d := UNIT_PATH % [color, unit]
	match unit:
		"Warrior":
			return SheetFrames.build({"idle": [d + "Warrior_Idle.png", 8, 8.0], "run": [d + "Warrior_Run.png", 6, 12.0],
				"cast": [d + "Warrior_Attack1.png", 4, 22.0, false]})
		"Archer":
			return SheetFrames.build({"idle": [d + "Archer_Idle.png", 6, 8.0], "run": [d + "Archer_Run.png", 4, 10.0],
				"cast": [d + "Archer_Shoot.png", 8, 36.0, false]})
	return SheetFrames.build({"idle": [d + "Idle.png", 6, 8.0], "run": [d + "Run.png", 4, 10.0],
		"cast": [d + "Heal.png", 11, 44.0, false]})

## First idle frame, for the hero-select cards.
func portrait(color: String) -> Texture2D:
	return frames(color).get_frame_texture("idle", 0)
