class_name Dummy extends StaticBody2D
## Training dummy for the gym: takes any hit, never dies, shows floating damage and a rolling DPS readout.
## It also has a facing (aim_dir, drawn as an arrow) so backstabs, Shadow Rush and Bulwark-style checks can be tried,
## slides when knocked back (then walks home), and shows STUNNED / FROZEN when a hold lands.

const WINDOW := 3.0   ## seconds of hits the DPS number averages over

var down := false     ## Spell.foes / Projectile read this off every target
var knock := Vector2.ZERO   ## shoves (Spell.shove) land here: the dummy slides, then walks back to `home`
var aim_dir := Vector2.LEFT ## its facing: hits from the other side are backstabs
var home := Vector2.INF
var burn := 0               ## Kindling stacks, ticked like a player's so the gym shows the burn adding up
var _burn_by: Node = null
var _burn_tick := 0.0
var _burn_decay := 0.0
var _burning := false
var _status := ""
var _status_left := 0.0
var _hits: Array[Vector2] = []   ## (time, damage)
var _label: Label

func _ready() -> void:
	add_to_group("dummies")
	collision_layer = 3   # world + players: solid for the hero, and every projectile mask sees it
	collision_mask = 0
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 22.0
	cs.shape = circle
	cs.position = Vector2(0, 8)
	add_child(cs)
	_label = Label.new()
	_label.size = Vector2(160, 24)
	_label.position = Vector2(-80, -112)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 5)
	_label.z_index = 50
	add_child(_label)

func _physics_process(delta: float) -> void:
	if home == Vector2.INF:
		home = position
	if knock.length() > 1.0:
		position += knock * delta
		knock = knock.move_toward(Vector2.ZERO, Player.KNOCK_DECEL * delta)
	elif position.distance_to(home) > 2.0:
		position = position.move_toward(home, 220.0 * delta)
	_status_left = maxf(_status_left - delta, 0.0)
	if burn > 0:
		_burn_tick -= delta
		if _burn_tick <= 0.0:
			_burn_tick += Player.BURN_TICK
			_burning = true
			take_damage(burn, global_position, true, _burn_by if is_instance_valid(_burn_by) else null)
			_burning = false
		_burn_decay -= delta
		if _burn_decay <= 0.0:
			_burn_decay += Player.BURN_DECAY
			burn -= 1
	queue_redraw()

## Holds do nothing to a dummy but say so, so the gym shows which hits stun or freeze.
func stun(secs: float) -> void:
	_show_status("STUNNED %.1fs" % secs, secs)

func freeze(secs: float) -> void:
	_show_status("FROZEN %.1fs" % secs, secs)

func _show_status(text: String, secs: float) -> void:
	_status = text
	_status_left = secs

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	while not _hits.is_empty() and now - _hits[0].x > WINDOW:
		_hits.pop_front()
	var total := 0.0
	for h in _hits:
		total += h.y
	_label.text = "DPS %d" % roundi(total / WINDOW)
	if _status_left > 0.0:
		_label.text += "   " + _status
	if burn > 0:
		_label.text += "   BURN %d" % burn

func _draw() -> void:
	var f := aim_dir.normalized() * 40.0 + Vector2(0, 14)   # facing arrow on the ground: its front
	draw_line(Vector2(0, 14), f, Color(0.4, 0.8, 1.0, 0.8), 3.0)
	draw_colored_polygon(PackedVector2Array([f + aim_dir.normalized() * 12.0, f + aim_dir.orthogonal() * 8.0, f - aim_dir.orthogonal() * 8.0]), Color(0.4, 0.8, 1.0, 0.8))
	if _status_left > 0.0:
		draw_arc(Vector2(0, 14), 30.0, 0.0, TAU, 24, Color(0.55, 0.85, 1.0) if _status.begins_with("FROZEN") else Color(1.0, 0.95, 0.4), 3.0)
	draw_rect(Rect2(-6, -34, 12, 50), Color(0.45, 0.3, 0.18))        # post
	draw_rect(Rect2(-26, -22, 52, 9), Color(0.55, 0.38, 0.22))       # arm
	draw_circle(Vector2(0, -46), 15, Color(0.85, 0.7, 0.42))         # straw head
	draw_arc(Vector2(0, -46), 15, 0.0, TAU, 24, Color(0.35, 0.22, 0.1), 2.0)
	for r in [11.0, 6.0]:
		draw_arc(Vector2(0, -46), r, 0.0, TAU, 20, Color(0.8, 0.2, 0.2), 2.0)   # target rings
	draw_rect(Rect2(-18, 16, 36, 8), Color(0.3, 0.2, 0.12))          # base

func take_damage(amount: int, _from_pos: Vector2, silent := false, _attacker: Node = null) -> bool:
	_hits.append(Vector2(Time.get_ticks_msec() / 1000.0, amount))
	if _attacker is Player and _attacker.owns():
		_attacker.on_hit_landed(amount)   # the gym is where an ult (and lifesteal) gets tried out
	if _attacker is Player and _attacker.hero and _attacker.hero.kindling and not _burning:
		if burn == 0:
			_burn_tick = Player.BURN_TICK
			_burn_decay = Player.BURN_DECAY
		burn = mini(burn + 1, Player.BURN_MAX)
		_burn_by = _attacker
	if not silent:
		Player.hit_fx(self, amount, true)   # the gym is where the hit feel gets tuned
	var l := Label.new()
	l.text = str(amount)
	l.modulate = Color(1, 0.85, 0.3)
	l.z_index = 100
	l.position = Vector2(randf_range(-30, 10), -80)
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	add_child(l)
	var t := create_tween().set_parallel()
	t.tween_property(l, "position:y", -130.0, 0.8)
	t.tween_property(l, "modulate:a", 0.0, 0.4).set_delay(0.4)
	t.chain().tween_callback(l.queue_free)
	modulate = Color(1, 0.6, 0.6)
	create_tween().tween_property(self, "modulate", Color.WHITE, 0.15)
	return true
