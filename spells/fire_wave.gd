class_name FireWave extends Spell
## Standard 2: fan of 5 piercing fireballs.

func _init() -> void:
	display_name = "Fire Wave"
	cooldown = 4.0
	damage = 14

func cast(caster: Node2D, aim_dir: Vector2, _aim_pos: Vector2) -> float:
	for i in 5:
		var dir := aim_dir.rotated((i - 2) * 0.28)
		var p := Projectile.new().setup(caster.global_position + dir * 30.0 + Vector2(0, 8), dir * 520.0, damage, true, caster)
		p.pierce = 3
		p.life = 0.75
		p.radius = 13.0
		p.color = Color(1.0, 0.35, 0.1)
		caster.get_tree().current_scene.add_child(p)
	return cooldown
