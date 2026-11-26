class_name Purification extends Spell
## Paladin right click: a burst of holy light around you. You heal HEAL, and every foe within RADIUS takes the same
## amount. Health and damage in one button: use it hurt in a crowd and it swings the fight both ways.

const RADIUS := 150.0
const HEAL := 30
const HOLY := Color(1.0, 0.92, 0.55)

## Foes the burst at `at` reaches.
static func caught(at: Vector2, foes: Array[Node2D]) -> Array[Node2D]:
	var out: Array[Node2D] = []
	for e in foes:
		if e.global_position.distance_to(at) <= RADIUS + 14.0:
			out.append(e)
	return out

class Flash extends Node2D:
	var _age := 0.0

	func _process(delta: float) -> void:
		_age += delta
		if _age >= 0.45:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		var k := clampf(_age / 0.45, 0.0, 1.0)
		draw_circle(Vector2(0, 14), Purification.RADIUS * (0.4 + 0.6 * k), Color(HOLY, 0.35 * (1.0 - k)))
		draw_arc(Vector2(0, 14), Purification.RADIUS * (0.4 + 0.6 * k), 0.0, TAU, 40, Color(1, 1, 1, 1.0 - k), 5.0 * (1.0 - k) + 1.0)
		for i in 8:   # rays
			var a := TAU * i / 8.0 + k
			draw_line(Vector2(0, -20), Vector2(0, -20) + Vector2.from_angle(a) * 90.0 * k, Color(HOLY, 0.7 * (1.0 - k)), 3.0)

func _init() -> void:
	display_name = "Purification"
	cooldown = 8.0
	damage = HEAL
	sfx = "crown"
	cast_pitch = 1.4

func cast(caster: Node2D, _aim_dir: Vector2, _aim_pos: Vector2) -> float:
	var at := caster.global_position
	var f := Flash.new()
	f.position = at
	f.z_index = 4
	caster.get_parent().add_child(f)
	if caster.owns() and caster.has_method("heal") and not caster.down:   # the caster's own HP is its owner's call
		caster.heal(damage)
		caster.float_text("+%d" % damage, Color(0.5, 1.0, 0.5), 20)
		if caster.online and caster.is_inside_tree():
			caster._net_hp.rpc(caster.hp)
	for e in caught(at, Spell.foes(caster)):
		e.take_damage(damage, at, false, caster)
	return cooldown
