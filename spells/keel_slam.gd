class_name KeelSlam extends Spell
## Tidecaller right click: slam the anchor down. Every foe within RADIUS takes the hit and is weakened: for WEAK_TIME
## seconds everything it deals is cut to Player.WEAK_MULT. The weaken is set on every peer whether or not the hit
## itself landed there (its hits are judged on its victims' peers, so they all need to agree on it).

const RADIUS := 150.0
const WEAK_TIME := 3.0
const COLOR := Color(0.15, 0.85, 0.85)   ## the hero's signature colour (Hero.basic_color)

class Ring extends Node2D:
	var _age := 0.0

	func _physics_process(delta: float) -> void:
		_age += delta
		if _age >= 0.4:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		var k := _age / 0.4
		draw_circle(Vector2.ZERO, KeelSlam.RADIUS * (0.6 + 0.4 * k), Color(COLOR, 0.25 * (1.0 - k)))
		draw_arc(Vector2.ZERO, KeelSlam.RADIUS * (0.6 + 0.4 * k), 0.0, TAU, 48, Color(0.9, 0.97, 1.0, 1.0 - k), 5.0)

func _init() -> void:
	display_name = "Anchor Slam"
	cooldown = 7.0
	damage = 18
	sfx = "explosion"
	cast_pitch = 0.7

static func caught(at: Vector2, foes: Array[Node2D]) -> Array[Node2D]:
	var out: Array[Node2D] = []
	for e in foes:
		if e.global_position.distance_to(at) <= RADIUS + 14.0:
			out.append(e)
	return out

func cast(caster: Node2D, _aim_dir: Vector2, _aim_pos: Vector2) -> float:
	var at := caster.global_position + Vector2(0, 10)
	for e in caught(at, Spell.foes(caster)):
		e.take_damage(damage, at, false, caster)
		if e.has_method("weaken"):
			e.weaken(WEAK_TIME)
		if e.has_method("float_text"):
			e.float_text("WEAKENED", Color(0.6, 0.8, 1.0), 16)
	var r := Ring.new()
	r.position = at
	r.z_index = 3
	caster.get_parent().add_child(r)
	var cam := caster.get_tree().get_first_node_in_group("camera") as GameCamera
	if cam and Player.is_local(caster):
		cam.shake(0.3)
	return cooldown
