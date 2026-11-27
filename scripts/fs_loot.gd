class_name FsLoot
## Friendslop passive and ult drops. The Bonker starts with an empty passive and an empty ult; a drop fills one.
## Passive (pickup kind "pas_<id>"): a hero passive baked onto the taker's own Hero copy, kept until death; a new passive
## drop swaps it out. Ult (kind "ult_<id>"): a hero ult in the F slot, ready right away, one use, lost on death.
## Both reuse the hero kits' code: a passive is just Hero fields (read by Player / the basic), an ult is a Spell.
## apply_pickup runs on every peer with the same kind, so every peer's Hero copy and kit agree.

## id -> name, text, and the Hero fields it sets. Only passives the Player (or the Bonk itself) reads work here.
const PASSIVES := {
	"kindling": {"name": "Kindling", "text": "Every hit adds a Burn stack: 1 damage per second each, up to 12.", "props": {"kindling": true}},
	"vampire": {"name": "Vampire", "text": "A quarter of all your damage heals you.", "props": {"lifesteal": 0.25}},
	"static": {"name": "Static Charge", "text": "Every hit also deals 5% of the target's current HP.", "props": {"static_field": 0.05}},
	"glass": {"name": "Glass Cannon", "text": "You deal 35% more damage and take 35% more.", "props": {"damage_dealt": 1.35, "taken_mult": 1.35}},
	"trampler": {"name": "Trampler", "text": "Every 90 px you move stomps foes right next to you for 3.", "props": {"stride": true}},
	"hellwalker": {"name": "Hellwalker", "text": "You leave burning ground behind you, thick where you dash.", "props": {"fel_trail": true}},
	"tide": {"name": "Tide Breaker", "text": "Every 7 s your next Bonk also sends a wave.", "props": {"tide_wave": true}},
	"bulwark": {"name": "Bulwark", "text": "Hits from the front deal 25% less.", "props": {"front_mult": 0.75}},
	"devils_eye": {"name": "Devil's Eye", "text": "See hidden foes close by. A kill gives you a short shield.", "props": {"darkvision": true, "fiend_toll": true}},
	"stalk": {"name": "Stalk", "text": "Hits from behind deal 1.8x. 1.5 s without attacking or being hit: you fade. Your first bonk out of the fade is a backstab.",
		"props": {"stalk": true, "back_mult": 1.8}},   # back_mult is copied onto the Bonk by Player._sync_basic_passive
}

## id -> the Hero.make_skill id of the ult. Only ults that work on a melee Bonker (no Focus Fire, no Fiendform).
const ULTS := {
	"meteor": "meteor", "judgement": "judgement", "smoke": "smoke_screen", "storm": "thunderstorm",
	"blade_ring": "blade_ring", "ebb": "ebb_and_flow", "fault": "fault_line", "stillwake": "stillwake",
	"dark": "starving_dark", "angel": "guardian_angel",
}

static func is_passive(kind: String) -> bool:
	return kind.begins_with("pas_") and PASSIVES.has(kind.substr(4))

static func is_ult(kind: String) -> bool:
	return kind.begins_with("ult_") and ULTS.has(kind.substr(4))

static func passive_kinds() -> Array:
	return PASSIVES.keys().map(func(k: String) -> String: return "pas_" + k)

static func ult_kinds() -> Array:
	return ULTS.keys().map(func(k: String) -> String: return "ult_" + k)

## Every Hero field any passive touches (cleared back to the Bonker's own values before a new one goes on).
static func passive_fields() -> Array:
	var out: Array = []
	for d: Dictionary in PASSIVES.values():
		for f: String in d.props:
			if f not in out:
				out.append(f)
	return out

## The ult's one-line text, taken from the hero that owns it (one source of truth).
static func ult_text(skill_id: String) -> String:
	var heroes: Array = Hero.all().duplicate()
	heroes.append(Hero.secret())
	for h: Hero in heroes:
		if h.ult_skill == skill_id:
			return h.ult_text
	return ""
