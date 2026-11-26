class_name Meteor extends Spell
## Mage ult: calls a meteor down on the cursor. A big circle and a falling shadow show where for DELAY seconds, then the
## impact hits everyone inside hard and LAUNCHES them outward: the Mage's ring-out tool (knockback already grows as HP
## drops, so a hurt foe near the shore goes for a swim). No stun: the 1 s telegraph is the counterplay, get out.
## Always casts (at full range toward a far cursor); bots only drop it on somebody (worth_casting).

const MAX_RANGE := 620.0
const RADIUS := 170.0
const DELAY := 1.0
const SHOVE := 950.0       ## at the centre; LAUNCH_EDGE of it at the rim
const LAUNCH_EDGE := 0.55
const FIRE := Color(1.0, 0.45, 0.15)

## Where it lands for a cast from `from` aimed at `aim_pos`.
static func spot(from: Vector2, aim_pos: Vector2) -> Vector2:
	return from + (aim_pos - from).limit_length(MAX_RANGE)

## Foes the impact at `at` catches.
static func caught(at: Vector2, foes: Array[Node2D]) -> Array[Node2D]:
	var out: Array[Node2D] = []
	for e in foes:
		if e.global_position.distance_to(at) <= RADIUS + 14.0:
			out.append(e)
	return out

## Launch for a foe `off` away from the centre: strongest dead centre, LAUNCH_EDGE of that at the rim, always outward.
static func launch(off: Vector2) -> Vector2:
	var k := clampf(off.length() / RADIUS, 0.0, 1.0)
	var dir := off.normalized() if off.length() > 1.0 else Vector2.RIGHT
	return dir * SHOVE * lerpf(1.0, LAUNCH_EDGE, k)

class Strike extends Node2D:
	var caster: Node2D
	var dmg := 40
	var _age := 0.0
	var _hit := false

	func _ready() -> void:
		add_to_group("zones")   # bots keep out of it like an Ember Field
		Sfx.play("crown", global_position, -4.0, 0.6)   # a low toll: something is coming

	func _physics_process(delta: float) -> void:
		_age += delta
		if not _hit and _age >= DELAY:
			_hit = true
			_impact()
		if _age >= DELAY + 0.5:
			queue_free()
		queue_redraw()

	func _impact() -> void:
		Sfx.play("bomb_boom", global_position, 0.0, 0.8)
		SheetFrames.play_once(get_parent(), global_position, SheetFrames.FX + "AoE/FireAoE/", 0, 22.0, RADIUS / 110.0)
		var cam := get_tree().get_first_node_in_group("camera") as GameCamera
		if cam:
			cam.shake(0.45)
		if not is_instance_valid(caster):
			return
		for e in Meteor.caught(global_position, Spell.foes(caster)):
			if e.take_damage(dmg, global_position, false, caster):
				Spell.shove(e, Meteor.launch(e.global_position - global_position))

	func _draw() -> void:
		if not _hit:
			var k := clampf(_age / DELAY, 0.0, 1.0)
			draw_circle(Vector2.ZERO, Meteor.RADIUS, Color(FIRE, 0.1 + 0.15 * k))
			draw_arc(Vector2.ZERO, Meteor.RADIUS, 0.0, TAU, 56, Color(FIRE, 0.95), 4.0)
			draw_circle(Vector2.ZERO, Meteor.RADIUS * k, Color(FIRE, 0.15))
			# the rock itself, falling in along the screen's up axis, its shadow growing under it
			draw_circle(Vector2.ZERO, 18.0 + 30.0 * k, Color(0, 0, 0, 0.25 + 0.2 * k))
			var rock := Vector2(0, -900.0 * (1.0 - k) * (1.0 - k))
			draw_circle(rock, 26.0, Color(0.35, 0.2, 0.15))
			draw_circle(rock, 18.0, Color(1.0, 0.6, 0.2))
			draw_line(rock, rock + Vector2(0, -140), Color(FIRE, 0.6), 14.0)
		else:
			var k := clampf((_age - DELAY) / 0.5, 0.0, 1.0)
			draw_arc(Vector2.ZERO, Meteor.RADIUS * (0.5 + 0.8 * k), 0.0, TAU, 56, Color(FIRE, 1.0 - k), 10.0 * (1.0 - k) + 1.0)

func _init() -> void:
	display_name = "Meteor"
	cooldown = 0.6     # the charge is the real gate; this only covers the cast lock
	damage = 40
	sfx = "shoot"
	cast_pitch = 0.6

func ult_lock() -> float:
	return DELAY + 0.5

## Bots only: is anyone there to make it worth spending the charge? (Players can always cast it.)
func worth_casting(caster: Node2D, aim_pos: Vector2) -> bool:
	return not caught(spot(caster.global_position, aim_pos), Spell.foes(caster)).is_empty()

func cast(caster: Node2D, _aim_dir: Vector2, aim_pos: Vector2) -> float:
	var s := Strike.new()
	s.caster = caster
	s.dmg = damage
	s.position = spot(caster.global_position, aim_pos)
	s.z_index = 4
	caster.get_parent().add_child(s)
	return cooldown
