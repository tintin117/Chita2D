class_name BladeRing extends Spell
## Shade ult: a small ring of spinning blades orbits the Shade for DURATION seconds and moves with him. Every TICK,
## every foe within RADIUS takes a hit and is slowed. Unlike the old Blade Fury spin, the Shade keeps throwing
## daggers the whole time: walk the ring into them and keep Focus going. Silent hits: they stay close.
## Always casts; bots only start it with a foe within REACH (worth_casting).

const RADIUS := 120.0
const REACH := 220.0
const DURATION := 3.5
const TICK := 0.25
const SLOW := Vector2(0.55, 0.4)
const STEEL := Color(0.75, 1.0, 0.85)

## True if `pos` is inside the ring round `at`.
static func in_ring(at: Vector2, pos: Vector2) -> bool:
	return pos.distance_to(at) <= RADIUS + 14.0

class Ring extends Node2D:
	var caster: Node2D
	var dmg := 7
	var _age := 0.0
	var _next := 0.0

	func _ready() -> void:
		z_index = 4

	func _physics_process(delta: float) -> void:
		_age += delta
		if _age >= DURATION or not is_instance_valid(caster) or caster.down:
			queue_free()
			return
		global_position = caster.global_position
		if _age >= _next:
			_next += TICK
			for e in Spell.foes(caster):
				if BladeRing.in_ring(global_position, e.global_position) and e.take_damage(dmg, e.global_position, true, caster):
					if e.has_method("apply_slow"):
						e.apply_slow(SLOW.x, SLOW.y)
		queue_redraw()

	func _draw() -> void:
		var fade := clampf(_age / 0.15, 0.0, 1.0) * clampf((DURATION - _age) / 0.3, 0.0, 1.0)
		var c0 := Vector2(0, 6)
		draw_circle(c0, RADIUS, Color(STEEL, 0.08 * fade))
		draw_arc(c0, RADIUS, 0.0, TAU, 48, Color(STEEL, 0.6 * fade), 2.0)
		var n := 8
		for i in n:   # the blades, orbiting fast
			var a := TAU * i / n + _age * 5.0
			var c := c0 + Vector2.from_angle(a) * RADIUS * 0.85
			var tang := Vector2.from_angle(a + PI / 2.0)
			draw_line(c - tang * 16.0, c + tang * 16.0, Color(1, 1, 1, 0.9 * fade), 4.0)
			draw_line(c - tang * 16.0, c + tang * 16.0, Color(STEEL, 0.9 * fade), 2.0)

func _init() -> void:
	display_name = "Blade Ring"
	cooldown = 0.6     # the charge is the real gate; this only covers the cast lock
	damage = 7
	sfx = "swing"
	cast_pitch = 0.8

func ult_lock() -> float:
	return DURATION + 0.5

## Bots only: is anyone there to make it worth spending the charge? (Players can always cast it.)
func worth_casting(caster: Node2D, _aim_pos: Vector2) -> bool:
	for e in Spell.foes(caster):
		if e.global_position.distance_to(caster.global_position) <= REACH:
			return true
	return false

func cast(caster: Node2D, _aim_dir: Vector2, _aim_pos: Vector2) -> float:
	var r := Ring.new()
	r.caster = caster
	r.dmg = damage
	caster.get_parent().add_child(r)
	return cooldown
