class_name ArrowBarrage extends Spell
## Ranger signature: ~1.6s of rapid arrows that follow your aim. Arrows pierce one target and never refill the meter.

const DURATION := 1.6
const INTERVAL := 0.08
const ARROW := "res://assets/tiny_swords/units/Blue/Archer/Arrow.png"

class Barrage extends Node:
	var caster: Node2D
	var dmg := 8
	var left := DURATION
	var _next := 0.0

	func _physics_process(delta: float) -> void:
		left -= delta
		_next -= delta
		if not is_instance_valid(caster) or caster.down or left <= 0.0:
			queue_free()
			return
		if _next <= 0.0:
			_next = INTERVAL
			var dir: Vector2 = caster.aim_dir.rotated(randf_range(-0.1, 0.1))
			var p := Projectile.new().setup(caster.global_position + dir * 30.0 + Vector2(0, 8), dir * 1000.0, dmg, true)
			p.arrow_tex = ARROW
			p.silent = true
			p.pierce = 1
			p.life = 0.8
			p.radius = 8.0
			get_tree().current_scene.add_child(p)

func _init() -> void:
	display_name = "Arrow Barrage"
	cooldown = 0.5
	damage = 8
	charge_cost = 100.0

func cast(caster: Node2D, _aim_dir: Vector2, _aim_pos: Vector2) -> float:
	var b := Barrage.new()
	b.caster = caster
	b.dmg = damage
	caster.get_tree().current_scene.add_child(b)
	return cooldown
