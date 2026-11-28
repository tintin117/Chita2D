class_name RiftBolt extends Spell
## Chaos Lord right click: a bolt at the foe near the cursor (homing on a lock, shaken off by a dash). Loaded Dice
## rolls once per cast and scales BOTH its damage and its stun: a 0.5x roll is a tickle, a 3.5x roll is 28 and a 2.1 s
## stun. The stun still obeys the stun immunity.

const SPEED := 760.0
const RANGE := 450.0
const BASE_STUN := 0.6
const PICK_RADIUS := 150.0
const COLOR := Color(0.95, 0.3, 0.85)   ## the hero's signature colour (Hero.basic_color)
## Aperture in the first CastSpell cell, in the SpriteFrames facing order.
const CAST_APERTURE: Array[Vector2] = [Vector2(78, 64), Vector2(63, 66), Vector2(48, 63), Vector2(36, 54),
	Vector2(50, 40), Vector2(65, 38), Vector2(80, 40), Vector2(91, 55)]

class Bolt extends Projectile:
	const WAKE_LENGTH := 8
	const FLIGHT_OFFSET := Vector2(0, -28)

	var power := 0.0
	var launch_offset := FLIGHT_OFFSET
	var _wake := PackedVector2Array()

	func _visual_offset() -> Vector2:
		return launch_offset.lerp(FLIGHT_OFFSET, smoothstep(0.0, 0.07, _anim_t))

	func _draw() -> void:
		for i in range(0, _wake.size() - 1, 2):
			var past := to_local(_wake[i])
			var heading := _wake[i + 1] - _wake[i]
			if heading.length_squared() < 1.0:
				heading = velocity
			var steps_back := _wake.size() - i
			var echo := lerpf(0.45, 0.87, float(steps_back) / WAKE_LENGTH)
			var sample_age := _anim_t - steps_back / float(Engine.physics_ticks_per_second)
			ChaosFx.draw_bolt(self, past, heading, sample_age, power, echo)
		ChaosFx.draw_bolt(self, _visual_offset(), velocity, _anim_t, power)

	func _physics_process(delta: float) -> void:
		_wake.append(to_global(_visual_offset()))
		if _wake.size() > WAKE_LENGTH:
			_wake.remove_at(0)
		super._physics_process(delta)
		if life <= 0.0:
			ChaosFx.fizzle(get_parent(), global_position, velocity, power)

	func _on_body_entered(body: Node) -> void:
		if not is_queued_for_deletion():
			super._on_body_entered(body)

	func _damage_body(body: Node, amount: int, from: Vector2) -> bool:
		if body is Player or body is Dummy:
			return body.take_damage(amount, from, false, source, ChaosFx.BLAST, power)
		if body is Enemy:
			var before: int = body.hp
			super._damage_body(body, amount, from)
			if body.hp < before:
				ChaosFx.victim_impact(body, ChaosFx.BLAST, velocity.normalized(), power)
				return true
			return false
		return super._damage_body(body, amount, from)

	func _finish_impact(landed: bool) -> void:
		if not landed:
			ChaosFx.fizzle(get_parent(), global_position, velocity, power)

func _init() -> void:
	display_name = "Chaos Blast"
	cooldown = 7.0
	damage = 8
	sfx = "shoot"
	cast_pitch = 0.6

func target(caster: Node2D, aim_pos: Vector2, dir: Vector2) -> Node2D:
	if caster.get("ai"):
		return null
	return Spell.pick_foe(caster, aim_pos, dir, PICK_RADIUS, 0.4, RANGE)

func aim(caster: Node2D, dir: Vector2) -> Vector2:
	return Spell.assist_dir(caster, dir, 0.4, RANGE, 0.0 if caster.get("ai") else SPEED)

func cast(caster: Node2D, aim_dir: Vector2, _aim_pos: Vector2) -> float:
	var d := aim_dir.normalized() if aim_dir != Vector2.ZERO else Vector2.RIGHT
	var roll := Chaos.roll(caster)
	var start := caster.global_position + d * 28.0 + Vector2(0, 8)
	var p := Bolt.new()
	p.setup(start, d * SPEED, maxi(roundi(damage * roll), 1), true, caster)
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	p.radius = 18.0
	p.life = RANGE / SPEED
	p.stun = BASE_STUN * roll
	p.color = COLOR
	p.power = inverse_lerp(Chaos.LO, Chaos.HI, roll)
	if is_instance_valid(lock):
		p.target = lock
		p.life *= 1.4
	var scene := caster.get_tree().current_scene
	# The sparks on the opening pose meet here, ahead of the torso.
	var aperture := caster.to_global(Vector2(0, -35))
	var behind := false
	if caster is Player and is_instance_valid(caster._sprite):
		var sprite: AnimatedSprite2D = caster._sprite
		var row: int = caster._dirs.find(sprite.sprite_frames)
		if row >= 0:
			aperture = sprite.to_global(CAST_APERTURE[row] - Vector2(64, 64) + sprite.offset)
			behind = row >= 4 and row <= 6
	p.launch_offset = aperture - start
	scene.add_child(p)
	ChaosFx.release(scene, aperture, d, p.power, behind)
	return cooldown
