class_name Progression extends RefCounted
## Per-player XP, level, skill points and skill ranks (player.prog). Pure data, no nodes:
## Player reads the bonuses below and folds them into its stats (Player.recalc_stats).
## Tune everything in the constants.

signal leveled_up(new_level: int)   ## once per add_xp call, with the final level
signal rewarded(kind: String)       ## objective reward granted (see grant_reward)
signal changed                      ## anything a stat or the HUD cares about moved

const LEVEL_CAP := 10
const RANK_CAP := 5
const SLOTS := 4                    ## basic, right click, Q, signature (same order as Player.SLOTS)

const HP_PER_LEVEL := 10
const DAMAGE_PER_LEVEL := 0.04      ## fraction
const SPEED_PER_LEVEL := 0.01       ## fraction
const HP_PER_POWER := 10            ## "power" objective reward stack
const DAMAGE_PER_POWER := 0.06
const XP_REWARD := 60               ## "xp" objective reward
const SKILL_DAMAGE_PER_RANK := 0.15 ## fraction per rank above 1
const SKILL_COOLDOWN_PER_RANK := 0.06

const XP_BY_KIND := {"grunt": 8, "archer": 8, "lancer": 12, "boss": 200}

var level := 1
var xp := 0
var skill_points := 0
var power_stacks := 0
var ranks: Array[int] = [1, 1, 1, 1]

func xp_to_next() -> int:
	return 0 if level >= LEVEL_CAP else roundi(20.0 * pow(level, 1.4))

static func xp_for(kind: String) -> int:
	return XP_BY_KIND.get(kind, 5)

func add_xp(n: int) -> void:
	if level >= LEVEL_CAP or n <= 0:
		return
	xp += n
	var start := level
	while level < LEVEL_CAP and xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		skill_points += 1
	if level >= LEVEL_CAP:
		xp = 0
	changed.emit()  # before leveled_up, so listeners see the new stats
	if level > start:
		leveled_up.emit(level)

## kind: "power" = permanent stat stack, "xp" = bulk XP.
func grant_reward(kind: String) -> void:
	match kind:
		"power": power_stacks += 1
		"xp": add_xp(XP_REWARD)
	changed.emit()
	rewarded.emit(kind)

func can_rank_up(slot: int) -> bool:
	return skill_points > 0 and slot >= 0 and slot < SLOTS and ranks[slot] < RANK_CAP

func rank_up(slot: int) -> bool:
	if not can_rank_up(slot):
		return false
	ranks[slot] += 1
	skill_points -= 1
	changed.emit()
	return true

func hp_bonus() -> int:
	return (level - 1) * HP_PER_LEVEL + power_stacks * HP_PER_POWER

func damage_bonus() -> float:
	return (level - 1) * DAMAGE_PER_LEVEL + power_stacks * DAMAGE_PER_POWER

func speed_bonus() -> float:
	return (level - 1) * SPEED_PER_LEVEL

func skill_damage_mult(slot: int) -> float:
	return 1.0 + (ranks[slot] - 1) * SKILL_DAMAGE_PER_RANK

func skill_cooldown_mult(slot: int) -> float:
	return 1.0 - (ranks[slot] - 1) * SKILL_COOLDOWN_PER_RANK
