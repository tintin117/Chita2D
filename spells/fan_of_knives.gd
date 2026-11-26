class_name FanOfKnives extends Spell
## Shade right click: a fan of KNIVES knives across SPREAD radians toward the aim. Each one that lands hits for `damage`
## and slows. Point blank most of them land on one foe; at range the fan covers a doorway or a bridge.

const KNIVES := 5
const SPREAD := 1.05          ## ~60 degrees
const RANGE := 380.0
const SPEED := 1000.0
const SLOW := Vector2(0.5, 1.2)
const COLOR := Color(0.55, 1.0, 0.7)

## The knives' directions around `dir`, evenly across SPREAD.
static func directions(dir: Vector2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in KNIVES:
		out.append(dir.rotated(lerpf(-SPREAD / 2.0, SPREAD / 2.0, float(i) / (KNIVES - 1))))
	return out

func _init() -> void:
	display_name = "Fan of Knives"
	cooldown = 6.0
	damage = 7
	sfx = "swing"
	cast_pitch = 1.3

func cast(caster: Node2D, aim_dir: Vector2, _aim_pos: Vector2) -> float:
	var d := aim_dir.normalized() if aim_dir != Vector2.ZERO else Vector2.RIGHT
	for k in directions(d):
		var p := Projectile.new().setup(caster.global_position + k * 24.0 + Vector2(0, 8), k * SPEED, damage, true, caster)
		p.radius = 11.0
		p.life = RANGE / SPEED
		p.color = COLOR
		p.trail = 50.0
		p.slow = SLOW
		caster.get_tree().current_scene.add_child(p)
	return cooldown
