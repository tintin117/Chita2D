class_name ArrowRain extends Spell
## Ranger ult: a storm of arrows on the cursor. After a short DELAY, for DURATION seconds every VOLLEY hits everyone in
## the circle for a little and slows them, so they must leave the area or keep bleeding. Silent hits: no knockback, the
## rain never pushes anyone out on its own. Pairs with Power Shot: slowed foes are easy to land a full draw on.
## Always casts (at full range toward a far cursor); bots only rain on somebody (worth_casting).

const MAX_RANGE := 650.0
const RADIUS := 160.0
const DELAY := 0.4
const DURATION := 3.0
const VOLLEY := 0.3
const SLOW := 0.6
const TINT := Color(1.0, 0.6, 0.25)

static func spot(from: Vector2, aim_pos: Vector2) -> Vector2:
	return from + (aim_pos - from).limit_length(MAX_RANGE)

static func caught(at: Vector2, foes: Array[Node2D]) -> Array[Node2D]:
	var out: Array[Node2D] = []
	for e in foes:
		if e.global_position.distance_to(at) <= RADIUS + 14.0:
			out.append(e)
	return out

## Volleys in a full rain (the most a foe that stays inside takes).
static func volleys() -> int:
	return int(floor(DURATION / VOLLEY + 0.001))

class Storm extends Node2D:
	var caster: Node2D
	var dmg := 6
	var _age := 0.0
	var _next := DELAY
	var _streaks: Array[Vector3] = []   ## x, y, birth age: falling arrows, visual only

	func _ready() -> void:
		add_to_group("zones")   # bots walk out of it

	func _physics_process(delta: float) -> void:
		_age += delta
		while _age >= _next and _next < DELAY + DURATION:
			_volley()
			_next += VOLLEY
		if _age >= DELAY + DURATION + 0.2:
			queue_free()
		queue_redraw()

	func _volley() -> void:
		for i in 6:
			var at := Vector2.from_angle(randf() * TAU) * sqrt(randf()) * RADIUS
			_streaks.append(Vector3(at.x, at.y, _age))
		Sfx.play("shoot", global_position, -10.0, 1.6 + randf() * 0.3)
		if not is_instance_valid(caster) or caster.down:
			return
		for e in ArrowRain.caught(global_position, Spell.foes(caster)):
			if e.take_damage(dmg, global_position, true, caster) and e.has_method("apply_slow"):
				e.apply_slow(SLOW, VOLLEY + 0.15)

	func _draw() -> void:
		var raining := _age >= DELAY
		var fade := 1.0 - clampf((_age - DELAY - DURATION) / 0.2, 0.0, 1.0)
		draw_circle(Vector2(0, 14), RADIUS, Color(TINT, (0.16 if raining else 0.08) * fade))
		draw_arc(Vector2(0, 14), RADIUS, 0.0, TAU, 48, Color(TINT, 0.85 * fade), 3.0)
		for s in _streaks:
			var k := (_age - s.z) / 0.25
			if k < 0.0 or k > 1.0:
				continue
			var land := Vector2(s.x, s.y + 14.0)
			var tip := land + Vector2(-60, -260) * (1.0 - k)
			draw_line(tip, tip + Vector2(-14, -60), Color(1, 0.9, 0.7, 0.9), 2.0)
			if k > 0.85:
				draw_circle(land, 5.0, Color(TINT, 0.7))

func _init() -> void:
	display_name = "Arrow Rain"
	cooldown = 0.6     # the charge is the real gate; this only covers the cast lock
	damage = 6
	sfx = "shoot"
	cast_pitch = 0.8

## Bots only: is anyone there to make it worth spending the charge? (Players can always cast it.)
func worth_casting(caster: Node2D, aim_pos: Vector2) -> bool:
	return not caught(spot(caster.global_position, aim_pos), Spell.foes(caster)).is_empty()

func cast(caster: Node2D, _aim_dir: Vector2, aim_pos: Vector2) -> float:
	var s := Storm.new()
	s.caster = caster
	s.dmg = damage
	s.position = spot(caster.global_position, aim_pos)
	s.z_index = 4
	caster.get_parent().add_child(s)
	return cooldown
