class_name EmberField extends Spell
## Mage right click: marks a patch of ground at the cursor. After a short telegraph it erupts (damage + knockback away from
## the centre, which peels melee off you), then smoulders for a few seconds, slowing and burning anyone inside.
## Standing it on a pickup denies the pickup. Never hurts its caster.

const MAX_RANGE := 460.0
const RADIUS := 125.0
const DELAY := 0.6
const LINGER := 3.5
const SLOW := 0.55          ## move speed multiplier inside the field
const TICK := 0.5
const TICK_DAMAGE := 4
const SHOVE := 520.0

class Zone extends Node2D:
	var caster: Node2D
	var dmg := 16
	var _age := 0.0
	var _boomed := false
	var _tick := 0.0

	func _ready() -> void:
		add_to_group("zones")   # bots keep out of enemy fields

	func _physics_process(delta: float) -> void:
		_age += delta
		if not _boomed and _age >= DELAY:
			_boomed = true
			_burst()
		elif _boomed:
			_tick -= delta
			var tick := _tick <= 0.0
			if tick:
				_tick = TICK
			for e in inside():
				if e.has_method("apply_slow") and (e.owns() if e.has_method("owns") else false):
					e.apply_slow(SLOW, 0.25)
				if tick:
					e.take_damage(TICK_DAMAGE, global_position, true, caster)
		if _age >= DELAY + LINGER:
			queue_free()
		queue_redraw()

	func inside() -> Array[Node2D]:
		var out: Array[Node2D] = []
		if not is_instance_valid(caster):
			return out
		for e in Spell.foes(caster):
			if e.global_position.distance_to(global_position) <= RADIUS + 14.0:
				out.append(e)
		return out

	func _burst() -> void:
		Sfx.play("explosion", global_position)
		SheetFrames.play_once(get_parent(), global_position, "res://assets/tiny_swords/fx/Explosion_02.png", 10, 22.0, RADIUS / 60.0)
		var cam := get_tree().get_first_node_in_group("camera") as GameCamera
		if cam:
			cam.shake(0.25)
		for e in inside():
			var away: Vector2 = (e.global_position - global_position).normalized()
			if away == Vector2.ZERO:
				away = Vector2.RIGHT
			e.take_damage(dmg, global_position, false, caster)
			Spell.shove(e, away * SHOVE)

	func _draw() -> void:
		if not _boomed:
			var grow := clampf(_age / DELAY, 0.0, 1.0)
			draw_circle(Vector2.ZERO, RADIUS, Color(1, 0.4, 0.1, 0.1 + 0.12 * grow))
			draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 48, Color(1, 0.55, 0.1, 0.9), 3.0)
			draw_arc(Vector2.ZERO, RADIUS * grow, 0.0, TAU, 48, Color(1, 0.8, 0.3, 0.7), 2.0)
			return
		var left := 1.0 - clampf((_age - DELAY) / LINGER, 0.0, 1.0)
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
		draw_circle(Vector2.ZERO, RADIUS, Color(0.9, 0.3, 0.1, (0.12 + 0.08 * pulse) * left))
		draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 48, Color(1, 0.5, 0.1, 0.8 * left), 3.0)

func _init() -> void:
	display_name = "Ember Field"
	cooldown = 7.0
	damage = 16
	sfx = "shoot"

func cast(caster: Node2D, _aim_dir: Vector2, aim_pos: Vector2) -> float:
	var z := Zone.new()
	z.caster = caster
	z.dmg = damage
	z.position = caster.global_position + (aim_pos - caster.global_position).limit_length(MAX_RANGE)
	z.z_index = -1
	caster.get_tree().current_scene.add_child(z)
	return cooldown
