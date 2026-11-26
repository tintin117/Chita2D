class_name BladeWall extends Spell
## Shade ult: raise a wall of spinning blades at the cursor (up to MAX_RANGE), LENGTH long, across the line from the
## Shade to that spot. For DURATION seconds anyone touching it takes a hit every TICK and is slowed: cut off an escape,
## split a fight, or pin someone between the wall and the water. Silent hits, so it does not bounce people through.
## Always fires: it is a zone, not a target.

const MAX_RANGE := 450.0
const LENGTH := 340.0
const THICK := 34.0          ## how close to the line counts as touching
const DURATION := 4.0
const TICK := 0.25
const SLOW := Vector2(0.5, 0.35)
const STEEL := Color(0.75, 1.0, 0.85)

## The wall's ends for a cast from `from` aimed at `aim_pos`: centred on the spot, across the line of sight.
static func ends(from: Vector2, aim_pos: Vector2) -> PackedVector2Array:
	var at := from + (aim_pos - from).limit_length(MAX_RANGE)
	var d := (at - from).normalized() if at.distance_to(from) > 1.0 else Vector2.RIGHT
	var across := d.orthogonal() * LENGTH / 2.0
	return PackedVector2Array([at - across, at + across])

## True if `pos` touches the wall a -> b.
static func touching(a: Vector2, b: Vector2, pos: Vector2) -> bool:
	var seg := b - a
	var t := clampf((pos - a).dot(seg) / maxf(seg.length_squared(), 1.0), 0.0, 1.0)
	return pos.distance_to(a + seg * t) <= THICK + 14.0

class Wall extends Node2D:
	var caster: Node2D
	var a := Vector2.ZERO   ## world ends
	var b := Vector2.ZERO
	var dmg := 7
	var _age := 0.0
	var _next := 0.0

	func _ready() -> void:
		z_index = 4
		add_to_group("zones")   # bots keep out of it

	func _physics_process(delta: float) -> void:
		_age += delta
		if _age >= DURATION:
			queue_free()
			return
		if _age >= _next and is_instance_valid(caster):
			_next += TICK
			for e in Spell.foes(caster):
				if BladeWall.touching(a, b, e.global_position) and e.take_damage(dmg, e.global_position, true, caster):
					if e.has_method("apply_slow"):
						e.apply_slow(SLOW.x, SLOW.y)
		queue_redraw()

	func _draw() -> void:
		var la := to_local(a)
		var lb := to_local(b)
		var fade := clampf(_age / 0.15, 0.0, 1.0) * clampf((DURATION - _age) / 0.3, 0.0, 1.0)
		draw_line(la, lb, Color(STEEL, 0.18 * fade), THICK * 2.0)
		draw_line(la, lb, Color(STEEL, 0.8 * fade), 3.0)
		var n := 9
		for i in n:   # the spinning blades along it
			var c := la.lerp(lb, (i + 0.5) / n)
			var spin := _age * 14.0 + i
			for k in 3:
				var ang := spin + k * TAU / 3.0
				draw_line(c, c + Vector2.from_angle(ang) * 20.0, Color(1, 1, 1, 0.85 * fade), 3.0)
			draw_circle(c, 4.0, Color(STEEL, fade))

func _init() -> void:
	display_name = "Blade Wall"
	cooldown = 0.6     # the charge is the real gate; this only covers the cast lock
	damage = 7
	sfx = "swing"
	cast_pitch = 0.8

func cast(caster: Node2D, _aim_dir: Vector2, aim_pos: Vector2) -> float:
	var e := ends(caster.global_position, aim_pos)
	var w := Wall.new()
	w.caster = caster
	w.a = e[0]
	w.b = e[1]
	w.dmg = damage
	w.position = (e[0] + e[1]) / 2.0
	caster.get_parent().add_child(w)
	return cooldown
