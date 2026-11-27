class_name RiftBolt extends Spell
## Chaos Lord right click: a bolt at the foe near the cursor (homing on a lock, shaken off by a dash). Loaded Dice
## rolls once per cast and scales BOTH its damage and its stun: a 0.5x roll is a tickle, a 3.5x roll is 28 and a 2.1 s
## stun. The stun still obeys the stun immunity.

const SPEED := 760.0
const RANGE := 450.0
const BASE_STUN := 0.6
const PICK_RADIUS := 150.0
const COLOR := Color(0.95, 0.3, 0.85)   ## the hero's signature colour (Hero.basic_color)

func _init() -> void:
	display_name = "Chaos Blast"
	cooldown = 7.0
	damage = 8
	sfx = "shoot"
	cast_pitch = 0.6

func target(caster: Node2D, aim_pos: Vector2, dir: Vector2) -> Node2D:
	if caster.get("ai"):
		return null
	return Spell.pick_foe(caster, aim_pos, dir, PICK_RADIUS, 0.4, RANGE)

func aim(caster: Node2D, dir: Vector2) -> Vector2:
	return Spell.assist_dir(caster, dir, 0.4, RANGE, 0.0 if caster.get("ai") else SPEED)

func cast(caster: Node2D, aim_dir: Vector2, _aim_pos: Vector2) -> float:
	var d := aim_dir.normalized() if aim_dir != Vector2.ZERO else Vector2.RIGHT
	var roll := Chaos.roll(caster)
	var p := Projectile.new().setup(caster.global_position + d * 28.0 + Vector2(0, 8), d * SPEED, maxi(roundi(damage * roll), 1), true, caster)
	p.radius = 18.0
	p.life = RANGE / SPEED
	p.stun = BASE_STUN * roll
	p.color = COLOR
	p.tex_scale = 0.9 + 0.2 * roll
	if is_instance_valid(lock):
		p.target = lock
		p.life *= 1.4
	caster.get_tree().current_scene.add_child(p)
	return cooldown
