class_name Projectile extends Area2D
## Straight-line projectile. Call setup(), tweak fields, then add_child().
## Default look: a fire / ice / death streak picked from `color`. Set arrow_tex for an arrow frame instead.

const SPELL := "res://assets/isometric_projecttile/Spells/%sSpell/0011.png"
const ARROW_SCALE := 0.5   ## the arrow frames are ~200 px long

var velocity := Vector2.ZERO
var damage := 10
var pierce := 0            ## extra targets it passes through
var life := 1.5
var radius := 10.0
var from_player := true
var source: Node
var silent := false          ## rapid-fire hits: no knockback / shake / hit-stop on enemies
var shove := 0.0             ## extra launch speed along the flight line, on top of the hit's own knockback
var stun := 0.0              ## stun on a hit that lands; grows toward stun_far as the shot nears stun_dist px of flight
var stun_far := 0.0
var stun_dist := 1.0
var target: Node2D           ## lock-on: steers at this foe until it dashes, phases or goes down. Cover still blocks the shot
var _flown := 0.0
var arrow_tex := ""
var color := Color(1.0, 0.55, 0.15)
var _hit: Array[Node] = []
static var _used: Dictionary = {}   ## texture -> opaque rect, so the streak's tip sits on the hitbox

func setup(pos: Vector2, vel: Vector2, dmg: int, player_owned: bool, src: Node = null) -> Projectile:
	position = pos
	velocity = vel
	damage = dmg
	from_player = player_owned
	source = src
	return self

func _ready() -> void:
	add_to_group("projectiles")   # bots dodge these
	collision_layer = 8 if from_player else 16
	collision_mask = 2 | 1   # PvP: everything player-fired or enemy-fired hits players (never its own caster, see _on_body_entered)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	add_child(shape)
	body_entered.connect(_on_body_entered)

func _draw() -> void:
	var path := arrow_tex
	if path == "":
		path = SPELL % ("Ice" if color.b > color.r else ("Death" if color.b > 0.6 else "Fire"))
	var tex: Texture2D = load(path)
	if not _used.has(tex):
		_used[tex] = Rect2(tex.get_image().get_used_rect())
	var r: Rect2 = _used[tex]
	var k := ARROW_SCALE if arrow_tex != "" else 1.0
	draw_set_transform(Vector2.ZERO, velocity.angle(), Vector2.ONE * k)
	draw_texture_rect_region(tex, Rect2(Vector2(radius / k - r.size.x, -r.size.y / 2.0), r.size), r)

func _physics_process(delta: float) -> void:
	if target != null:
		if not is_instance_valid(target) or target.down or (target.has_method("dodging") and target.dodging()):
			target = null   # shaken off: it flies on straight and can still be sidestepped
		else:
			velocity = (target.global_position + Vector2(0, 8) - global_position).normalized() * velocity.length()
			queue_redraw()
	position += velocity * delta
	_flown += velocity.length() * delta
	life -= delta
	if life <= 0.0:
		queue_free()

func _on_body_entered(body: Node) -> void:
	if body == source or ("down" in body and body.down):   # never the caster; downed players are walked through
		return
	if body.has_method("phased") and body.phased():   # a Shadow Step is untargetable
		return
	if body.has_method("take_damage"):
		if body in _hit:
			return
		_hit.append(body)
		var landed: bool = body.take_damage(damage, global_position, silent and from_player, source) == true   # PvE enemies return nothing
		if landed and maxf(stun, stun_far) > 0.0:
			Spell.stun(body, lerpf(stun, maxf(stun, stun_far), clampf(_flown / stun_dist, 0.0, 1.0)))
		if body == target:
			target = null   # a piercing shot flies on straight
		if shove > 0.0:
			Spell.shove(body, velocity.normalized() * shove)
		if pierce > 0:
			pierce -= 1
			return
	SheetFrames.play_once(get_parent(), global_position, SheetFrames.FX + "AoE/FireAoE/", 0, 40.0, 0.12)
	queue_free()
