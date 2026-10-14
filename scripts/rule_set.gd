@tool  # ponytail: only so the in-editor test runner can instantiate it; it does nothing in the editor
class_name RuleSet extends RefCounted
## Global rules rolled by the slot machine. They stack multiplicatively and apply to EVERY creature:
## Player and Enemy read RuleSet.current at their own chokepoints (take_damage, stats recalculation).

signal changed

## mods keys: speed, damage (dealt), hp (max), attack_rate (recharge speed). Add a rule = add an entry here.
const RULES := {
	"adrenaline": {"name": "Adrenaline", "desc": "Everyone moves 25% faster", "color": Color(0.35, 0.85, 1.0), "mods": {"speed": 1.25}},
	"brute": {"name": "Brute Force", "desc": "Everyone deals 40% more damage", "color": Color(1.0, 0.45, 0.25), "mods": {"damage": 1.4}},
	"thick_skin": {"name": "Thick Skin", "desc": "Everyone has 40% more max HP", "color": Color(0.5, 0.9, 0.4), "mods": {"hp": 1.4}},
	"frenzy": {"name": "Frenzy", "desc": "Attacks and skills recharge 30% faster", "color": Color(1.0, 0.85, 0.3), "mods": {"attack_rate": 1.3}},
	"glass_cannon": {"name": "Glass Cannon", "desc": "Everyone deals 60% more damage\nbut has 30% less max HP", "color": Color(0.85, 0.5, 1.0), "mods": {"damage": 1.6, "hp": 0.7}},
	"stampede": {"name": "Stampede", "desc": "Everyone moves 15% faster and\nrecharges attacks 15% faster", "color": Color(1.0, 0.6, 0.7), "mods": {"speed": 1.15, "attack_rate": 1.15}},
}

## The one live instance. Long-lived on purpose: nodes connect to `changed` once, and reset() clears it in place.
static var current := RuleSet.new()

var speed := 1.0
var damage := 1.0
var hp := 1.0
var attack_rate := 1.0
var active: Array[String] = []   ## rule ids picked so far, in order

func reset() -> void:
	speed = 1.0
	damage = 1.0
	hp = 1.0
	attack_rate = 1.0
	active.clear()
	changed.emit()

func apply(id: String) -> void:
	var mods: Dictionary = RULES[id].mods
	speed *= mods.get("speed", 1.0)
	damage *= mods.get("damage", 1.0)
	hp *= mods.get("hp", 1.0)
	attack_rate *= mods.get("attack_rate", 1.0)
	active.append(id)
	changed.emit()

## A random rule id that isn't `last_id` (so back-to-back rolls differ).
static func roll(rng: RandomNumberGenerator, last_id := "") -> String:
	var ids: Array = RULES.keys().filter(func(k: String) -> bool: return k != last_id)
	return ids[rng.randi() % ids.size()]
