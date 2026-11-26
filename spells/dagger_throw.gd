class_name DaggerThrow extends Spell
## Shade basic: a short-range thrown dagger at the foe near the cursor (homing on a locked foe), no slow.
## Focus (Shade passive): every focus_hits-th throw in a row at the same target is a crit_mult crit. The target is
## counted when the dagger is thrown (the lock, or the foe nearest the aim), so every peer counts the same. No dice.

const SPEED := 1150.0
const PICK_RADIUS := 150.0
const COLOR := Color(0.3, 1.0, 0.55)
const CRIT_COLOR := Color(0.9, 1.0, 0.5)

var range_px := 330.0
var focus_hits := 4
var crit_mult := 2.5
var _focus_target: Node = null
var _focus := 0

func _init() -> void:
	display_name = "Dagger"
	cooldown = 0.4
	damage = 9
	sfx = "shoot"
	cast_pitch = 1.6

## Focus: one more throw at `e`. Returns the damage multiplier: crit_mult on the focus_hits-th in a row at the same
## target (then it starts over), 1 otherwise. Null or a new target starts the count again.
func focus_mult(e: Node) -> float:
	if focus_hits <= 0 or e == null:
		_focus_target = null
		_focus = 0
		return 1.0
	if e != _focus_target:
		_focus_target = e
		_focus = 0
	_focus += 1
	if _focus >= focus_hits:
		_focus = 0
		return crit_mult
	return 1.0

func prime_focus(e: Node) -> void:
	_focus_target = e
	_focus = focus_hits - 1

func focus_count() -> int:
	return _focus

func reach() -> float:
	return range_px

func target(caster: Node2D, aim_pos: Vector2, dir: Vector2) -> Node2D:
	if caster.get("ai"):
		return null
	return Spell.pick_foe(caster, aim_pos, dir, PICK_RADIUS, 0.4, range_px)

func aim(caster: Node2D, dir: Vector2) -> Vector2:
	return Spell.assist_dir(caster, dir, 0.4, range_px, 0.0 if caster.get("ai") else SPEED)

func cast(caster: Node2D, aim_dir: Vector2, aim_pos: Vector2) -> float:
	var d := aim_dir.normalized() if aim_dir != Vector2.ZERO else Vector2.RIGHT
	var at: Node2D = lock if is_instance_valid(lock) else Spell.pick_foe(caster, aim_pos, d, PICK_RADIUS, 0.4, range_px)
	var crit := focus_mult(at)
	var p := Projectile.new().setup(caster.global_position + d * 26.0 + Vector2(0, 8), d * SPEED, roundi(damage * crit), true, caster)
	p.radius = 12.0
	p.life = range_px / SPEED
	p.color = CRIT_COLOR if crit > 1.0 else COLOR
	p.trail = 90.0 if crit > 1.0 else 40.0
	if crit > 1.0:
		p.tex_scale = 1.4
		p.impact_scale = 0.3
		if caster.has_method("float_text"):
			caster.float_text("CRIT", CRIT_COLOR, 20)
	if lock:
		p.target = lock
		p.life *= 1.3
	caster.get_tree().current_scene.add_child(p)
	return cooldown
