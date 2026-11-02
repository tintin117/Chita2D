class_name ShieldCharge extends Spell
## Knight right click: rush forward behind the shield, shoving everything in the way. Brief invulnerability.
## A foe shoved straight into a rock or wall takes PIN_BONUS extra damage; one shoved toward the water just goes swimming.

const TIME := 0.28
const SPEED := 780.0
const SHOVE := 1400.0
const PIN_BONUS := 1.6
const PIN_REACH := 130.0

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
		for e in Spell.foes(caster):
			if e in _hit or e.global_position.distance_to(pos) > 62.0:
				continue
			_hit.append(e)
			var pinned := Spell.solid_ahead(caster, e.global_position + Vector2(0, 14), dir, PIN_REACH)
			e.take_damage(roundi(dmg * PIN_BONUS) if pinned else dmg, pos, false, caster)
			Sfx.play("hit_big", pos)
			if pinned and e.has_method("float_text"):
				e.float_text("PINNED!", Color(1.0, 0.7, 0.2), 22)
			Spell.shove(e, dir * SHOVE)   # only the victim's own peer moves it
		if left <= 0.0:
			queue_free()

func _init() -> void:
	display_name = "Shield Charge"
	cooldown = 6.0
	damage = 22
	sfx = "dash"

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
