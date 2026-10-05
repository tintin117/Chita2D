class_name Player extends CharacterBody2D
## Wizard: move, aim, dash (charges), 4 spell slots. Input actions are prefixed p1_ / p2_.

signal hp_changed(hp: int, max_hp: int)
signal downed

const SLOTS := ["basic", "spell1", "spell2", "signature"]
const MAX_DASH := 3
const MAX_CHARGE := 100.0
const DASH_SPEED := 1500.0
const DASH_TIME := 0.16
const DASH_RECHARGE := 1.5
const AIM_REACH := 280.0   ## aim_pos distance for stick aiming

@export var player_index := 0
@export var max_hp := 100
@export var speed := 260.0
@export var spells: Array[Spell] = []
var hero: Hero              ## set before add_child; defaults to the Wizard

var hp := 0
var down := false
var aim_dir := Vector2.RIGHT
var aim_pos := Vector2.ZERO
var cooldowns: Array[float] = [0.0, 0.0, 0.0, 0.0]
var cooldown_max: Array[float] = [1.0, 1.0, 1.0, 1.0]  ## last applied cooldown, for HUD
var dash_charges := MAX_DASH
var dash_recharge := 0.0
var signature_charge := 0.0
var knock := Vector2.ZERO
var _p := "p1_"
var _dash_time := 0.0
var _dash_vec := Vector2.RIGHT
var _dash_speed := DASH_SPEED
var _cast_time := 0.0
var _iframes := 0.0
var _sprite: AnimatedSprite2D

## Closest living player, or null.
static func nearest_alive(tree: SceneTree, pos: Vector2) -> Player:
	var best: Player = null
	for n in tree.get_nodes_in_group("players"):
		var p := n as Player
		if p and not p.down and (best == null or p.global_position.distance_squared_to(pos) < best.global_position.distance_squared_to(pos)):
			best = p
	return best

func _ready() -> void:
	add_to_group("players")
	collision_layer = 2
	collision_mask = 1
	_p = "p%d_" % (player_index + 1)
	if hero == null:
		hero = Hero.by_id("wizard")
	max_hp = hero.max_hp
	speed = hero.speed
	hp = max_hp
	if spells.is_empty():
		spells = hero.make_kit()
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 14.0
	shape.shape = circle
	shape.position = Vector2(0, 14)
	add_child(shape)
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = hero.frames(["Blue", "Yellow"][player_index % 2])
	_sprite.offset = Vector2(0, -4)  # sprite art sits slightly below frame center
	add_child(_sprite)
	_sprite.play("idle")
	hp_changed.emit(hp, max_hp)

func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	if down:
		return
	var move := Input.get_vector(_p + "left", _p + "right", _p + "up", _p + "down")
	_update_aim(move)
	if _dash_time > 0.0:
		_dash_time -= delta
		velocity = _dash_vec * _dash_speed
	else:
		if Input.is_action_just_pressed(_p + "dash") and dash_charges > 0:
			_start_dash(move)
		velocity = move * speed
		_try_cast()
	velocity += knock
	move_and_slide()
	_animate(move)

func _tick_timers(delta: float) -> void:
	_iframes = maxf(_iframes - delta, 0.0)
	_cast_time = maxf(_cast_time - delta, 0.0)
	knock = knock.move_toward(Vector2.ZERO, 1800.0 * delta)
	for i in cooldowns.size():
		cooldowns[i] = maxf(cooldowns[i] - delta, 0.0)
	if dash_charges < MAX_DASH:
		dash_recharge -= delta
		if dash_recharge <= 0.0:
			dash_charges += 1
			dash_recharge = DASH_RECHARGE

func _update_aim(move: Vector2) -> void:
	if player_index == 0:
		aim_pos = get_global_mouse_position()
		aim_dir = (aim_pos - global_position).normalized() if aim_pos.distance_to(global_position) > 4.0 else aim_dir
	else:
		var stick := Input.get_vector(_p + "aim_left", _p + "aim_right", _p + "aim_up", _p + "aim_down")
		if stick.length() > 0.3:
			aim_dir = stick.normalized()
		elif move != Vector2.ZERO:
			aim_dir = move.normalized()  # keyboard fallback: aim where you walk
		aim_pos = global_position + aim_dir * AIM_REACH

## Short forward burst without spending a dash charge (melee sweeps step into the target).
func lunge(vec: Vector2, time: float, spd: float) -> void:
	_dash_vec = vec.normalized()
	_dash_time = time
	_dash_speed = spd

func _start_dash(move: Vector2) -> void:
	dash_charges -= 1
	if dash_recharge <= 0.0:
		dash_recharge = DASH_RECHARGE
	_dash_vec = move if move != Vector2.ZERO else aim_dir
	_dash_time = DASH_TIME
	_dash_speed = DASH_SPEED
	_iframes = maxf(_iframes, DASH_TIME + 0.05)
	SheetFrames.play_once(get_parent(), global_position + Vector2(0, 20), "res://assets/tiny_swords/fx/Dust_01.png", 8, 24.0, 0.8)

func _try_cast() -> void:
	for i in SLOTS.size():
		var spell: Spell = spells[i] if i < spells.size() else null
		if spell and cooldowns[i] <= 0.0 and signature_charge >= spell.charge_cost and Input.is_action_pressed(_p + SLOTS[i]):
			signature_charge -= spell.charge_cost
			var cd := spell.cast(self, aim_dir, aim_pos)
			cooldowns[i] = cd
			cooldown_max[i] = cd
			_cast_time = 0.25
			_sprite.play("cast")
			return

func _animate(move: Vector2) -> void:
	_sprite.flip_h = aim_dir.x < 0.0
	if _cast_time > 0.0:
		return
	var anim := "run" if move != Vector2.ZERO else "idle"
	if _sprite.animation != anim:
		_sprite.play(anim)

## Called by projectiles/explosions when this player's attack lands: fills the signature meter.
func on_dealt_damage(amount: int) -> void:
	signature_charge = minf(signature_charge + amount * 0.8, MAX_CHARGE)

func take_damage(amount: int, from_pos: Vector2) -> void:
	if _iframes > 0.0 or down:
		return
	hp = maxi(hp - amount, 0)
	_iframes = 0.7
	knock = (global_position - from_pos).normalized() * 380.0
	_sprite.modulate = Color(1, 0.4, 0.4)
	create_tween().tween_property(_sprite, "modulate", Color.WHITE, 0.25)
	hp_changed.emit(hp, max_hp)
	if hp == 0:
		down = true
		velocity = Vector2.ZERO
		_sprite.modulate = Color(0.5, 0.5, 0.6, 0.6)
		_sprite.play("idle")
		downed.emit()

func revive(hp_fraction := 0.5) -> void:
	down = false
	hp = maxi(int(max_hp * hp_fraction), 1)
	_iframes = 1.5
	_sprite.modulate = Color.WHITE
	hp_changed.emit(hp, max_hp)

func heal(amount: int) -> void:
	if down:
		return
	hp = mini(hp + amount, max_hp)
	hp_changed.emit(hp, max_hp)
