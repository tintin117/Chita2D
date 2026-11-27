class_name Cluckcurse extends Spell
## Pactknight right click: a hex bolt at the foe near the cursor (homing on a lock; a dash shakes it off). The first foe
## it touches is a chicken for TIME seconds: no attacks, no skills, no dash, slower (Player.hex). No damage.
## Runs on every peer, so every screen hexes the same foe.

const SPEED := 1000.0
const RANGE := 450.0
const TIME := 1.4
const RADIUS := 22.0
const PICK_RADIUS := 150.0
const COLOR := Color(0.7, 0.25, 1.0)   ## the hero's signature colour (Hero.basic_color)

class Curse extends Node2D:
	var caster: Node2D
	var dir := Vector2.RIGHT
	var velocity := Vector2.ZERO   ## for bots to dodge (group dodgeables)

	func _ready() -> void:
		add_to_group("dodgeables")
	var target: Node2D
	var life := RANGE / SPEED

	func _physics_process(delta: float) -> void:
		life -= delta
		if life <= 0.0 or not is_instance_valid(caster):
			queue_free()
			return
		if is_instance_valid(target) and not target.down and not (target.has_method("dodging") and target.dodging()):
			dir = (target.global_position + Vector2(0, -4) - global_position).normalized()
		else:
			target = null
		global_position += dir * SPEED * delta
		velocity = dir * SPEED
		for e in Spell.foes(caster):
			if e.global_position.distance_to(global_position) > RADIUS + 14.0:
				continue
			if e.has_method("dodging") and e.dodging():
				continue
			if e.has_method("hex"):
				e.hex(TIME)
			Sfx.play("cluck", global_position)
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		draw_circle(Vector2.ZERO, RADIUS * 0.8, Color(COLOR, 0.3))
		draw_circle(Vector2.ZERO, 8.0, COLOR)
		draw_circle(Vector2.ZERO, 4.0, Color(1.0, 0.9, 0.35))
		draw_line(Vector2.ZERO, -dir * 30.0, Color(COLOR, 0.5), 6.0)

func _init() -> void:
	display_name = "Chicken Hex"
	cooldown = 8.0
	damage = 0
	sfx = "shoot"
	cast_pitch = 1.4

func target(caster: Node2D, aim_pos: Vector2, dir: Vector2) -> Node2D:
	if caster.get("ai"):
		return null
	return Spell.pick_foe(caster, aim_pos, dir, PICK_RADIUS, 0.4, RANGE)

func aim(caster: Node2D, dir: Vector2) -> Vector2:
	return Spell.assist_dir(caster, dir, 0.4, RANGE, 0.0 if caster.get("ai") else SPEED)

func cast(caster: Node2D, aim_dir: Vector2, _aim_pos: Vector2) -> float:
	var c := Curse.new()
	c.caster = caster
	c.dir = aim_dir.normalized() if aim_dir != Vector2.ZERO else Vector2.RIGHT
	c.target = lock if is_instance_valid(lock) else null
	if c.target:
		c.life *= 1.4
	c.position = caster.global_position + Vector2(0, 2) + c.dir * 24.0
	c.z_index = 6
	caster.get_parent().add_child(c)
	return cooldown
