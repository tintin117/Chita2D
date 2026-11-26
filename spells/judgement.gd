class_name Judgement extends Spell
## Knight ult: leap toward the cursor (over rocks, not walls), land after LEAP seconds and slam: everyone within RADIUS of
## the landing spot takes a heavy hit, is stunned and shoved outward. Untouchable in the air.
## The landing circle is drawn from the moment of the jump: that is the counterplay, walk out of it.
## Always casts: a far cursor leaps the full RANGE that way (also an escape). Bots only leap onto somebody (worth_casting).

const RANGE := 420.0       ## farthest leap
const LEAP := 0.5          ## seconds in the air (the telegraph)
const RADIUS := 150.0
const STUN := 1.0
const SHOVE := 380.0
const GOLD := Color(1.0, 0.8, 0.35)

## Where the leap lands: toward `aim_pos`, at most RANGE away, backed off water toward the start (never jumps into the
## sea). `is_water` is the map's check; pass an invalid Callable to skip it. Pure, so tests and every peer agree.
static func landing(from: Vector2, aim_pos: Vector2, is_water: Callable) -> Vector2:
	var to := from + (aim_pos - from).limit_length(RANGE)
	if not is_water.is_valid():
		return to
	var back := (from - to).normalized() * 16.0
	var tries := 0
	while is_water.call(to + Vector2(0, 14)) and tries < 40 and to.distance_to(from) > 16.0:
		to += back
		tries += 1
	return to

## Foes the slam at `at` catches.
static func caught(at: Vector2, foes: Array[Node2D]) -> Array[Node2D]:
	var out: Array[Node2D] = []
	for e in foes:
		if e.global_position.distance_to(at) <= RADIUS + 14.0:
			out.append(e)
	return out

class Slam extends Node2D:
	var caster: Node2D
	var dmg := 26
	var _age := 0.0
	var _done := false

	func _ready() -> void:
		z_index = 4

	func _physics_process(delta: float) -> void:
		_age += delta
		if not _done and _age >= LEAP:
			_done = true
			_land()
		if _age >= LEAP + 0.35:
			queue_free()
		queue_redraw()

	func _land() -> void:
		if not is_instance_valid(caster) or caster.down:
			return
		Sfx.play("bomb_boom", global_position, -6.0, 1.2)
		SheetFrames.play_once(get_parent(), global_position + Vector2(0, 20), SheetFrames.FX + "AoE/FireAoE/", 0, 30.0, 0.5)
		for e in Judgement.caught(global_position, Spell.foes(caster)):
			if not e.take_damage(dmg, global_position, false, caster):
				continue   # dodged (dash / phase): no stun, no shove
			Spell.stun(e, STUN)
			var out: Vector2 = e.global_position - global_position
			Spell.shove(e, (out if out.length() > 1.0 else Vector2.RIGHT).normalized() * SHOVE)

	func _draw() -> void:
		if not _done:   # the telegraph: a filling circle where the Knight will come down
			var k := clampf(_age / LEAP, 0.0, 1.0)
			draw_circle(Vector2(0, 14), Judgement.RADIUS, Color(GOLD, 0.12 + 0.12 * k))
			draw_arc(Vector2(0, 14), Judgement.RADIUS, 0.0, TAU, 40, Color(GOLD, 0.9), 3.0)
			draw_circle(Vector2(0, 14), Judgement.RADIUS * k, Color(GOLD, 0.18))
		else:   # the shockwave
			var k := clampf((_age - LEAP) / 0.35, 0.0, 1.0)
			draw_arc(Vector2(0, 14), Judgement.RADIUS * (0.6 + 0.6 * k), 0.0, TAU, 40, Color(GOLD, 1.0 - k), 8.0 * (1.0 - k) + 1.0)

func _init() -> void:
	display_name = "Judgement"
	cooldown = 0.6     # the charge is the real gate; this only covers the cast lock
	damage = 26
	sfx = "dash"
	cast_pitch = 0.7

func _water(caster: Node2D) -> Callable:
	if "ground_check" in caster and caster.ground_check.is_valid():
		return caster.ground_check   # never land in the water or against the wall
	return caster.water_check if "water_check" in caster else Callable()

func ult_lock() -> float:
	return LEAP + 0.5

## Bots only: is anyone there to make it worth spending the charge? (Players can always cast it.)
func worth_casting(caster: Node2D, aim_pos: Vector2) -> bool:
	var at := landing(caster.global_position, aim_pos, _water(caster))
	return not caught(at, Spell.foes(caster)).is_empty()

func cast(caster: Node2D, _aim_dir: Vector2, aim_pos: Vector2) -> float:
	var from := caster.global_position
	var to := landing(from, aim_pos, _water(caster))
	caster.phase(LEAP)   # in the air: nothing touches the Knight until he lands
	if caster.owns():   # only the owner moves it; everyone else sees the flight through the replicated position
		caster.leap(to - from, LEAP)
	var s := Slam.new()
	s.caster = caster
	s.dmg = damage
	s.position = to
	caster.get_parent().add_child(s)
	return cooldown
