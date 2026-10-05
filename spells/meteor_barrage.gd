class_name MeteorBarrage extends Spell
## Signature: 8 delayed explosions scattered around the aim point over ~2s.

func _init() -> void:
	display_name = "Meteor Barrage"
	cooldown = 0.5
	damage = 30
	charge_cost = 100.0

func cast(caster: Node2D, _aim_dir: Vector2, aim_pos: Vector2) -> float:
	var center := caster.global_position + (aim_pos - caster.global_position).limit_length(420.0)
	for i in 8:
		var pos := center + Vector2.from_angle(randf() * TAU) * randf_range(0.0, 170.0)
		caster.get_tree().current_scene.add_child(Explosion.new().setup(pos, 70.0, damage, 0.4 + i * 0.22, caster))
	return cooldown
