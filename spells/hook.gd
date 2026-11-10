class_name Hook extends Spell
## Bonker right click (Pudge's hook): throws a chain along the aim. The first foe it touches is dragged back to you and
## stunned for a moment, so you get your bonks in. Rocks stop the chain; a dash or a phase slips it.

const SPEED := 1100.0
const RANGE := 460.0
const RADIUS := 26.0
const STUN := 0.7
const STOP := 70.0   ## the victim ends up about this far in front of you

class Chain extends Node2D:
	var caster: Node2D
	var dir := Vector2.RIGHT
	var dmg := 6
	var _len := 0.0

	func _physics_process(delta: float) -> void:
		if not is_instance_valid(caster) or caster.down:
			queue_free()
			return
		position = caster.global_position + Vector2(0, 8)
		var step := SPEED * delta
		if _len >= RANGE or Spell.solid_ahead(caster, position + dir * _len, dir, step):
			queue_free()
			return
		_len += step
		var tip := position + dir * _len
		for e in Spell.foes(caster):
			if e.global_position.distance_to(tip) > RADIUS + 14.0:
				continue
			# hit "from behind" the victim, so the hit's own knockback also points at the caster
			if e.take_damage(dmg, e.global_position + dir * 10.0, false, caster):
				Spell.stun(e, STUN)
				var gap := e.global_position.distance_to(position) - STOP
				if gap > 0.0:   # launch speed whose slide (v^2 / 2 decel) ends STOP px in front of the caster
					Spell.shove(e, (position - e.global_position).normalized() * sqrt(2.0 * Player.KNOCK_DECEL * gap))
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		draw_line(dir * 24.0, dir * _len, Color(0.75, 0.75, 0.8), 4.0)
		draw_circle(dir * _len, 9.0, Color(0.9, 0.9, 0.95))
		draw_arc(dir * _len, 9.0, 0.0, TAU, 16, Color(0.25, 0.25, 0.3), 2.0)

func _init() -> void:
	display_name = "Hook"
	cooldown = 5.0
	damage = 6
	sfx = "dash"
	cast_pitch = 0.7   # a chain, not a dash

func aim(caster: Node2D, dir: Vector2) -> Vector2:
	return Spell.assist_dir(caster, dir, 0.3, RANGE, 0.0 if caster.get("ai") else SPEED)

func cast(caster: Node2D, aim_dir: Vector2, _aim_pos: Vector2) -> float:
	var c := Chain.new()
	c.caster = caster
	c.dir = aim_dir.normalized()
	c.dmg = damage
	c.z_index = 5
	c.position = caster.global_position + Vector2(0, 8)
	caster.get_tree().current_scene.add_child(c)
	return cooldown
