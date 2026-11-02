class_name SnipeShot extends Spell
## Ranger right click: take aim for CHARGE seconds (slowed, with a laser showing the line), then loose one heavy arrow.
## The line is locked when you press, so it can be sidestepped; anything it hits is launched, which is how you ring foes out.

const ARROW := "res://assets/tiny_swords/units/Blue/Archer/Arrow.png"
const SPEED := 1700.0
const CHARGE := 0.6
const LENGTH := 1100.0
const SHOVE := 1100.0
const SLOW := 0.3

class Aim extends Node2D:
	var caster: Node2D
	var dir := Vector2.RIGHT
	var dmg := 40
	var _age := 0.0

	func _physics_process(delta: float) -> void:
		_age += delta
		if not is_instance_valid(caster) or caster.down:
			queue_free()
			return
		position = caster.global_position + Vector2(0, 8)
		if caster.has_method("apply_slow"):
			caster.apply_slow(SLOW, 0.1)
		if _age >= CHARGE:
			var p := Projectile.new().setup(position + dir * 30.0, dir * SPEED, dmg, true, caster)
			p.arrow_tex = ARROW
			p.pierce = 1
			p.life = LENGTH / SPEED
			p.radius = 12.0
			p.shove = SHOVE
			caster.get_tree().current_scene.add_child(p)
			Sfx.play("shoot", position)
			queue_free()
		queue_redraw()

	func _draw() -> void:
		var t := clampf(_age / CHARGE, 0.0, 1.0)
		draw_line(dir * 30.0, dir * LENGTH, Color(1.0, 0.3, 0.2, 0.15 + 0.5 * t), 1.0 + 5.0 * t)
		draw_arc(Vector2.ZERO, 34.0, 0.0, TAU * t, 24, Color(1.0, 0.8, 0.3, 0.9), 3.0)

func _init() -> void:
	display_name = "Snipe Shot"
	cooldown = 7.0
	damage = 40
	sfx = "shoot"

func cast(caster: Node2D, aim_dir: Vector2, _aim_pos: Vector2) -> float:
	var a := Aim.new()
	a.caster = caster
	a.dir = aim_dir.normalized()
	a.dmg = damage
	a.z_index = 5
	caster.get_tree().current_scene.add_child(a)
	return cooldown
