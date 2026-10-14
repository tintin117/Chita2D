class_name Item extends Resource
## An equippable item: one per gear slot, three rarities. Immutable data, so instances are shared.
## mods keys: max_hp (flat), damage / speed / cooldown (fractions; cooldown = reduction). Player.recalc_stats sums them.

const SLOTS := ["weapon", "armor", "trinket"]
const RARITY_NAMES := ["Common", "Rare", "Epic"]
const RARITY_COLORS := [Color(0.85, 0.85, 0.85), Color(0.4, 0.7, 1.0), Color(0.8, 0.45, 1.0)]
## Drop-table weights per rarity, indexed by enemy/camp tier - 1.
const ROLL_WEIGHTS := [[70, 25, 5], [40, 45, 15], [15, 50, 35]]

## [common, rare, epic] per slot: [name, mods]
const _TABLE := {
	"weapon": [["Iron Blade", {"damage": 0.10}], ["Ember Blade", {"damage": 0.18, "cooldown": 0.05}], ["Sunfire Edge", {"damage": 0.28, "cooldown": 0.10}]],
	"armor": [["Leather Vest", {"max_hp": 20}], ["Chain Mail", {"max_hp": 40, "speed": 0.03}], ["Dragon Plate", {"max_hp": 70, "speed": 0.05}]],
	"trinket": [["Swift Charm", {"speed": 0.06}], ["Focus Ring", {"cooldown": 0.10, "speed": 0.04}], ["Phoenix Idol", {"cooldown": 0.15, "max_hp": 30, "speed": 0.06}]],
}

@export var id := ""
@export var display_name := ""
@export var slot := "weapon"
@export var rarity := 0                 ## 0 common, 1 rare, 2 epic
@export var mods := {}

static var _all: Array[Item] = []

static func all() -> Array[Item]:
	if _all.is_empty():
		for s: String in SLOTS:
			for r in 3:
				var it := Item.new()
				it.slot = s
				it.rarity = r
				it.display_name = _TABLE[s][r][0]
				it.mods = _TABLE[s][r][1]
				it.id = it.display_name.to_snake_case()
				_all.append(it)
	return _all

static func by_id(item_id: String) -> Item:
	for it in all():
		if it.id == item_id:
			return it
	return null

## Random item; tier (1..3) skews toward better rarities. Pass a seeded rng for reproducible drops.
static func roll(rng: RandomNumberGenerator, tier := 1) -> Item:
	var w: Array = ROLL_WEIGHTS[clampi(tier, 1, 3) - 1]
	var pick := rng.randi_range(1, 100)
	var r := 0
	while r < 2 and pick > w[r]:
		pick -= w[r]
		r += 1
	var s: String = SLOTS[rng.randi() % SLOTS.size()]
	for it in all():
		if it.slot == s and it.rarity == r:
			return it
	return null

func color() -> Color:
	return RARITY_COLORS[rarity]

## "+20 HP, +10% damage" style summary.
func describe() -> String:
	var parts: Array[String] = []
	if mods.has("max_hp"):
		parts.append("+%d HP" % mods["max_hp"])
	if mods.has("damage"):
		parts.append("+%d%% damage" % roundi(mods["damage"] * 100))
	if mods.has("speed"):
		parts.append("+%d%% speed" % roundi(mods["speed"] * 100))
	if mods.has("cooldown"):
		parts.append("-%d%% cooldowns" % roundi(mods["cooldown"] * 100))
	return ", ".join(parts)
