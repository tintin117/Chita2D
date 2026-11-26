class_name Shackleshot extends Spell
## Ranger ult (Windranger): fire a shackle arrow toward the cursor. The first foe it hits is stunned: LONG if something
## stands right behind it along the arrow's flight (another foe, a brazier or rock, a wall or a rail, within REACH), and
## that other foe is shackled too; SHORT otherwise. Ults may stun (the stun diet keeps stuns on ults and two RMBs).
## Line them up with a pillar. Only fires with a foe to aim at.

const RANGE := 700.0
const SPEED := 1500.0
const RADIUS := 18.0
const REACH := 260.0          ## how far behind the first foe an anchor counts
const LONG := 2.0
const SHORT := 0.75
const PICK_RADIUS := 240.0
const COLOR := Color(0.85, 0.75, 0.45)

## The second foe a shackle on `first` (flying along `dir`) ties to: the nearest foe behind it within REACH and close to
## the line. Null if none.
static func partner(first: Node2D, dir: Vector2, foes: Array[Node2D]) -> Node2D:
	var best: Node2D = null
	var best_d := REACH
	for e in foes:
		if e == first:
			continue
		var off: Vector2 = e.global_position - first.global_position
		var along := off.dot(dir)
		if along <= 0.0 or along > REACH:
			continue
		if absf(off.dot(dir.orthogonal())) > 70.0:
			continue
		if along < best_d:
			best_d = along
			best = e
	return best

class Arrow extends Node2D:
	var caster: Node2D
	var dir := Vector2.RIGHT
	var dmg := 20
	var _flown := 0.0

	func _physics_process(delta: float) -> void:
		if not is_instance_valid(caster):
			queue_free()
			return
		var step := SPEED * delta
		position += dir * step
		_flown += step
		for e in Spell.foes(caster):
			if e.global_position.distance_to(global_position) <= RADIUS + 22.0:
				_shackle(e)
				queue_free()
				return
		if _flown >= RANGE:
			queue_free()
			return
		queue_redraw()

	func _shackle(e: Node2D) -> void:
		Sfx.play("crown", e.global_position, -2.0, 0.7)
		var other := Shackleshot.partner(e, dir, Spell.foes(caster))
		var anchored := other != null or Spell.solid_ahead(e, e.global_position + Vector2(0, 14), dir, REACH) \
			or _rail_ahead(e, e.global_position + Vector2(0, 14))
		if e.take_damage(dmg, global_position, false, caster):
			Spell.stun(e, LONG if anchored else SHORT)
			if e.has_method("float_text"):
				e.float_text("SHACKLED" if anchored else "STUNNED", COLOR, 22)
		if other and other.take_damage(dmg / 2, e.global_position, false, caster):
			Spell.stun(other, LONG)
		var fx := Tie.new()
		fx.a = e.global_position
		fx.b = other.global_position if other else e.global_position + dir * 90.0
		fx.z_index = 6
		caster.get_parent().add_child(fx)

	## A Colosseum rail behind the foe also anchors the shackle.
	func _rail_ahead(e: Node2D, from: Vector2) -> bool:
		if not e.is_inside_tree():
			return false
		var q := PhysicsRayQueryParameters2D.create(from, from + dir * REACH, Player.LOW_MASK)
		return not e.get_world_2d().direct_space_state.intersect_ray(q).is_empty()

	func _draw() -> void:
		draw_line(Vector2(0, -8) - dir * 60.0, Vector2(0, -8), Color(COLOR, 0.5), 6.0)
		draw_line(Vector2(0, -8) - dir * 30.0, Vector2(0, -8) + dir * 10.0, Color(1, 1, 1, 0.9), 3.0)

class Tie extends Node2D:
	var a := Vector2.ZERO
	var b := Vector2.ZERO
	var _age := 0.0

	func _process(delta: float) -> void:
		_age += delta
		if _age >= LONG:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		var k := 1.0 - _age / LONG
		var pts := PackedVector2Array()
		for i in 9:   # a sagging rope
			var t := i / 8.0
			pts.append(a.lerp(b, t) + Vector2(0, -10 + sin(t * PI) * 14.0))
		draw_polyline(pts, Color(COLOR, 0.9 * k), 3.0)

func _init() -> void:
	display_name = "Shackleshot"
	cooldown = 0.6     # the charge is the real gate; this only covers the cast lock
	damage = 20
	sfx = "shoot"
	cast_pitch = 0.7

## Targeted ult: it needs a foe to lock onto. With nobody there the press does nothing and the charge is kept
## ("Nobody in reach"), for players and bots alike.
func can_cast(caster: Node2D, aim_pos: Vector2) -> bool:
	return worth_casting(caster, aim_pos)

## Is there a foe to lock onto?
func worth_casting(caster: Node2D, aim_pos: Vector2) -> bool:
	return Spell.pick_foe(caster, aim_pos, (aim_pos - caster.global_position).normalized(), PICK_RADIUS, 0.4, RANGE) != null

func cast(caster: Node2D, aim_dir: Vector2, aim_pos: Vector2) -> float:
	var foe := Spell.pick_foe(caster, aim_pos, aim_dir, PICK_RADIUS, 0.4, RANGE)
	var d := (foe.global_position - caster.global_position).normalized() if foe else aim_dir.normalized()
	var a := Arrow.new()
	a.caster = caster
	a.dir = d
	a.dmg = damage
	a.position = caster.global_position + Vector2(0, 8) + d * 30.0
	a.z_index = 6
	caster.get_parent().add_child(a)
	return cooldown
