class_name SnipeShot extends Spell
## Ranger right click: one heavy arrow that pierces everything in a long line.

const ARROW := "res://assets/tiny_swords/units/Blue/Archer/Arrow.png"
const SPEED := 1500.0

func _init() -> void:
	display_name = "Snipe Shot"
	cooldown = 3.0
	damage = 45

func cast(caster: Node2D, aim_dir: Vector2, _aim_pos: Vector2) -> float:
	var p := Projectile.new().setup(caster.global_position + aim_dir * 30.0 + Vector2(0, 8), aim_dir * SPEED, damage, true, caster)
	p.arrow_tex = ARROW
	p.pierce = 99
	p.life = 0.75
	p.radius = 12.0
	caster.get_tree().current_scene.add_child(p)
	return cooldown
