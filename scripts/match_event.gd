class_name MatchEvent extends RefCounted
## Match events (docs/design_pillars_and_crown_mode.md §6.4): one rule for the whole match, rolled by the host once at
## FIGHT and shown on the FIGHT card and as a chip under the clock. Which event is dice; what it does is fixed. Events
## change the map and the information, never the kit's numbers. Classic and Crown only (Friendslop has its slot machine).
## `current` is the running match's event; Player, Radar, DropArrows and the HUD read it. The match resets it.

const NONE := "none"
const BLADEMAIL := "blademail"
const METEOR := "meteor"
const FOG := "fog"
const DOUBLE := "double"

## name / blurb: the FIGHT card. color: one per event, never a drop tier colour. weight: the roll.
const EVENTS := {
	NONE: {"name": "Clean match", "blurb": "", "color": Color(0.8, 0.8, 0.8), "weight": 40.0},
	BLADEMAIL: {"name": "Blademail", "blurb": "Every hit bites back: 30% of the damage returns to the attacker", "color": Color(0.62, 0.72, 0.85), "weight": 15.0},
	METEOR: {"name": "Meteor Shower", "blurb": "A meteor falls every 20 s. 2 s warning. Get out of the circle", "color": Color(1.0, 0.55, 0.2), "weight": 15.0},
	FOG: {"name": "Fog", "blurb": "No radar, no name tags, no drop arrows. The beams still shine", "color": Color(0.85, 0.88, 0.9), "weight": 15.0},
	DOUBLE: {"name": "Double Drop", "blurb": "Drops fall in pairs, on opposite sides of the centre", "color": Color(0.8, 0.5, 1.0), "weight": 15.0},
}
const ORDER := [NONE, BLADEMAIL, METEOR, FOG, DOUBLE]   ## roll order, so the same r gives the same event everywhere

const REFLECT := 0.3            ## Blademail: share of a hit's damage returned to the attacker
const METEOR_EVERY := 20.0      ## Meteor Shower: seconds between meteors
const METEOR_DELAY := 2.0       ## telegraph
const METEOR_RADIUS := 150.0
const METEOR_DAMAGE := 20
const METEOR_SHOVE := 700.0     ## outward launch on top of the hit's own knockback

static var current := NONE

static func valid(id: String) -> bool:
	return EVENTS.has(id)

static func cfg(id: String) -> Dictionary:
	return EVENTS.get(id, EVENTS[NONE])

static func is_on(id: String) -> bool:
	return current == id

## A weighted event id; r in [0, 1).
static func roll(r: float) -> String:
	var total := 0.0
	for id: String in ORDER:
		total += EVENTS[id].weight
	var x := r * total
	for id: String in ORDER:
		x -= EVENTS[id].weight
		if x < 0.0:
			return id
	return NONE

static func title(id: String) -> String:
	return cfg(id).name

static func color(id: String) -> Color:
	return cfg(id).color
