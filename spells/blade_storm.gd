class_name BladeStorm extends Spell
## Knight signature: a spinning storm of blades around you for ~1.5s. You keep moving while it chews through enemies.

const DURATION := 1.5
const TICK := 0.12
const RADIUS := 135.0

class Spin extends Node2D:
	var caster: Node2D
	var dmg := 10
	var left := DURATION
	var _next := 0.0

	func _physics_process(delta: float) -> void:
		left -= delta
		_next -= delta
		if not is_instance_valid(caster):
			queue_free()
			return
		if _next <= 0.0:
			_next = TICK
			var pos := caster.global_position + Vector2(0, 14)
			for e: Node2D in get_tree().get_nodes_in_group("enemies"):
				if e.global_position.distance_to(pos) <= RADIUS + 16.0:
					e.take_damage(dmg, pos, true)
					if e.kind != "boss":
						e.knock += (e.global_position - pos).normalized() * 25.0   # a gentle shove, enemies stay in the storm
		if left <= 0.0:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		var t := Time.get_ticks_msec() / 1000.0
		draw_circle(Vector2.ZERO, RADIUS, Color(1.0, 0.45, 0.1, 0.1))
		for i in 3:
			var a := t * 12.0 + i * TAU / 3.0
			draw_arc(Vector2.ZERO, RADIUS, a, a + 1.4, 14, Color(1.0, 0.6, 0.2, 0.9), 6.0)
		draw_arc(Vector2.ZERO, RADIUS * 0.6, -t * 15.0, -t * 15.0 + 3.2, 14, Color(1, 1, 1, 0.6), 3.0)

func _init() -> void:
	display_name = "Blade Storm"
	cooldown = 0.5
	damage = 10
	charge_cost = 100.0

func cast(caster: Node2D, _aim_dir: Vector2, _aim_pos: Vector2) -> float:
	var s := Spin.new()
	s.caster = caster
	s.dmg = damage
	s.position = Vector2(0, 14)
	s.z_index = 5
	caster.add_child(s)   # follows the knight; ticks never refill the signature meter
	return cooldown
