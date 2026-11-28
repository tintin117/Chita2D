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
@export var skill_anims := false            ## use the unit's CastSpell and Special1 sheets for signature and ult
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
@export var basic_color := Color(1.0, 0.5, 0.15)   ## the hero's signature colour: the basic's swing / bolt, cast flashes, hit sparks
@export var basic_arrow := ""              ## ranged basic: arrow sprite ("" = spell bolt)
@export var homing := true                 ## ranged basic: a locked shot steers at its target (false = skillshot)
@export var tide_wave := false             ## Tidecaller Breaker Wave: every Player.WAVE_CD s the next swing also sends a wave
@export var stride := false                ## Rampager Rumble Stride: moving stomps foes close by (Player._tick_stride)
@export var chaos_lo := 0.0                ## Chaos Lord Loaded Dice: every cast rolls x[chaos_lo, chaos_hi]; 0 = off
@export var chaos_hi := 0.0
@export var lives_67 := false              ## Six Seven: a lethal hit leaves him at Player.LIVES_HP, once per Player.LIVES_CD
@export var fel_trail := false             ## Demonbound Hellwalker: leaves burning ground (FelTrail), thick on a dash
@export var impetus := 0.0                 ## Demonbound Long Malice: basic bolt + this damage per px flown
@export var pull := 0.0                    ## Pactknight Grasping Blast: basic hit drags the foe this many px toward you
@export var darkvision := false            ## Pactknight: sees hidden foes within Player.DARKVISION (only for himself)
@export var fiend_toll := false            ## Pactknight: a kill gives a short shield (Player.grant_toll)
@export var ult_taken_mult := 1.0          ## damage taken charges the ult this many times faster (Tidecaller: 2)
@export var stalk := false                 ## Rogue Stalk: fades out of combat, unseen by foes farther than Player.STALK_SEEN

static var _all: Array[Hero] = []

static func all() -> Array[Hero]:
	if _all.is_empty():
		_all = [
			_make({"id": "knight", "display_name": "Knight", "units": ["1Knight"], "attack_type": "melee",
				"archetype": "Tank", "attack_range": 145.0,
				"description": "Tank. Slow, wide, heavy cleaves that hit everyone in front; the third one launches. Takes hits head-on and throws a shield that rebounds between foes.",
				"basic_name": "Cleave", "basic_damage": 14, "max_hp": 140, "speed": 252.0, "finisher_mult": 1.8,
				"basic_cd": 0.50, "arc_angle": 2.8, "windup": 0.16, "basic_color": Color(1.0, 0.62, 0.15),
				"rmb_skill": "rebound_shield", "rmb_text": "Throw your shield: it rebounds between up to 3 foes (each hit weaker), slows the first, then flies back to you.",
				"front_mult": 0.75,
				"passive_name": "Bulwark", "passive_text": "Hits from the front deal 25% less, but only while you hold your shield: it is off while the shield is thrown.",
				"ult_skill": "judgement", "ult_cost": 180.0,
				"ult_text": "Leap over rocks to the cursor, hang briefly, then slam. Deals heavy damage, stuns for 1 s, and shoves foes out. Move out of the marked area to dodge."}),
			_make({"id": "rogue", "display_name": "Rogue", "units": ["11Rogue"], "attack_type": "melee", "attack_range": 112.0,
				"archetype": "Assassin",
				"description": "Assassin. Fastest hero. Quick narrow stabs, all the same, that hit for 1.8x from behind. Flank, burst, vanish. Dies if caught in the open.",
				"basic_name": "Stab", "basic_damage": 14, "max_hp": 95, "speed": 325.0, "combo": false,
				"basic_cd": 0.3, "arc_angle": 0.95, "windup": 0.04, "back_mult": 1.8, "basic_color": Color(0.62, 0.6, 0.9), "stalk": true,
				"rmb_skill": "shadow_rush", "rmb_cd": 5.0, "rmb_text": "Blink through a line. Everyone you pass is Frozen: can't move, dash or turn, but can still swing forward.",
				"passive_name": "Stalk", "passive_text": "Hits from behind deal 1.8x. 1.5 s without attacking or being hit: you fade, unseen by foes farther than 260 px and a faint shimmer closer in. Your first stab out of the fade is always a backstab.",
				"ult_skill": "smoke_screen", "ult_cost": 140.0,
				"ult_text": "A cloud of smoke for 4.5 s: foes inside miss half their hits; you inside are invisible and every stab is a backstab."}),
			_make({"id": "wizard", "display_name": "Mage", "units": ["3Wizard"], "attack_type": "ranged",
				"archetype": "Artillery", "attack_range": 390.0,
				"description": "Artillery caster. Every basic is a spell: a fire orb you throw at a spot that bursts and hits everyone there. Burn the ground, call the meteor. Soft up close.",
				"basic_name": "Fire Orb", "basic_damage": 13, "max_hp": 95, "speed": 255.0, "bolt_speed": 800.0, "finisher_spread": 0,
				"basic_cd": 0.68, "combo": false, "splash": 68.0, "basic_color": Color(1.0, 0.45, 0.1),
				"rmb_skill": "ember_field", "rmb_text": "Blast a patch of ground: foes hit are slowed hard. It burns and slows for a while.",
				"kindling": true,
				"passive_name": "Kindling", "passive_text": "Every hit you land adds a Burn stack: 1 damage per second each, up to 12. One stack fades every 2 s.",
				"ult_skill": "meteor", "ult_cost": 160.0,
				"ult_text": "Call a meteor on the cursor. 1 s later it hits hard and launches everyone in the circle: knock them into the water."}),
			_make({"id": "ranger", "display_name": "Ranger", "units": ["2Archer", "9Longbow"], "attack_type": "ranged", "attack_range": 560.0,
				"archetype": "Marksman",
				"description": "Marksman. One long arrow at a time, piercing a foe. It flies straight: lead your shots. Longest reach; draw a Power Arrow to blow them off the island. Fragile up close.",
				"basic_name": "Arrow", "basic_damage": 10, "max_hp": 80, "speed": 270.0, "bolt_speed": 1300.0, "homing": false, "bolt_pierce": 1, "finisher_spread": 0,
				"basic_cd": 0.50, "combo": false, "basic_color": Color(0.95, 0.9, 0.75), "basic_arrow": "res://assets/isometric_projecttile/Arrows/Arrow/",
				"rmb_skill": "power_shot", "rmb_text": "Hold to draw, release to fire. Aim freely while drawing. Longer draw = harder, farther, more knockback; full draw pierces.",
				"steady_aim": true,
				"passive_name": "Steady Aim", "passive_text": "Standing still while drawing Power Arrow fills it twice as fast. Plant your feet, or kite with a slower draw.",
				"ult_skill": "focus_fire", "ult_cost": 150.0,
				"ult_text": "Focus Volley: for 4 s your arrows fly at one foe by themselves, 3x as fast, each 70% as hard. Keep moving."}),
		]
		# Heroes 5-8: own kits. base_id = the core hero whose skill icons they borrow until they get their own art.
		_all.append_array([
			_clone("knight", {"id": "paladin", "display_name": "Paladin", "units": ["4Paladin"], "skill_anims": true, "tint": Color(1.0, 0.92, 0.6),
				"archetype": "Holy Tank", "attack_type": "ranged", "attack_range": 270.0,
				"description": "Holy Tank. The thrown Hammer hits going out and coming back. Purify sends holy light outward, then draws it back in.",
				"basic_spell": "hammer_throw", "basic_name": "Hammer", "basic_damage": 12, "basic_cd": 1.18,
				"max_hp": 112, "speed": 240.0, "basic_color": Color(1.0, 0.88, 0.35),
				"lifesteal": 0.09, "might": 0.035, "front_mult": 1.0,
				"rmb_skill": "purification", "rmb_cd": 11.0, "rmb_text": "Send a ring outward, then draw it back in. The ring follows you. Each sweep heals you for 15 and deals 15 damage per foe crossed.",
				"passive_name": "Holy Might", "passive_text": "Your Hammer deals +3.5% of your current HP on each of its two hits, and 9% of all your damage heals you.",
				"ult_skill": "guardian_angel", "ult_cost": 200.0,
				"ult_text": "3 s of taking no damage; your hits heal you for half. Back off and wait it out."}),
			_clone("rogue", {"id": "shade", "display_name": "Shade", "units": ["8DarkLord"], "tint": Color(0.65, 1.0, 0.75),
				"archetype": "Duelist", "attack_type": "ranged", "attack_range": 305.0, "stalk": false,
				"description": "Duelist. Throws daggers at short range: stay on one target and every 3rd dagger is a sure crit. A fan of knives slows them, a ring of blades traps them.",
				"basic_spell": "dagger_throw", "basic_name": "Dagger", "basic_damage": 14, "basic_cd": 0.35,
				"max_hp": 112, "speed": 290.0, "back_mult": 1.0, "basic_color": Color(0.2, 1.0, 0.6),
				"focus_hits": 3, "crit_mult": 2.5,
				"rmb_skill": "fan_of_knives", "rmb_cd": 5.0, "rmb_text": "A fan of 5 knives toward the cursor: each one hits and slows.",
				"passive_name": "Focus", "passive_text": "Every 3rd dagger in a row at the same target is a 2.5x crit. Switching target starts over.",
				"ult_skill": "blade_ring", "ult_cost": 150.0,
				"ult_text": "A small ring of blades orbits you for 3.5 s: anyone close is cut and slowed. Keep throwing daggers."}),
			_clone("wizard", {"id": "sorcerer", "display_name": "Sorcerer", "units": ["6Mage"], "tint": Color(0.7, 0.8, 1.25),
				"archetype": "Storm Caster", "attack_range": 310.0,
				"description": "Storm Caster. Lightning that jumps from foe to foe and eats a slice of their health every hit. Bolts from the sky find anyone hiding.",
				"basic_spell": "chain_lightning", "basic_name": "Chain Lightning", "basic_damage": 5, "basic_cd": 0.88,
				"max_hp": 85, "speed": 260.0, "kindling": false, "basic_color": Color(0.55, 0.75, 1.0),
				"static_field": 0.02,
				"rmb_skill": "lightning_bolt", "rmb_cd": 9.5, "rmb_text": "A bolt from the sky on the cursor: damage, slow, and it reveals anyone in a Smoke Cloud.",
				"passive_name": "Static Charge", "passive_text": "Every hit you land also deals 2% of the target's current HP: tanks feel it most.",
				"ult_skill": "thunderstorm", "ult_cost": 220.0,
				"ult_text": "For 3.5 s a storm follows you: every 0.45 s a bolt hits the weakest foe within 320, harder each time it hits the same one."}),
			_clone("ranger", {"id": "scout", "display_name": "Scout", "units": ["5CamoArcher"], "tint": Color(1.0, 0.75, 0.7),
				"archetype": "Glass Cannon", "attack_range": 470.0,
				"description": "Glass Cannon. The least health in the game. Fast short arrows, a rain of arrows to zone, and a sniper ult. Never get caught.",
				"basic_name": "Quick Shot", "basic_damage": 4, "max_hp": 60, "speed": 290.0, "bolt_speed": 1400.0, "bolt_pierce": 0, "homing": true,
				"basic_cd": 0.39, "combo": false, "basic_color": Color(1.0, 0.55, 0.5), "steady_aim": false,
				"basic_arrow": "res://assets/isometric_projecttile/Arrows/FireArrow/",
				"damage_dealt": 1.12, "taken_mult": 1.35,
				"rmb_skill": "arrow_rain", "rmb_cd": 10.0,
				"rmb_text": "Rain arrows on the cursor for 3 s: everyone inside keeps taking hits and is slowed. Leave or bleed.",
				"passive_name": "Glass Cannon", "passive_text": "You deal 12% more damage and take 35% more.",
				"ult_skill": "assassinate", "ult_cost": 160.0,
				"ult_text": "Root yourself and lock a laser on a foe for 1 s, then a huge shot (1.5x under 40% HP). A dash at the right time dodges it."}),
		])
		# Heroes 9-12: Tidecaller, Rampager, Demonbound, Chaos Lord. Built on a core hero for sprite layout and icons;
		# every field that hero sets and these do not want is overridden here (a clone keeps the base's values).
		_all.append_array([
			_clone("knight", {"id": "tidecaller", "display_name": "Tidecaller", "units": ["4Paladin"], "tint": Color(0.6, 0.95, 1.2),
				"archetype": "Bruiser", "attack_type": "melee", "attack_range": 165.0,
				"description": "Bruiser. Heavy anchor swings that send a wave every few seconds. The more he is hit, the sooner the tide comes in and out of his body.",
				"basic_name": "Anchor Swing", "basic_damage": 15, "basic_cd": 0.56, "max_hp": 145, "speed": 245.0,
				"combo": false, "finisher_mult": 1.0, "arc_angle": 1.6, "windup": 0.18, "basic_color": Color(0.15, 0.85, 0.85),
				"front_mult": 1.0, "tide_wave": true,
				"rmb_skill": "keel_slam", "rmb_text": "Slam the anchor around you: damage, and everyone hit deals 30% less damage for 3 s.",
				"passive_name": "Tide Breaker", "passive_text": "Every 7 s (shown like a cooldown) your next swing also sends a wave the same shape as the swing, out to about 210 px: 12 damage. The first foe it hits takes 1 s off the wait.",
				"ult_skill": "ebb_and_flow", "ult_cost": 170.0, "ult_taken_mult": 2.0,
				"ult_text": "Six lines of water burst out of you (damage, push), then rush back in between them (damage, pull to you). You take 30% less meanwhile. Charges 2x from damage taken."}),
			_clone("rogue", {"id": "rampager", "display_name": "Rampager", "units": ["7DeathKnight"], "tint": Color(1.2, 0.8, 0.55),
				"archetype": "Diver", "attack_type": "melee", "attack_range": 130.0,
				"description": "Diver. Hurls an orb and lands where it does, then runs circles: every step stomps. Splits the earth to drag a whole line of foes in.",
				"basic_name": "Claw", "basic_damage": 12, "basic_cd": 0.40, "max_hp": 136, "speed": 309.0,
				"combo": false, "arc_angle": 1.35, "windup": 0.06, "back_mult": 1.0, "stalk": false, "stride": true,
				"basic_color": Color(0.85, 0.6, 0.3),
				"rmb_skill": "wild_orb", "rmb_cd": 0.0, "rmb_text": "Hurl a slow orb at the cursor: it hits everyone it passes, and you blink to where it lands. No take-backs.",
				"passive_name": "Trampler", "passive_text": "Every 90 px you move (walk, dash or blink) stomps foes right next to you for 3.",
				"ult_skill": "fault_line", "ult_cost": 160.0,
				"ult_text": "Plant your feet and crack the ground: the crack creeps out in a long line, then splits: 25% of max HP, everyone on it is pulled to the line and slowed for 3 s."}),
			_clone("ranger", {"id": "demonbound", "display_name": "Demonbound", "units": ["8DarkLord"], "tint": Color(1.25, 0.55, 0.55),
				"archetype": "Sniper Caster", "attack_type": "ranged", "attack_range": 485.0,
				"description": "Sniper Caster. Leaves burning ground wherever he goes, thick where he dashes. Kite in lines and shoot back through them: bolts that cross the fire burn hotter and burst.",
				"basic_name": "Hellbolt", "basic_damage": 9, "basic_cd": 0.76, "max_hp": 85, "speed": 255.0,
				"bolt_speed": 600.0, "bolt_pierce": 0, "homing": false, "basic_arrow": "", "basic_color": Color(0.95, 0.15, 0.25),
				"steady_aim": false, "impetus": 0.0, "fel_trail": true, "rmb_cd": 9.0,
				"rmb_skill": "mirror_torment", "rmb_text": "Curse a spot: every foe there gets a dark copy clinging to its back that hits it with its own attack and slows it for 3.5 s.",
				"passive_name": "Hellwalker", "passive_text": "You leave burning ground for 3 s: thin when you walk, thick when you dash. Foes on it burn and are slowed. Your bolts that cross it catch fire: +6 damage and a small blast.",
				"ult_skill": "fiendform", "ult_cost": 160.0,
				"ult_text": "Become the demon for 6 s: bolts fly 40% farther and faster, hit 30% harder, and 60% of them come with a second bolt. Dark Reflection lasts 1 s longer."}),
			_clone("knight", {"id": "chaoslord", "display_name": "Chaos Lord", "units": ["10ChaosLord"], "skill_anims": true,
				"archetype": "Gambler", "attack_type": "melee", "attack_range": 145.0,
				"description": "Gambler. Slow swings that roll the dice: anything from a tickle to a crater. Every skill rolls too, even how long time stops.",
				"basic_name": "Chaos Cleave", "basic_damage": 13, "basic_cd": 0.53, "max_hp": 155, "speed": 275.0,
				"combo": false, "finisher_mult": 1.0, "arc_angle": 3.5, "windup": 0.16, "basic_color": Color(0.95, 0.3, 0.85),
				"front_mult": 1.0, "chaos_lo": 0.5, "chaos_hi": 3.5,
				"rmb_skill": "rift_bolt", "rmb_cd": 4.6, "rmb_text": "A bolt at the foe near the cursor. The roll scales both its damage and its stun (0.3 to 2.1 s).",
				"passive_name": "Chaos Roll", "passive_text": "Everything you do rolls x0.5 to x3.5: your swing's damage, Chaos Blast's damage and stun, Time Sphere's length.",
				"ult_skill": "stillwake", "ult_cost": 180.0,
				"ult_text": "Stop time in a circle at the cursor: everyone inside but you is held for 0.4 to 2.8 s (rolled). Walk in and swing."}),
		])
	return _all

## The secret hero (Konami code on the hero pick, see PlaySettings.pact_unlocked). Not in all(): bots never take him.
static var _pact: Hero

static func secret() -> Hero:
	if _pact == null:
		all()
		_pact = _clone("wizard", {"id": "pactknight", "display_name": "Pactknight", "units": ["4Paladin"], "tint": Color(0.8, 0.6, 1.25),
			"archetype": "Hexblade", "attack_type": "ranged", "attack_range": 430.0,
			"description": "Hexblade. A knight who signed the wrong pact: blasts that drag foes in, a curse that makes chickens, eyes that see in the dark.",
			"basic_name": "Eldritch Pull", "basic_damage": 14, "basic_cd": 0.45, "max_hp": 110, "speed": 260.0,
			"bolt_speed": 1100.0, "splash": 0.0, "kindling": false, "combo": false, "finisher_spread": 0, "pull": 25.0,
			"basic_color": Color(0.7, 0.25, 1.0),
			"darkvision": true, "fiend_toll": true,
			"rmb_skill": "cluckcurse", "rmb_text": "A hex bolt: the first foe it touches is a chicken for 1.4 s. No attacks, no skills, no dash.",
			"passive_name": "Devil's Eye", "passive_text": "You see hidden foes within 200 px (Stalk, Smoke Cloud). A kill gives you a 15 HP shield for 5 s (Dark Blessing).",
			"ult_skill": "starving_dark", "ult_cost": 150.0,
			"ult_text": "A sphere of hungry dark for 4 s: foes inside are slowed, take cold damage and miss half their hits."})
	return _pact

## The second secret hero, Six Seven (type "67" on the hero pick, see PlaySettings.seven_unlocked). Not in all().
static var _seven: Hero

static func six_seven() -> Hero:
	if _seven == null:
		all()
		_seven = _clone("wizard", {"id": "sixseven", "display_name": "Six Seven", "units": ["6Mage"], "tint": Color(0.7, 1.15, 1.1),
			"archetype": "Brainrot", "attack_type": "ranged", "attack_range": 467.0,
			"description": "Brainrot. Six... seven. Laggy shots that buffer then hunt, a blink that yells 67 and stuns everyone in earshot, 67 lives, and a server crash for an ult.",
			"basic_spell": "packet_loss", "basic_name": "Packet Loss", "basic_damage": 9, "basic_cd": 0.67, "max_hp": 67, "speed": 267.0,
			"splash": 0.0, "kindling": false, "combo": false, "finisher_spread": 0, "basic_color": Color(0.2, 1.0, 0.9),
			"lives_67": true,
			"rmb_skill": "six_seven", "rmb_text": "Blink up to 267 px toward the cursor and yell SIX SEVEN: everyone around where you land is stunned (confused) for 0.67 s.",
			"passive_name": "67 Lives", "passive_text": "A hit that would kill you leaves you at 67 HP instead, untouchable for 1 s. Once every 67 s (shown on your HUD).",
			"ult_skill": "connection_lost", "ult_cost": 160.0,
			"ult_text": "Everyone around you loses connection: frozen for 1 s. Then your attacks go twice as fast for 3 s."})
	return _seven

## The heroes this machine can pick: all(), plus each secret one once it is unlocked.
static func pickable() -> Array[Hero]:
	var out: Array[Hero] = all().duplicate()
	PlaySettings.load_once()
	if PlaySettings.pact_unlocked:
		out.append(secret())
	if PlaySettings.seven_unlocked:
		out.append(six_seven())
	return out

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
## LMB Bonk and RMB Hook are always there; a weapon drop replaces the Bonk for a while. The passive and the ult start
## empty and are filled by passive / ult drops (FsLoot), each Player on its own Hero copy, lost on death.
## Not in all(): it is never offered on the hero pick screen and Classic bots never use it.
static var _bonker: Hero

static func bonker() -> Hero:
	if _bonker == null:
		_bonker = _make({"id": "bonker", "display_name": "Bonker", "units": ["4Paladin", "1Knight", "7DeathKnight", "8DarkLord"], "attack_type": "melee", "attack_range": 95.0,
			"description": "Everyone's the same. A short bonk and a hook; weapons, passives and ults come from the drops.",
			"basic_name": "Bonk", "basic_damage": 9, "max_hp": 110, "speed": 265.0, "finisher_mult": 1.4,
			"basic_cd": 0.4, "arc_angle": 2.0,
			"rmb_skill": "hook", "rmb_text": "Throw a hook: the first foe it touches is dragged to you and stunned."})
	return _bonker

static func by_id(hero_id: String) -> Hero:
	if hero_id == "bonker":
		return bonker()
	if hero_id == "pactknight":
		return secret()
	if hero_id == "sixseven":
		return six_seven()
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
	s.chaos_cleave_fx = id == "chaoslord"
	s.knight_cleave_fx = id == "knight"
	s.rogue_stab_art = id == "rogue"
	s.might = might
	s.focus_hits = focus_hits
	s.crit_mult = crit_mult
	s.homing = homing
	s.chaos_lo = chaos_lo
	s.chaos_hi = chaos_hi
	s.impetus = impetus
	s.pull = pull
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
		"rebound_shield": return ReboundShield.new()
		"keel_slam": return KeelSlam.new()
		"ebb_and_flow": return EbbAndFlow.new()
		"wild_orb": return WildOrb.new()
		"fault_line": return FaultLine.new()
		"mirror_torment": return MirrorTorment.new()
		"fiendform": return Fiendform.new()
		"rift_bolt": return RiftBolt.new()
		"stillwake": return Stillwake.new()
		"cluckcurse": return Cluckcurse.new()
		"starving_dark": return StarvingDark.new()
		"packet_loss": return PacketLoss.new()
		"rubber_band": return RubberBand.new()   # Six Seven's first RMB; kept for A/B
		"six_seven": return SixSeven.new()
		"connection_lost": return ConnectionLost.new()
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
	var stride_fps := 29.0 if id == "rogue" else 24.0
	var anims := {"idle": [d + "Idle.png", 15, 12.0], "run": [d + "Run.png", 15, stride_fps],
		"cast": [d + hit + ".png", 15, 30.0, false], "cast2": [d + hit2 + ".png", 15, 30.0, false]}
	if id == "rogue":
		anims.erase("cast2")
	if id == "knight":
		anims["cast"] = [KnightFx.ART + "CleaveOpening.png", 15, 30.0, false]
		anims["cast2"] = [KnightFx.ART + "CleaveReturn.png", 15, 30.0, false]
		anims["cast_finisher"] = [KnightFx.ART + "CleaveFinisher.png", 15, 30.0, false]
	if skill_anims or id in ["knight", "rogue"]:
		var release_frame := 4 if id == "knight" else 0
		anims["skill"] = [d + "CastSpell.png", 15, 30.0, false, release_frame]
		var ult_pose := "ShieldBlockStart" if ult_skill == "guardian_angel" else "Special1"
		anims["ult"] = [d + ult_pose + ".png", 15, 30.0, false]
	for a: String in Player.RUN_ANIMS:   # backpedal / strafe sheets; a unit without one falls back to "run" (Player._run_anim)
		if not anims.has(a) and ResourceLoader.exists(d + Player.RUN_SHEETS[a]):
			anims[a] = [d + Player.RUN_SHEETS[a], 15, stride_fps]
	return SheetFrames.build_dirs(anims)

## Facing the camera (south).
func frames(color: String) -> SpriteFrames:
	return dir_frames(color)[1]

## First idle frame, for the hero-select cards.
func portrait(color: String) -> Texture2D:
	return frames(color).get_frame_texture("idle", 0)
