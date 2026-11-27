class_name FocusFire extends Spell
## Ranger ult (Windranger): pick the foe nearest the cursor. For DURATION seconds the Ranger's basic auto-fires at it,
## RATE times as fast, each arrow DAMAGE_MULT as hard (Player.focus_fire_on / _try_focus_fire). You can still walk,
## dodge and use Power Shot; the arrows only fly while it is in range. Losing it (death, out of range) pauses the
## fire. Only fires with a foe to focus (an ult with nobody in reach keeps its charge).

const DURATION := 4.0
const RATE := 3.0
const DAMAGE_MULT := 0.7
const RANGE := 700.0
const PICK_RADIUS := 220.0

func _init() -> void:
	display_name = "Focus Volley"
	cooldown = 0.6     # the charge is the real gate; this only covers the cast lock
	damage = 0
	sfx = "crown"
	cast_pitch = 1.5

func target(caster: Node2D, aim_pos: Vector2, dir: Vector2) -> Node2D:
	return Spell.pick_foe(caster, aim_pos, dir, PICK_RADIUS, 0.4, RANGE)

## Targeted ult: it needs a foe to lock onto. With nobody there the press does nothing and the charge is kept
## ("Nobody in reach"), for players and bots alike.
func can_cast(caster: Node2D, aim_pos: Vector2) -> bool:
	return worth_casting(caster, aim_pos)

## Is there a foe to lock onto?
func worth_casting(caster: Node2D, aim_pos: Vector2) -> bool:
	return target(caster, aim_pos, (aim_pos - caster.global_position).normalized()) != null

func ult_lock() -> float:
	return DURATION + 0.5

func cast(caster: Node2D, _aim_dir: Vector2, _aim_pos: Vector2) -> float:
	if lock and caster.has_method("focus_fire_on"):
		caster.focus_fire_on(lock, DURATION)
		if lock.has_method("float_text"):
			lock.float_text("FOCUSED", Color(1.0, 0.85, 0.4), 20)
	return cooldown
