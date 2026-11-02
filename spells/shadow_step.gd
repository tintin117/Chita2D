class_name ShadowStep extends Spell
## Rogue right click: blink to the foe nearest the cursor and land behind its back (so the next stabs are backstabs),
## or just a short hop toward the cursor if nobody is there. Untargetable for PHASE seconds. Deals no damage by itself.

const MAX_RANGE := 430.0       ## farthest foe it can reach
const PICK_RADIUS := 220.0     ## how close to the cursor a foe has to be to be chosen
const HOP := 300.0             ## blink length with no target
const BEHIND := 62.0
const PHASE := 0.45

## Where the blink lands (before obstacle / water checks). Pure given the foes, so owner and tests agree.
static func destination(from: Vector2, aim_pos: Vector2, foes: Array[Node2D]) -> Vector2:
	var best: Node2D = null
	var best_d := PICK_RADIUS
	for e in foes:
		var d := e.global_position.distance_to(aim_pos)
		if d < best_d and e.global_position.distance_to(from) <= MAX_RANGE:
			best_d = d
			best = e
	if best == null:
		return from + (aim_pos - from).limit_length(HOP)
	var facing: Vector2 = best.aim_dir if "aim_dir" in best else (best.global_position - from).normalized()
	return best.global_position - facing.normalized() * BEHIND

func _init() -> void:
	display_name = "Shadow Step"
	cooldown = 5.5
	damage = 0
	sfx = "dash"

func cast(caster: Node2D, _aim_dir: Vector2, aim_pos: Vector2) -> float:
	var from := caster.global_position
	var dust := "res://assets/tiny_swords/fx/Dust_01.png"
	SheetFrames.play_once(caster.get_parent(), from + Vector2(0, 20), dust, 8, 24.0, 1.0).modulate = Color(0.6, 0.45, 0.9)
	caster.phase(PHASE)
	if caster.owns():   # only the owner moves it; everyone else sees it arrive through the replicated position
		caster.blink_to(destination(from, aim_pos, Spell.foes(caster)))
	SheetFrames.play_once(caster.get_parent(), caster.global_position + Vector2(0, 20), dust, 8, 24.0, 1.0).modulate = Color(0.6, 0.45, 0.9)
	return cooldown
