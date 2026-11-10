class_name Shove extends Spell
## Bonker right click: a short, wide shockwave that slams every foe in front of you away (a little damage, a lot of launch).
## It does the least damage of any skill; its job is to put people in the water and off the loot.

const REACH := 150.0
const HALF_ANGLE := 0.85    ## radians either side of the aim
const LAUNCH := 1250.0

class Wave extends Node2D:
	var caster: Node2D
	var dir := Vector2.RIGHT
	var dmg := 4
	var _age := 0.0
	var _hit: Array[Node] = []

	func _physics_process(delta: float) -> void:
		_age += delta
		if not is_instance_valid(caster) or caster.down:
			queue_free()
			return
		position = caster.global_position + Vector2(0, 8)
		if _age > 0.12:
			return
		for e in Spell.foes(caster):
			var off := e.global_position - position
			if e in _hit or off.length() > REACH + 20.0:
				continue
			if off.length() < 30.0 or absf(dir.angle_to(off)) <= HALF_ANGLE:
				_hit.append(e)
				e.take_damage(dmg, position, false, caster)
				Spell.shove(e, off.normalized() * LAUNCH)
				Sfx.play("hit_big", position)

	func _process(_delta: float) -> void:
		if _age >= 0.3:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		var k := clampf(_age / 0.25, 0.0, 1.0)
		var r := REACH * (0.35 + 0.65 * k)
		var base := dir.angle() - HALF_ANGLE
		for ring in 3:
			var rr := r - ring * 16.0
			if rr > 10.0:
				draw_arc(Vector2.ZERO, rr, base, base + HALF_ANGLE * 2.0, 24, Color(0.9, 0.95, 1.0, (1.0 - k) * (0.9 - ring * 0.25)), 5.0 - ring)

func _init() -> void:
	display_name = "Shove"
	cooldown = 3.5
	damage = 4
	sfx = "dash"

func aim(caster: Node2D, dir: Vector2) -> Vector2:
	return Spell.assist_dir(caster, dir, 0.3, REACH + 40.0)

func cast(caster: Node2D, aim_dir: Vector2, _aim_pos: Vector2) -> float:
	var w := Wave.new()
	w.caster = caster
	w.dir = aim_dir.normalized()
	w.dmg = damage
	w.z_index = 5
	w.position = caster.global_position + Vector2(0, 8)
	caster.get_tree().current_scene.add_child(w)
	return cooldown
