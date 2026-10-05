class_name Enemy extends CharacterBody2D
## One script, four behaviours (grunt / archer / lancer / boss). Every attack is telegraphed (windup state).

signal died(enemy: Enemy)

const UNITS := "res://assets/tiny_swords/units/%s/%s/%s"
const ARROW := "res://assets/tiny_swords/units/Red/Archer/Arrow.png"

@export_enum("grunt", "archer", "lancer", "boss") var kind := "grunt"
var hp_mult := 1.0       ## set by the spawner (scales with player count)

var max_hp := 40
var hp := 40
var speed := 120.0
var knock := Vector2.ZERO
var bar_y := -54.0
var _state := "chase"
var _t := 0.0            ## state timer
var _cd := 1.0           ## attack cooldown
var _dir := Vector2.RIGHT ## locked attack direction
var _strafe := 1.0
var _hit_player := false
var _move := "charge"    ## boss: which attack is being wound up
var _pattern := 0
var _hit_r := 46.0
var _charge_speed := 720.0
var _sprite: AnimatedSprite2D

func _ready() -> void:
	add_to_group("enemies")
	collision_layer = 4
	collision_mask = 1 | 4
	var color := "Red"
	var scale_f := 1.0
	var anims := {}
	match kind:
		"grunt":
			max_hp = 40; speed = 120.0
			anims = {"idle": [UNITS % [color, "Warrior", "Warrior_Idle.png"], 8, 8.0], "run": [UNITS % [color, "Warrior", "Warrior_Run.png"], 6, 10.0],
				"attack": [UNITS % [color, "Warrior", "Warrior_Attack1.png"], 4, 12.0, false]}
		"archer":
			max_hp = 25; speed = 100.0
			anims = {"idle": [UNITS % [color, "Archer", "Archer_Idle.png"], 6, 8.0], "run": [UNITS % [color, "Archer", "Archer_Run.png"], 4, 10.0],
				"attack": [UNITS % [color, "Archer", "Archer_Shoot.png"], 8, 16.0, false]}
		"lancer", "boss":
			if kind == "boss":
				color = "Black"; scale_f = 2.0
				max_hp = 700; speed = 95.0; bar_y = -150.0; _hit_r = 95.0; _charge_speed = 820.0
				add_to_group("boss")
			else:
				max_hp = 60; speed = 130.0; bar_y = -70.0
			anims = {"idle": [UNITS % [color, "Lancer", "Lancer_Idle.png"], 12, 8.0], "run": [UNITS % [color, "Lancer", "Lancer_Run.png"], 6, 10.0],
				"attack": [UNITS % [color, "Lancer", "Lancer_Right_Attack.png"], 3, 8.0]}
	max_hp = int(max_hp * hp_mult)
	hp = max_hp
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 16.0 * scale_f
	shape.shape = circle
	shape.position = Vector2(0, 14) * scale_f
	add_child(shape)
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = SheetFrames.build(anims)
	_sprite.offset = Vector2(0, -4)
	_sprite.scale = Vector2.ONE * scale_f
	add_child(_sprite)
	_sprite.play("idle")
	_strafe = 1.0 if randf() < 0.5 else -1.0
	_cd = randf_range(0.8, 1.6)

func _physics_process(delta: float) -> void:
	_t -= delta
	_cd -= delta
	knock = knock.move_toward(Vector2.ZERO, 1400.0 * delta)
	var target := Player.nearest_alive(get_tree(), global_position)
	var to := (target.global_position - global_position) if target else Vector2.ZERO
	var dist := to.length()
	var dir := to.normalized()
	velocity = Vector2.ZERO
	match _state:
		"chase":
			if target:
				_sprite.flip_h = dir.x < 0.0
				_chase(dir, dist)
		"windup":
			if _t <= 0.0:
				_strike()
		"charge":
			velocity = _dir * _charge_speed
			if not _hit_player:
				_charge_hit()
			if _t <= 0.0 or get_slide_collision_count() > 0:
				_enter("recover", 0.9)
		"recover":
			if _t <= 0.0:
				_state = "chase"
	velocity += knock
	move_and_slide()
	_animate()

func _chase(dir: Vector2, dist: float) -> void:
	match kind:
		"grunt":
			velocity = dir * speed
			if dist < 70.0 and _cd <= 0.0:
				_windup(dir, 0.35)
		"archer":
			if dist < 240.0:
				velocity = -dir * speed
			elif dist > 380.0:
				velocity = dir * speed
			else:
				velocity = dir.orthogonal() * speed * 0.4 * _strafe
			if dist < 520.0 and _cd <= 0.0:
				_windup(dir, 0.5)
		"lancer":
			velocity = dir * speed
			if dist < 340.0 and _cd <= 0.0:
				_windup(dir, 0.7)
		"boss":
			velocity = dir * speed
			if _cd <= 0.0:
				_move = ["charge", "ring", "summon"][_pattern % 3]
				_pattern += 1
				_windup(dir, 0.9 if _move == "charge" else 0.7)

func _windup(dir: Vector2, time: float) -> void:
	_dir = dir
	_enter("windup", time)
	_sprite.modulate = Color(1.6, 0.8, 0.8)
	queue_redraw()

func _enter(state: String, time: float) -> void:
	_state = state
	_t = time
	queue_redraw()

func _enraged() -> bool:
	return kind == "boss" and hp * 2 < max_hp

func _strike() -> void:
	_sprite.modulate = Color.WHITE
	_sprite.play("attack")
	_sprite.flip_h = _dir.x < 0.0
	match kind:
		"grunt":
			for p: Player in get_tree().get_nodes_in_group("players"):
				var off := p.global_position - global_position
				if not p.down and off.length() < 95.0 and off.normalized().dot(_dir) > 0.2:
					p.take_damage(12, global_position)
			_cd = 1.2
			_enter("recover", 0.6)
		"archer":
			_fire_arrow(_dir, 380.0, 8)
			_cd = 1.7
			_enter("recover", 0.7)
		"lancer":
			_start_charge(2.2)
		"boss":
			var rage := _enraged()
			_cd = 0.9 if rage else 1.5
			match _move:
				"charge":
					_start_charge(_cd)
				"ring":
					var n := 24 if rage else 14
					var off := randf() * TAU
					for i in n:
						_fire_arrow(Vector2.from_angle(off + TAU * i / n), 300.0, 10)
					_enter("recover", 0.8)
				"summon":
					for i in 2:
						var g := Enemy.new()
						g.kind = "grunt"
						g.hp_mult = hp_mult
						g.position = global_position + Vector2.from_angle(randf() * TAU) * 150.0
						get_parent().add_child(g)
						SheetFrames.play_once(get_parent(), g.position, "res://assets/tiny_swords/fx/Dust_02.png", 10, 20.0, 1.0)
					_enter("recover", 1.1)

func _start_charge(next_cd: float) -> void:
	_hit_player = false
	_cd = next_cd
	_enter("charge", 0.55 if kind == "boss" else 0.45)

func _fire_arrow(dir: Vector2, spd: float, dmg: int) -> void:
	var arrow := Projectile.new().setup(global_position + dir * 24.0 + Vector2(0, 8), dir * spd, dmg, false, self)
	arrow.arrow_tex = ARROW
	arrow.radius = 7.0
	arrow.life = 2.5
	get_parent().add_child(arrow)

func _charge_hit() -> void:
	for p: Player in get_tree().get_nodes_in_group("players"):
		if not p.down and p.global_position.distance_to(global_position) < _hit_r:
			p.take_damage(22 if kind == "boss" else 16, global_position)
			_hit_player = true

func _animate() -> void:
	if _sprite.animation == "attack" and _sprite.is_playing() and _state != "chase":
		return
	var anim := "run" if velocity.length() > 20.0 else "idle"
	if _sprite.animation != anim:
		_sprite.play(anim)

func _draw() -> void:
	if _state == "windup" and (kind == "lancer" or (kind == "boss" and _move == "charge")):
		var w := 16.0 if kind == "boss" else 8.0
		draw_line(Vector2(0, 14), Vector2(0, 14) + _dir * 520.0, Color(1, 0.2, 0.2, 0.45), w)
	if hp < max_hp and kind != "boss":
		draw_rect(Rect2(-20, bar_y, 40, 5), Color.BLACK)
		draw_rect(Rect2(-19, bar_y + 1, 38.0 * hp / max_hp, 3), Color(0.9, 0.2, 0.2))

func take_damage(amount: int, from_pos: Vector2) -> void:
	if hp <= 0:
		return
	hp -= amount
	if _state != "charge" and kind != "boss":
		knock = (global_position - from_pos).normalized() * 260.0
	_spawn_number(amount)
	if _state != "windup":
		_sprite.modulate = Color(2, 2, 2)
		create_tween().tween_property(_sprite, "modulate", Color.WHITE, 0.12)
	var cam := get_tree().get_first_node_in_group("camera") as GameCamera
	if cam:
		cam.shake(0.15)
		cam.hit_stop(0.04)
	queue_redraw()
	if hp <= 0:
		remove_from_group("enemies")
		remove_from_group("boss")
		died.emit(self)
		var big := 2.5 if kind == "boss" else 1.0
		SheetFrames.play_once(get_parent(), global_position, "res://assets/tiny_swords/fx/Dust_02.png", 10, 24.0, big)
		queue_free()

func _spawn_number(amount: int) -> void:
	var l := Label.new()
	l.text = str(amount)
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.position = global_position + Vector2(-8, bar_y - 6.0)
	l.z_index = 100
	get_parent().add_child(l)
	var t := l.create_tween().set_parallel(true)
	t.tween_property(l, "position:y", l.position.y - 40.0, 0.5)
	t.tween_property(l, "modulate:a", 0.0, 0.3).set_delay(0.25)
	t.chain().tween_callback(l.queue_free)
