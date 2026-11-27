class_name Assassinate extends Spell
## Scout ult: lock onto the foe nearest the cursor within RANGE. A red laser joins you for AIM seconds (everyone sees it),
## then the shot lands for `damage`, EXECUTE_MULT of it on a foe under EXECUTE_HP of its health. A dash or a phase at
## the right moment makes it miss: the laser is the counterplay. The Scout is rooted while aiming (can turn, cannot walk
## or dash), so the shot is a commitment. Being stunned or killed while aiming cancels it.
## Only fires with a foe to lock onto (an ult with nobody in reach keeps its charge).

const RANGE := 950.0
const PICK_RADIUS := 220.0
const AIM := 1.0
const EXECUTE_HP := 0.4
const EXECUTE_MULT := 1.5
const LASER := Color(1.0, 0.25, 0.2)

## The foe the shot locks onto, or null.
static func pick(caster: Node2D, aim_pos: Vector2, dir: Vector2) -> Node2D:
	return Spell.pick_foe(caster, aim_pos, dir, PICK_RADIUS, 0.35, RANGE)

## Damage on a foe at `hp_frac` of its health.
static func shot_damage(base: int, hp_frac: float) -> int:
	return roundi(base * (EXECUTE_MULT if hp_frac < EXECUTE_HP else 1.0))

class Lock extends Node2D:
	var caster: Node2D
	var victim: Node2D
	var dmg := 55
	var _age := 0.0
	var _fired := false

	func _ready() -> void:
		z_index = 7
		if victim.has_method("float_text"):
			victim.float_text("TARGETED", LASER, 22)

	func _physics_process(delta: float) -> void:
		_age += delta
		if not is_instance_valid(caster) or caster.down or not is_instance_valid(victim) or victim.down:
			queue_free()
			return
		if caster.has_method("stunned") and caster.stunned():   # knocked out of the aim
			queue_free()
			return
		if not _fired and _age >= AIM:
			_fired = true
			_fire()
		if _age >= AIM + 0.25:
			queue_free()
		queue_redraw()

	func _fire() -> void:
		Sfx.play("bomb_boom", caster.global_position, -4.0, 1.6)
		var v := victim
		if v.has_method("dodging") and v.dodging():
			if v.has_method("float_text"):
				v.float_text("DODGED", Color(0.8, 0.9, 1.0), 20)
			return
		var frac: float = float(v.hp) / maxf(v.max_hp, 1.0) if "hp" in v else 1.0
		v.take_damage(Assassinate.shot_damage(dmg, frac), caster.global_position, false, caster)

	func _draw() -> void:
		var a: Vector2 = to_local(caster.global_position + Vector2(0, -20))
		var b: Vector2 = to_local(victim.global_position + Vector2(0, -10))
		if not _fired:
			var k := clampf(_age / AIM, 0.0, 1.0)
			draw_line(a, b, Color(LASER, 0.25 + 0.6 * k), 1.0 + 3.0 * k)
			draw_arc(b, 40.0 - 22.0 * k, 0.0, TAU, 24, Color(LASER, 0.9), 2.0 + 2.0 * k)
			draw_line(b + Vector2(-26, 0), b + Vector2(26, 0), Color(LASER, 0.8), 2.0)
			draw_line(b + Vector2(0, -26), b + Vector2(0, 26), Color(LASER, 0.8), 2.0)
		else:
			var k := 1.0 - clampf((_age - AIM) / 0.25, 0.0, 1.0)
			draw_line(a, b, Color(1, 0.9, 0.6, k), 10.0 * k + 1.0)

func _init() -> void:
	display_name = "Assassin Shot"
	cooldown = 0.6     # the charge is the real gate; this only covers the cast lock
	damage = 55
	sfx = "shoot"
	cast_pitch = 0.6

func ult_lock() -> float:
	return AIM + 0.5

## Targeted ult: it needs a foe to lock onto. With nobody there the press does nothing and the charge is kept
## ("Nobody in reach"), for players and bots alike.
func can_cast(caster: Node2D, aim_pos: Vector2) -> bool:
	return worth_casting(caster, aim_pos)

## Is there a foe to lock onto?
func worth_casting(caster: Node2D, aim_pos: Vector2) -> bool:
	return pick(caster, aim_pos, (aim_pos - caster.global_position).normalized()) != null

func cast(caster: Node2D, aim_dir: Vector2, aim_pos: Vector2) -> float:
	var v := pick(caster, aim_pos, aim_dir)
	if v == null:
		return cooldown   # can_cast stops this; a foe that left in the same frame just wastes the press
	if caster.has_method("root"):
		caster.root(AIM)
	var l := Lock.new()
	l.caster = caster
	l.victim = v
	l.dmg = damage
	caster.get_parent().add_child(l)
	return cooldown
