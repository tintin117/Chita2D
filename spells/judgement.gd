class_name Judgement extends Spell
## Knight ult: leap toward the cursor (over rocks, not walls), land after LEAP seconds and slam: everyone within RADIUS of
## the landing spot takes a heavy hit, is stunned and shoved outward. Untouchable in the air.
## The projected landing boundary is drawn from the moment of the jump: that is the counterplay, walk out of it.
## Always casts: a far cursor leaps the full RANGE that way (also an escape). Bots only leap onto somebody (worth_casting).

const RANGE := 420.0       ## farthest leap
const RISE := 0.20         ## travel to the landing point while rising
const HOLD := 5.0 / 60.0   ## hang overhead for five ticks at the standard physics rate
const DESCENT := 7.0 / 60.0
const DROP := RISE + HOLD
const LEAP := DROP + DESCENT
const RADIUS := 150.0
const STUN := 1.0
const SHOVE := 380.0
const HIT_RADIUS := RADIUS + 14.0
const GROUND_OFFSET := Vector2(0, 14)
const RECOVERY := 0.17
const HEIGHT := 61.0
const AFTERSHOCK := 0.35

## Where the leap lands: toward `aim_pos`, at most RANGE away, backed off water toward the start (never jumps into the
## sea). `is_water` is the map's check; pass an invalid Callable to skip it. Pure, so tests and every peer agree.
static func landing(from: Vector2, aim_pos: Vector2, is_water: Callable) -> Vector2:
	var to := from + (aim_pos - from).limit_length(RANGE)
	if not is_water.is_valid():
		return to
	var back := (from - to).normalized() * 16.0
	var tries := 0
	while is_water.call(to + GROUND_OFFSET) and tries < 40 and to.distance_to(from) > 16.0:
		to += back
		tries += 1
	return to

## Foes the slam at `at` catches.
static func caught(at: Vector2, foes: Array[Node2D]) -> Array[Node2D]:
	var out: Array[Node2D] = []
	for e in foes:
		if ((e.global_position - at) / KnightFx.GROUND_SCALE).length_squared() <= HIT_RADIUS * HIT_RADIUS:
			out.append(e)
	return out

## Visual altitude above the moving ground position.
static func height_at(age: float) -> float:
	if age < RISE:
		return HEIGHT * (1.0 - pow(1.0 - clampf(age / RISE, 0.0, 1.0), 2.0))
	if age < DROP:
		return HEIGHT
	if age >= LEAP:
		return 0.0
	var descent := (age - DROP) / DESCENT
	return HEIGHT * (1.0 - descent * descent)

## Original Special1 poses: lift (0–4), hold (4), swing (5–8), then impact and recovery (9–14).
static func pose_at(age: float) -> int:
	if age < RISE:
		return floori(4.0 * clampf(age / RISE, 0.0, 1.0))
	if age < DROP:
		return 4
	if age < LEAP:
		return 5 + mini(floori(4.0 * (age - DROP) / DESCENT), 3)
	return 9 + mini(floori(6.0 * (age - LEAP) / RECOVERY), 5)

class Slam extends Node2D:
	var caster: Node2D
	var dmg := 26
	var _cast_frame := Engine.get_physics_frames()
	var _age := 0.0
	var _done := false
	var _floor := Node2D.new()

	func _ready() -> void:
		z_index = 4
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_floor.z_as_relative = false
		_floor.z_index = -1
		_floor.position = GROUND_OFFSET
		add_child(_floor)
		_floor.draw.connect(_draw_floor)

	func _physics_process(delta: float) -> void:
		# A cast from player input can add this node during a physics tick.
		# The Knight's travel starts on the next tick.
		if Engine.get_physics_frames() == _cast_frame:
			return
		_age += delta
		if not _done and _age + 0.00001 >= LEAP:
			_age = maxf(_age, LEAP)
			_done = true
			_update_pose()
			_land()
		else:
			_update_pose()
		if _age >= LEAP + AFTERSHOCK:
			queue_free()
		queue_redraw()
		_floor.queue_redraw()

	func _update_pose() -> void:
		if is_instance_valid(caster) and caster is Player and caster._judgement_art == self:
			if _age >= LEAP + RECOVERY or caster.down:
				caster._clear_judgement_art()
			else:
				caster._show_judgement_pose(_age)

	func _land() -> void:
		if not is_instance_valid(caster) or caster.down:
			return
		Sfx.play("bomb_boom", global_position, -6.0, 1.2)
		for e in Judgement.caught(global_position, Spell.foes(caster)):
			if not e.take_damage(dmg, global_position, false, caster, KnightFx.SLAM):
				continue   # dodged (dash / phase): no stun, no shove
			Spell.stun(e, STUN)
			var out: Vector2 = e.global_position - global_position
			Spell.shove(e, (out if out.length() > 1.0 else Vector2.RIGHT).normalized() * SHOVE)

	func _draw_floor() -> void:
		if _done:
			KnightFx.draw_slam(_floor, KnightFx.FLOOR, HIT_RADIUS, (_age - LEAP) / AFTERSHOCK)
			return
		var charge := clampf(_age / LEAP, 0.0, 1.0)
		var boundary := PackedVector2Array()
		for i in 65:
			boundary.append(Vector2.from_angle(TAU * i / 64.0) * HIT_RADIUS * KnightFx.GROUND_SCALE)
		_floor.draw_polyline(boundary, Color(KnightFx.INK, 0.53), 3)
		_floor.draw_polyline(boundary, Color(KnightFx.GOLD, 0.42 + charge * 0.4), 1)
		for i in 24:
			var tangent := TAU * i / 24.0
			var ray := Vector2.from_angle(tangent)
			var projected := ray * KnightFx.GROUND_SCALE
			var rim := projected * HIT_RADIUS
			var arm := ray.orthogonal() * KnightFx.GROUND_SCALE * (6.0 if i % 3 == 0 else 4.0)
			_floor.draw_line(rim - arm, rim + arm, Color(KnightFx.INK, 0.75), 4)
			_floor.draw_line(rim - arm, rim + arm, Color(KnightFx.GOLD, 0.6 + charge * 0.35), 2)
			_floor.draw_line(rim, rim - projected * (12.0 if i % 3 == 0 else 5.0), Color(KnightFx.GOLD, 0.56), 2)
		var radius := lerpf(33.0, 105.0, charge)
		var diamond := PackedVector2Array()
		for yaw in [0.0, PI * 0.5, PI, PI * 1.5, TAU]:
			diamond.append(Vector2.from_angle(yaw) * radius * KnightFx.GROUND_SCALE)
		_floor.draw_polyline(diamond, Color(KnightFx.INK, 0.78), 5)
		_floor.draw_polyline(diamond, Color(KnightFx.GOLD, 0.45 + charge * 0.48), 2)
		for i in 4:
			_floor.draw_line(diamond[i] * 0.34, diamond[i] * 0.90, Color(KnightFx.GOLD, charge * 0.6), 2)

	func _draw() -> void:
		if _done:
			draw_set_transform(GROUND_OFFSET)
			KnightFx.draw_slam(self, KnightFx.DEBRIS, HIT_RADIUS, (_age - LEAP) / AFTERSHOCK)

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
		caster.leap(to - from, RISE, HOLD + DESCENT)
	var s := Slam.new()
	s.caster = caster
	s.dmg = damage
	caster.get_parent().add_child(s)
	s.global_position = to
	if caster is Player and caster.hero and caster.hero.id == "knight":
		caster._judgement_art = s
	return cooldown
