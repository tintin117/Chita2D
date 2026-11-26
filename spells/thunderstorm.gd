class_name Thunderstorm extends Spell
## Sorcerer ult (Razor's Eye of the Storm): a storm follows you for DURATION seconds. Every STRIKE_EVERY seconds one
## bolt hits ONE foe within RADIUS: the one with the lowest health share (nearest breaks a tie), so it picks off the
## weak. Every strike on the same foe hits harder (+STACK per earlier strike on it, like Razor's armour shred).
## A ring shows the reach: get out of it. Silent strikes: no knockback. Always casts; bots only start it with a foe in the ring (worth_casting).

const DURATION := 3.5
const RADIUS := 320.0
const STRIKE_EVERY := 0.45
const STACK := 1

static func in_ring(at: Vector2, foes: Array[Node2D]) -> Array[Node2D]:
	var out: Array[Node2D] = []
	for e in foes:
		if e.global_position.distance_to(at) <= RADIUS + 14.0:
			out.append(e)
	return out

## The foe the next bolt hits: lowest hp share in the ring, then nearest. Null if the ring is empty.
static func pick(at: Vector2, foes: Array[Node2D]) -> Node2D:
	var best: Node2D = null
	var best_k := INF
	for e in in_ring(at, foes):
		var share: float = float(e.hp) / maxf(e.max_hp, 1.0) if "hp" in e and "max_hp" in e else 1.0
		var k := share * 10000.0 + e.global_position.distance_to(at)
		if k < best_k:
			best_k = k
			best = e
	return best

## Damage of a strike on a foe already struck `n` times by this storm.
static func strike_damage(base: int, n: int) -> int:
	return base + STACK * n

## Strikes in a full storm.
static func strikes() -> int:
	return int(floor(DURATION / STRIKE_EVERY + 0.001))

class Storm extends Node2D:
	var caster: Node2D
	var dmg := 9
	var _age := 0.0
	var _next := STRIKE_EVERY
	var _bolts: Array[Dictionary] = []   ## {at, age}: visual only
	var _struck := {}                   ## foe -> strikes so far (the shred)

	func _ready() -> void:
		z_index = 5

	func _physics_process(delta: float) -> void:
		_age += delta
		if not is_instance_valid(caster) or caster.down or _age >= DURATION + 0.3:
			queue_free()
			return
		global_position = caster.global_position
		if _age >= _next and _age <= DURATION:
			_next += STRIKE_EVERY
			var e := Thunderstorm.pick(global_position, Spell.foes(caster))
			if e:
				var n: int = _struck.get(e, 0)
				e.take_damage(Thunderstorm.strike_damage(dmg, n), e.global_position, true, caster)
				_struck[e] = n + 1
				_bolts.append({"at": e.global_position, "age": _age})
				Sfx.play("explosion", global_position, -8.0, 1.8)
		queue_redraw()

	func _draw() -> void:
		var on := _age <= DURATION
		var pulse := 0.5 + 0.5 * sin(_age * 10.0)
		if on:
			draw_arc(Vector2(0, 14), Thunderstorm.RADIUS, 0.0, TAU, 56, Color(ChainLightning.BOLT, 0.35 + 0.25 * pulse), 3.0)
			draw_circle(Vector2(0, 14), Thunderstorm.RADIUS, Color(ChainLightning.BOLT, 0.06))
		for b in _bolts:
			var k := 1.0 - (_age - float(b.age)) / 0.2
			if k <= 0.0:
				continue
			var at: Vector2 = to_local(b.at)
			var top := at + Vector2(randf_range(-20, 20), -420)
			var pts := PackedVector2Array([top])
			for i in range(1, 6):
				pts.append(top.lerp(at, i / 6.0) + Vector2(randf_range(-16, 16), 0))
			pts.append(at)
			draw_polyline(pts, Color(ChainLightning.BOLT, 0.6 * k), 9.0 * k + 1.0)
			draw_polyline(pts, Color(1, 1, 1, k), 2.5)

func _init() -> void:
	display_name = "Thunderstorm"
	cooldown = 0.6     # the charge is the real gate; this only covers the cast lock
	damage = 7
	sfx = "explosion"
	cast_pitch = 1.4

func ult_lock() -> float:
	return DURATION + 0.5

## Bots only: is anyone there to make it worth spending the charge? (Players can always cast it.)
func worth_casting(caster: Node2D, _aim_pos: Vector2) -> bool:
	return not in_ring(caster.global_position, Spell.foes(caster)).is_empty()

func cast(caster: Node2D, _aim_dir: Vector2, _aim_pos: Vector2) -> float:
	var s := Storm.new()
	s.caster = caster
	s.dmg = damage
	s.global_position = caster.global_position
	caster.get_parent().add_child(s)
	if caster.has_method("float_text"):
		caster.float_text("THUNDERSTORM", ChainLightning.BOLT, 22)
	return cooldown
