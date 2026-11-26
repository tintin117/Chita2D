class_name StiflingDagger extends Spell
## Shade right click (Phantom Assassin): throw a dagger at the foe nearest the cursor (or straight along the aim). It
## homes on a locked foe, hits for `damage` and slows it hard for SLOW[1] seconds: the Shade's way to catch a runner
## and get in blade range. A dash or a phase shakes the homing off, like any locked shot.

const RANGE := 520.0
const SPEED := 1250.0
const SLOW := Vector2(0.45, 1.6)   ## speed multiplier, seconds
const PICK_RADIUS := 180.0
const COLOR := Color(0.3, 1.0, 0.55)

func _init() -> void:
	display_name = "Stifling Dagger"
	cooldown = 6.0
	damage = 14
	sfx = "shoot"
	cast_pitch = 1.5

func target(caster: Node2D, aim_pos: Vector2, dir: Vector2) -> Node2D:
	if caster.get("ai"):
		return null
	return Spell.pick_foe(caster, aim_pos, dir, PICK_RADIUS, 0.4, RANGE)

func cast(caster: Node2D, aim_dir: Vector2, _aim_pos: Vector2) -> float:
	var d := aim_dir.normalized() if aim_dir != Vector2.ZERO else Vector2.RIGHT
	var p := Projectile.new().setup(caster.global_position + d * 28.0 + Vector2(0, 8), d * SPEED, damage, true, caster)
	p.radius = 14.0
	p.life = RANGE / SPEED
	p.color = COLOR
	p.trail = 70.0
	p.slow = SLOW
	if lock:
		p.target = lock
		p.life *= 1.4   # room to chase a target that runs
	caster.get_tree().current_scene.add_child(p)
	return cooldown
