class_name Projectile extends Area2D
## Straight-line projectile. Call setup(), tweak fields, then add_child().
## Default look: glowing orb with a fire-puff trail. Set arrow_tex for a rotated sprite instead.

const PUFF := "res://assets/tiny_swords/fx/Fire_02.png"

var velocity := Vector2.ZERO
var damage := 10
var pierce := 0            ## extra targets it passes through
var life := 1.5
var radius := 10.0
var from_player := true
var source: Node
var arrow_tex := ""
var color := Color(1.0, 0.55, 0.15)
var _hit: Array[Node] = []
var _trail := 0.0

func setup(pos: Vector2, vel: Vector2, dmg: int, player_owned: bool, src: Node = null) -> Projectile:
	position = pos
	velocity = vel
	damage = dmg
	from_player = player_owned
	source = src
	return self

func _ready() -> void:
	collision_layer = 8 if from_player else 16
	collision_mask = (4 | 1) if from_player else (2 | 1)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	add_child(shape)
	if arrow_tex != "":
		var s := Sprite2D.new()
		s.texture = load(arrow_tex)
		s.rotation = velocity.angle()
		add_child(s)
	body_entered.connect(_on_body_entered)

func _draw() -> void:
	if arrow_tex == "":
		draw_circle(Vector2.ZERO, radius * 1.5, Color(color, 0.3))
		draw_circle(Vector2.ZERO, radius, color)
		draw_circle(Vector2.ZERO, radius * 0.5, Color(1, 0.95, 0.6))

func _physics_process(delta: float) -> void:
	position += velocity * delta
	life -= delta
	if life <= 0.0:
		queue_free()
	_trail -= delta
	if _trail <= 0.0 and arrow_tex == "":
		_trail = 0.05
		SheetFrames.play_once(get_parent(), global_position, PUFF, 10, 24.0, 0.7)

func _on_body_entered(body: Node) -> void:
	if body.has_method("take_damage"):
		if body in _hit:
			return
		_hit.append(body)
		body.take_damage(damage, global_position)
		if source and source.has_method("on_dealt_damage"):
			source.on_dealt_damage(damage)
		if pierce > 0:
			pierce -= 1
			return
	SheetFrames.play_once(get_parent(), global_position, "res://assets/tiny_swords/fx/Dust_01.png", 8, 24.0, 0.5)
	queue_free()
