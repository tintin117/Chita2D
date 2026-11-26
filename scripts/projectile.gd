class_name Projectile extends Area2D
## Straight-line projectile. Call setup(), tweak fields, then add_child().
## Default look: a fire / ice / death streak picked from `color`. Set arrow_tex to an arrow frame folder instead.
## Spells play their frame folder once, then loop from LOOP_FROM. Arrows start there: their launch frames are only a
## tiny dark shaft, too faint to see in flight.

const SPELL := "res://assets/isometric_projecttile/Spells/%sSpell/"
const ARROW_SCALE := Vector2(1.0, 2.0)   ## the art's shaft is only 14x2 px: stretched thicker so it reads in a fight
const ARROW_TIP := Vector2(295, 10)   ## the shaft's tip on the 512x26 arrow canvas: sits on the hitbox in every frame
const ARROW_CUT := Rect2(236, 0, 119, 26)   ## part of the canvas drawn: no pivot speck, no detached streak far ahead of the tip
const ARROW_EDGE := 2.0   ## px of dark outline: the pale streaks vanish on grass and sand without it
const EDGE_COLOR := Color(0.08, 0.05, 0.02, 0.9)
const ANIM_FPS := 30.0
const LOOP_FROM := {"Arrow": 5, "FireArrow": 2, "FireSpell": 3, "IceSpell": 5, "DeathSpell": 5}   ## frame index

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
var splash := 0.0           ## > 0: an orb. No direct hit: it bursts (this radius) on the first body it touches or when its life runs out
var trail := 0.0            ## length of a glowing streak drawn behind it (Power Shot), 0 = none
var tex_scale := 1.0
var impact_scale := 0.12    ## size of the burst where it stops
var slow := Vector2.ZERO    ## (speed multiplier, seconds) on a hit that lands (Stifling Dagger); zero = none        ## extra size of the sprite (Power Shot grows with the draw)
var _burst_done := false
var color := Color(1.0, 0.55, 0.15)
var _hit: Array[Node] = []
var _anim_t := 0.0
static var _used: Dictionary = {}   ## spell texture -> opaque rect: the head moves across the canvas, so align each frame by it

## Which of `count` frames shows `t` seconds into a flight that opened on frame `start`.
static func frame_at(t: float, count: int, loop_from: int, start := 0) -> int:
	var i := start + int(t * ANIM_FPS)
	return i if i < count else loop_from + (i - count) % (count - loop_from)

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
	if trail > 0.0:   # the streak sits behind the tip, along the flight
		draw_set_transform(Vector2.ZERO, velocity.angle(), Vector2.ONE)
		draw_line(Vector2(-trail, 0), Vector2.ZERO, Color(color, 0.25), radius * 2.2)
		draw_line(Vector2(-trail * 0.6, 0), Vector2.ZERO, Color(1, 1, 1, 0.6), 3.0)
	if splash > 0.0:   # an orb: a glowing ball, not a bolt sprite, so the Mage's basic never reads as a gun
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.03)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_circle(Vector2.ZERO, radius * (1.5 + 0.2 * pulse), Color(color, 0.25))
		draw_circle(Vector2.ZERO, radius, color)
		draw_circle(Vector2(-3, -3), radius * 0.45, Color(1, 1, 0.9, 0.9))
		draw_line(Vector2.ZERO, -velocity.normalized() * radius * 2.5, Color(color, 0.4), radius)
		return
	var dir := arrow_tex
	if dir == "":
		dir = SPELL % ("Ice" if color.b > color.r else ("Death" if color.b > 0.6 else "Fire"))
	var frames := SheetFrames.seq(dir)
	var loop: int = LOOP_FROM[dir.trim_suffix("/").get_file()]
	var i := frame_at(_anim_t, frames.get_frame_count("fx"), loop, loop if arrow_tex != "" else 0)
	var tex := frames.get_frame_texture("fx", i)
	var k := (ARROW_SCALE if arrow_tex != "" else Vector2.ONE) * tex_scale
	draw_set_transform(Vector2.ZERO, velocity.angle(), k)
	if arrow_tex != "":
		var at := Rect2(Vector2(radius / k.x, 0) + ARROW_CUT.position - ARROW_TIP, ARROW_CUT.size)
		for side: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			draw_texture_rect_region(tex, Rect2(at.position + side * ARROW_EDGE / k, at.size), ARROW_CUT, EDGE_COLOR)
		draw_texture_rect_region(tex, at, ARROW_CUT)
		return
	if not _used.has(tex):
		_used[tex] = Rect2(tex.get_image().get_used_rect())
	var r: Rect2 = _used[tex]
	draw_texture_rect_region(tex, Rect2(Vector2(radius / k.x - r.size.x, -r.size.y / 2.0), r.size), r)

func _physics_process(delta: float) -> void:
	if target != null:
		if not is_instance_valid(target) or target.down or (target.has_method("dodging") and target.dodging()):
			target = null   # shaken off: it flies on straight and can still be sidestepped
		else:
			velocity = (target.global_position + Vector2(0, 8) - global_position).normalized() * velocity.length()
	position += velocity * delta
	_flown += velocity.length() * delta
	_anim_t += delta
	queue_redraw()   # next animation frame / the orb pulses
	life -= delta
	if life <= 0.0:
		if splash > 0.0:
			_burst()   # an orb that reached the cursor goes off there
		else:
			queue_free()

func _on_body_entered(body: Node) -> void:
	if body == source or ("down" in body and body.down):   # never the caster; downed players are walked through
		return
	if body.has_method("phased") and body.phased():   # a Shadow Step is untargetable
		return
	if splash > 0.0:   # an orb bursts on the first foe or rock it meets; the burst does the damage
		_burst()
		return
	if body.has_method("take_damage"):
		if body in _hit:
			return
		_hit.append(body)
		var landed: bool = body.take_damage(damage, global_position, silent and from_player, source) == true   # PvE enemies return nothing
		if landed and slow.y > 0.0 and body.has_method("apply_slow"):
			body.apply_slow(slow.x, slow.y)
		if landed and maxf(stun, stun_far) > 0.0:
			Spell.stun(body, lerpf(stun, maxf(stun, stun_far), clampf(_flown / stun_dist, 0.0, 1.0)))
		if body == target:
			target = null   # a piercing shot flies on straight
		if shove > 0.0:
			Spell.shove(body, velocity.normalized() * shove)
		if pierce > 0:
			pierce -= 1
			return
	SheetFrames.play_once(get_parent(), global_position, SheetFrames.FX + "AoE/FireAoE/", 0, 40.0, impact_scale)
	queue_free()

## Orb burst: everyone hostile within `splash` takes `damage` once (the one it touched included). Runs on every peer;
## damage lands on each victim's own peer like any hit.
func _burst() -> void:
	if _burst_done:
		return
	_burst_done = true
	SheetFrames.play_once(get_parent(), global_position, SheetFrames.FX + "AoE/FireAoE/", 0, 34.0, splash / 120.0)
	Sfx.play("explosion", global_position, -9.0, 1.5)
	if is_instance_valid(source) and source is Node2D and source.is_inside_tree():
		for e in Spell.foes(source):
			if e.global_position.distance_to(global_position) <= splash + 14.0:
				e.take_damage(damage, global_position, silent, source)
	queue_free()
