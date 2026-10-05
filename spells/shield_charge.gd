class_name ShieldCharge extends Spell
## Knight right click: rush forward behind the shield, shoving everything in the way. Brief invulnerability.

const TIME := 0.28
const SPEED := 780.0
const SHOVE := 650.0

class Rider extends Node:
	var caster: Node2D
	var dir := Vector2.RIGHT
	var dmg := 22
	var left := TIME
	var _hit: Array[Node] = []

	func _physics_process(delta: float) -> void:
		if not is_instance_valid(caster):
			queue_free()
			return
		left -= delta
		var pos := caster.global_position + Vector2(0, 8)
		for e: Node2D in get_tree().get_nodes_in_group("enemies"):
			if e in _hit or e.global_position.distance_to(pos) > 62.0:
				continue
			_hit.append(e)
			e.take_damage(dmg, pos)
			if e.kind != "boss":
				e.knock += dir * SHOVE
			caster.on_dealt_damage(dmg)
		if left <= 0.0:
			queue_free()

func _init() -> void:
	display_name = "Shield Charge"
	cooldown = 4.0
	damage = 22

func cast(caster: Node2D, aim_dir: Vector2, _aim_pos: Vector2) -> float:
	caster.lunge(aim_dir, TIME, SPEED)
	caster._iframes = maxf(caster._iframes, TIME + 0.1)
	var r := Rider.new()
	r.caster = caster
	r.dir = aim_dir.normalized()
	r.dmg = damage
	caster.get_tree().current_scene.add_child(r)
	SheetFrames.play_once(caster.get_parent(), caster.global_position + Vector2(0, 20), "res://assets/tiny_swords/fx/Dust_01.png", 8, 24.0, 0.9)
	return cooldown
