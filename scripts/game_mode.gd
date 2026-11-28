class_name GameMode extends RefCounted
## Match modes. Classic: everyone picks a hero, a few drops now and then. Friendslop: everyone is the same modest Bonker
## (LMB bonk + RMB hook) and the power comes from the drops, which fall often and in numbers. Crown: Classic kits, but the
## score is time spent wearing the crown (see docs/design_pillars_and_crown_mode.md), so everyone hunts the king.
## The host picks the mode (Net.mode) and it travels with the match start, so every peer reads the same CONFIG row.

const CLASSIC := "classic"
const FRIENDSLOP := "friendslop"
const CROWN := "crown"
const MODES := [CLASSIC, CROWN, FRIENDSLOP]

## pickup_every / first_pickup: seconds between drops / until the first one. max_pickups: drops lying around at once.
## spawn_clear / apart: how far a drop stays from player spawns / other drops (smaller spawn_clear = drops spread over the whole arena).
## drop_after_deaths: no drops until this many players have died (0 = from the start); drop_per_deaths: after that, every
## this many deaths forces one more drop (0 = clock only). pickup_life: seconds a drop lies before it despawns (0 = never).
## channel: seconds of standing still on a drop to take it, per tier (0 = walk over it; empty = every drop is walk-over). centre_rares: rares and epics
## fall on the centre circle only. events: the match rolls a MatchEvent at FIGHT.
## Crown only: score_limit (points to win; a point per second worn), crown_delay (seconds after FIGHT until it appears),
## crown_grace (seconds a dropped crown lies untouchable), crown_reset (seconds unworn before it returns to the centre),
## crown_bounty (points for killing the king), crown_speed (the king's move speed multiplier; he also cannot dash).
const CONFIG := {
	CLASSIC: {"name": "Classic", "blurb": "Pick a hero, fight it out.", "hero_pick": true, "hero": "",
		"pickup_every": 15.0, "first_pickup": 3.0, "max_pickups": 2, "spawn_clear": 380.0, "apart": 300.0,
		"drop_after_deaths": 3, "drop_per_deaths": 3, "pickup_life": 15.0, "channel": [0.0, 0.5, 1.0], "centre_rares": true, "events": true,
		"kill_limit": 15, "time_limit": 300.0, "weapons": false, "crown": false},
	CROWN: {"name": "Crown", "blurb": "Grab the crown, wear it to score. Everyone hunts the king.", "hero_pick": true, "hero": "",
		"pickup_every": 15.0, "first_pickup": 3.0, "max_pickups": 2, "spawn_clear": 380.0, "apart": 300.0,
		"drop_after_deaths": 3, "drop_per_deaths": 3, "pickup_life": 15.0, "channel": [0.0, 0.5, 1.0], "centre_rares": false, "events": true,
		"kill_limit": 0, "time_limit": 300.0, "weapons": false, "crown": true,
		"score_limit": 60, "crown_delay": 5.0, "crown_grace": 2.0, "crown_reset": 10.0, "crown_bounty": 2, "crown_speed": 0.85},
	FRIENDSLOP: {"name": "Friendslop", "blurb": "Same hero for all. Loot the drops, wreck your friends.", "hero_pick": false, "hero": "bonker",
		"pickup_every": 4.5, "first_pickup": 1.5, "max_pickups": 5, "spawn_clear": 250.0, "apart": 350.0,
		"drop_after_deaths": 0, "drop_per_deaths": 0, "pickup_life": 0.0, "channel": [], "centre_rares": false, "events": false,
		"kill_limit": 20, "time_limit": 300.0, "weapons": true, "crown": false},
}

## Seconds of channel to take a drop of `tier` in `mode` (0 = walk over it).
static func channel_time(mode: String, tier: int) -> float:
	var times: Array = cfg(mode).get("channel", [])
	return float(times[clampi(tier, 0, times.size() - 1)]) if not times.is_empty() else 0.0

static func valid(mode: String) -> bool:
	return CONFIG.has(mode)

## The config row of a mode (unknown ids fall back to Classic).
static func cfg(mode: String) -> Dictionary:
	return CONFIG.get(mode, CONFIG[CLASSIC])

static func is_friendslop(mode: String) -> bool:
	return mode == FRIENDSLOP

## True when the score is crown time, not kills.
static func is_crown(mode: String) -> bool:
	return bool(cfg(mode).get("crown", false))

static func next(mode: String) -> String:
	return MODES[(MODES.find(mode) + 1) % MODES.size()]

static func title(mode: String) -> String:
	return cfg(mode).name
