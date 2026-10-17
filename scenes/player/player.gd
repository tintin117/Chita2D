class_name Player extends CharacterBody2D
## Wizard: move, aim, dash (charges), 4 spell slots. Input actions are prefixed p1_ / p2_.

signal hp_changed(hp: int, max_hp: int)
signal downed
signal stats_changed   ## level, skill rank or gear changed and stats were recomputed
signal bomb_touch(other: Player)   ## the hot-potato carrier (owner's peer only) touched `other`; the match decides the pass
signal emoted(player: Player)
signal fragged(victim: Player, killer_peer: int, cause: String)   ## online: emitted on every peer when a player dies (killer_peer 0 = no player; cause = "hit" | "fall" | "bomb")

const SLOTS := ["basic", "spell1", "spell2", "signature"]
const MAX_DASH := 3
const MAX_CHARGE := 100.0
const DASH_SPEED := 1500.0
const DASH_TIME := 0.16
const DASH_RECHARGE := 1.5
const AIM_REACH := 280.0   ## aim_pos distance for stick aiming
const BUFFER_TIME := 0.15  ## a press this close to coming off cooldown is queued, not dropped
const COLORS := ["Blue", "Yellow", "Red", "Black"]   ## Tiny Swords unit colours, by player_index % 4
const NAME_COLORS := [Color("5fa8ff"), Color("ffd84a"), Color("ff6a5f"), Color("b9b9c8"), Color("6fe08a"), Color("e08aff"), Color("ff9a3c"), Color("4fe3e3")]
const RESPAWN_TIME := 3.0
const ONLINE_HIT_IFRAMES := 0.15   ## offline a hit grants 0.7s; online that would swallow most basic attacks
const KNOCK_BASE := 420.0          ## launch speed of any hit; grows with damage (a 10-dmg hit slides ~140 px, a 45-dmg snipe ~500 px)
const KNOCK_PER_DMG := 14.0
const KNOCK_MAX := 1500.0
const KNOCK_DECEL := 1100.0
const SINK_TIME := 0.3             ## seconds over water before you drown
const LAST_HIT_WINDOW := 4.0       ## a fall within this long of a hit is credited to the hitter
const GIANT_SCALE := 1.8
const BOMB_FUSE := 8.0
const BOMB_GRACE := 1.2            ## after getting or passing the bomb, no passing for this long (no instant ping-pong)
const BOMB_PASS_DIST := 56.0
const EMOTES := ["Bonk!", "Haha", "Oops", "GG"]
const EMOTE_COOLDOWN := 1.5
const CHICKEN_SCALE := 0.7

@export var player_index := 0
var online := false         ## set by the match before add_child; the node's multiplayer authority is then the owning peer
var display_name := ""
var respawn_point := Callable()   ## online: returns a Vector2; set by the match
var water_check := Callable()     ## online: (Vector2) -> bool, true over water; set by the match (the arena has no shore walls)
var last_hit_peer := 0            ## peer of the last player to hurt this one (credited if they then fall in the water)
var last_hit_msec := 0
var rng := RandomNumberGenerator.new()   ## reseeded from every cast so all peers roll the same AoE layout
var net_pos := Vector2.ZERO   ## replicated; puppets ease toward it
@export var max_hp := 100
@export var speed := 260.0
@export var spells: Array[Spell] = []
var hero: Hero              ## set before add_child; defaults to the Wizard
var prog: Progression       ## XP, level, skill ranks; created by init_loadout()
var equipment := {}         ## Item.SLOTS entry -> Item
var damage_mult := 1.0      ## level * gear; already baked into spells[i].damage by recalc_stats()
var cooldown_mult := 1.0
var _base_spells: Array = []  ## [damage, cooldown] per slot before any bonus
var buffs := {}             ## PvP pickup kind -> expiry in seconds (Time.get_ticks_msec); kept on every peer so hits can read the attacker's

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
var _queued := -1          ## buffered slot index, -1 = none
var _queued_time := 0.0
var _puppet := false       ## online and owned by another peer: no input, position comes from net_pos
var _mouse_aim := true     ## P1 only: aim with the mouse until a gamepad is touched, then with the right stick
var _swing := false        ## alternates basic-attack animations (cast / cast2) when the hero has both
var _iframes := 0.0
var _sink := 0.0           ## seconds spent over water
var crowned := false: set = _set_crowned   ## wears the match crown (set by the match); drawn as a crown and a beam
var has_bomb := false      ## carrying the hot potato; every peer ticks bomb_left, the host decides when it blows
var bomb_left := 0.0
var _bomb_grace := 0.0
var _bomb_tick := 0.0
var _cluck_at := 0
var _emote_cd := 0.0
var _emote_text := ""
var _emote_until := 0
var _shape: CircleShape2D
var _sprite: AnimatedSprite2D

## Launch speed for a hit of `amount` damage.
static func knock_for(amount: int) -> float:
	return minf(KNOCK_BASE + amount * KNOCK_PER_DMG, KNOCK_MAX)

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
	_p = "p1_" if online else "p%d_" % (player_index + 1)
	_puppet = online and not is_multiplayer_authority()
	if hero == null:
		hero = Hero.by_id("wizard")
	init_loadout()
	RuleSet.current.changed.connect(recalc_stats)   # slot-machine rules change max HP / speed / cooldowns
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 14.0
	_shape = circle
	shape.shape = circle
	shape.position = Vector2(0, 14)
	add_child(shape)
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = hero.frames(COLORS[player_index % COLORS.size()])
	_sprite.offset = Vector2(0, -4)  # sprite art sits slightly below frame center
	add_child(_sprite)
	_sprite.play("idle")
	add_child(OverheadHpBar.new())
	if online:
		_setup_online()
	hp_changed.emit(hp, max_hp)

func _setup_online() -> void:
	net_pos = position
	var cfg := SceneReplicationConfig.new()
	for prop in [":net_pos", ":aim_dir", ":aim_pos"]:
		cfg.add_property(NodePath(prop))
		cfg.property_set_replication_mode(NodePath(prop), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	sync.replication_config = cfg
	sync.replication_interval = 0.033
	sync.set_multiplayer_authority(get_multiplayer_authority())   # children added after set_multiplayer_authority do not inherit it
	add_child(sync)
	var label := Label.new()
	label.text = display_name
	label.size = Vector2(160, 20)
	label.position = Vector2(-80, -78)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.modulate = NAME_COLORS[player_index % NAME_COLORS.size()]
	label.z_index = 50
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	add_child(label)

## Builds the kit, progression and stats from the hero. Called by _ready (callable without a tree, for tests).
func init_loadout() -> void:
	if hero == null:
		hero = Hero.by_id("wizard")
	prog = Progression.new()
	prog.changed.connect(recalc_stats)
	prog.leveled_up.connect(_on_level_up)
	prog.rewarded.connect(_on_reward)
	if spells.is_empty():
		spells = hero.make_kit()
	_base_spells.clear()
	for s in spells:
		_base_spells.append([s.damage, s.cooldown])
	max_hp = 0
	recalc_stats()
	hp = max_hp

## Stats = hero base + level/power + gear; spell damage and cooldown also scale with skill rank.
func recalc_stats() -> void:
	var old_max := max_hp
	var rules := RuleSet.current
	max_hp = int((hero.max_hp + prog.hp_bonus() + int(_gear("max_hp"))) * rules.hp)
	speed = hero.speed * (1.0 + prog.speed_bonus() + _gear("speed")) * rules.speed
	damage_mult = (1.0 + prog.damage_bonus()) * (1.0 + _gear("damage"))
	cooldown_mult = maxf(1.0 - _gear("cooldown"), 0.5) / rules.attack_rate
	for i in mini(spells.size(), _base_spells.size()):
		spells[i].damage = roundi(_base_spells[i][0] * damage_mult * prog.skill_damage_mult(i))
		spells[i].cooldown = _base_spells[i][1] * cooldown_mult * prog.skill_cooldown_mult(i)
	if not down:
		hp = clampi(hp + maxi(max_hp - old_max, 0), 0, max_hp)  # gaining max HP heals the gain
	hp_changed.emit(hp, max_hp)
	stats_changed.emit()

func _gear(key: String) -> float:
	var total := 0.0
	for it: Item in equipment.values():
		total += it.mods.get(key, 0.0)
	return total

## Equips item if its slot is empty or it is a rarer item than the current one. Returns whether it was taken.
func try_equip(item: Item) -> bool:
	var cur: Item = equipment.get(item.slot)
	if cur != null and cur.rarity >= item.rarity:
		return false
	equipment[item.slot] = item
	recalc_stats()
	float_text(item.display_name, item.color())
	return true

func _on_level_up(lv: int) -> void:
	if not down:
		hp = max_hp
		hp_changed.emit(hp, max_hp)
	float_text("LEVEL %d" % lv, Color(1.0, 0.85, 0.3))

func _on_reward(kind: String) -> void:
	if kind == "power":
		heal(int(max_hp * 0.4))
		float_text("POWER UP", Color(1.0, 0.5, 0.3))

const BUFF_TIME := 10.0
const SPEED_BUFF := 1.5

func buffed(kind: String) -> bool:
	return buff_left(kind) > 0.0

func buff_left(kind: String) -> float:
	return maxf(buffs.get(kind, 0.0) - Time.get_ticks_msec() / 1000.0, 0.0)

## A PvP pickup was taken by this player. Runs on every peer; only the owner touches its own HP.
func apply_pickup(kind: String) -> void:
	float_text(PvpPickup.LABELS[kind], PvpPickup.COLORS[kind])
	match kind:
		"heal":
			if is_multiplayer_authority():
				heal(int(max_hp * 0.5))
				_net_hp.rpc(hp)
		"bomb":
			give_bomb(BOMB_FUSE)
		_:   # damage / speed / giant / chicken: timed forms, read from the buffs on every peer
			buffs[kind] = Time.get_ticks_msec() / 1000.0 + BUFF_TIME

func _speed_mult() -> float:
	var m := SPEED_BUFF if buffed("speed") else 1.0
	if buffed("giant"):
		m *= 0.8
	if buffed("chicken"):
		m *= 1.8
	return m

## Damage after the victim's own form: giant takes 40% less, chicken 50% more.
func form_damage(amount: int) -> int:
	if buffed("giant"):
		return roundi(amount * 0.6)
	if buffed("chicken"):
		return roundi(amount * 1.5)
	return amount

## Launch multiplier from the attacker's form (giant hits harder) and the victim's (giant is heavy).
func form_knock(attacker: Node) -> float:
	var m := 1.0
	if attacker is Player and attacker.buffed("giant"):
		m *= 1.6
	if buffed("giant"):
		m *= 0.5
	return m

# --- hot potato

func give_bomb(fuse: float) -> void:
	has_bomb = true
	bomb_left = fuse
	_bomb_grace = BOMB_GRACE
	_bomb_tick = 0.0
	queue_redraw()

func clear_bomb() -> void:
	has_bomb = false
	bomb_left = 0.0
	_bomb_grace = BOMB_GRACE   # the player who just passed it can't take it straight back
	queue_redraw()

func _tick_bomb(delta: float) -> void:
	_bomb_grace = maxf(_bomb_grace - delta, 0.0)
	if not has_bomb or down:
		return
	bomb_left -= delta
	_bomb_tick -= delta
	if _bomb_tick <= 0.0:
		Sfx.play("bomb_tick", global_position)
		_bomb_tick = clampf(bomb_left * 0.12, 0.12, 0.8)   # ticks faster as the fuse burns down
	queue_redraw()
	if _puppet or _bomb_grace > 0.0:
		return
	for n in get_tree().get_nodes_in_group("players"):
		var o := n as Player
		if o and o != self and not o.down and not o.has_bomb and o.global_position.distance_to(global_position) < BOMB_PASS_DIST:
			_bomb_grace = BOMB_GRACE   # one request per touch; the host answers with the real pass
			bomb_touch.emit(o)
			return

func _set_crowned(v: bool) -> void:
	crowned = v
	queue_redraw()

func _draw() -> void:
	if crowned and not down:
		var beam := Color(1.0, 0.85, 0.3, 0.3)
		draw_polygon(PackedVector2Array([Vector2(-20, 14), Vector2(20, 14), Vector2(9, -520), Vector2(-9, -520)]),
			PackedColorArray([beam, beam, Color(beam, 0.0), Color(beam, 0.0)]))
		var c := PackedVector2Array([Vector2(-14, -92), Vector2(-14, -108), Vector2(-7, -100), Vector2(0, -112), Vector2(7, -100), Vector2(14, -108), Vector2(14, -92)])
		draw_colored_polygon(c, Color(1.0, 0.85, 0.3))
		draw_polyline(c + PackedVector2Array([c[0]]), Color.BLACK, 2.0)
	if not has_bomb or down:
		return
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * (0.01 + 0.02 / maxf(bomb_left, 0.5)))
	draw_arc(Vector2(0, 14), 42.0 + pulse * 6.0, 0.0, TAU, 32, Color(1.0, 0.25, 0.2, 0.9), 4.0)
	draw_circle(Vector2(0, 14), 40.0, Color(1.0, 0.2, 0.15, 0.12 + 0.18 * pulse))
	draw_string(ThemeDB.fallback_font, Vector2(-30, -104), "%.1f" % maxf(bomb_left, 0.0), HORIZONTAL_ALIGNMENT_CENTER, 60, 22, Color(1.0, 0.6, 0.3))

# --- emotes

func _try_emote() -> void:
	_emote_cd = maxf(_emote_cd - get_physics_process_delta_time(), 0.0)
	if _emote_cd > 0.0:
		return
	for i in EMOTES.size():
		if Input.is_action_just_pressed("emote_%d" % (i + 1)):
			_emote_cd = EMOTE_COOLDOWN
			_net_emote.rpc(i)
			return

@rpc("authority", "call_local", "reliable")
func _net_emote(idx: int) -> void:
	if idx < 0 or idx >= EMOTES.size():
		return
	Sfx.play("emote", global_position)
	float_text(EMOTES[idx], NAME_COLORS[player_index % NAME_COLORS.size()], 30)
	emoted.emit(self)

func float_text(text: String, color: Color, font_size := 18) -> void:
	if not is_inside_tree():
		return
	var l := Label.new()
	l.text = text
	l.modulate = color
	l.z_index = 100
	l.size = Vector2(160, 24)
	l.position = Vector2(-80, -90)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	add_child(l)
	var t := create_tween().set_parallel()
	t.tween_property(l, "position:y", -140.0, 1.2)
	t.tween_property(l, "modulate:a", 0.0, 0.6).set_delay(0.7)
	t.chain().tween_callback(l.queue_free)

func _input(event: InputEvent) -> void:
	if _puppet or (player_index != 0 and not online):
		return
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		_mouse_aim = true
	elif event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5):
		_mouse_aim = false

func _physics_process(delta: float) -> void:
	_tick_bomb(delta)
	if _puppet:
		_puppet_tick(delta)
		return
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
		velocity = Vector2.ZERO if _firing() else move * speed * _speed_mult()  # hold attack = stand still, aim with move input
		_try_cast()
		_try_emote()
	velocity += knock
	move_and_slide()
	net_pos = position
	_animate(move)
	if _update_sink(delta):
		_fall()
	_apply_look()

## Another peer's player: ease toward the replicated position, animate from the movement.
func _puppet_tick(delta: float) -> void:
	_cast_time = maxf(_cast_time - delta, 0.0)
	_update_sink(delta)   # puppets only show the sinking; the owner decides when it kills
	_apply_look()
	if down:
		return
	var off := net_pos - position
	position = net_pos if off.length() > 300.0 else position.lerp(net_pos, 1.0 - exp(-20.0 * delta))
	_animate(off if off.length() > 3.0 else Vector2.ZERO)

## Counts time over water (shared by owner and puppets so everyone sees the sinking). True once the drowning is complete.
func _update_sink(delta: float) -> bool:
	if down or not water_check.is_valid():
		return false
	if water_check.call(global_position + Vector2(0, 14)):
		if _sink == 0.0:
			Sfx.play("splash", global_position)
			SheetFrames.play_once(get_parent(), global_position + Vector2(0, 20), "res://assets/tiny_swords/fx/Dust_01.png", 8, 24.0, 1.0).modulate = Color(0.55, 0.75, 1.0)
		_sink += delta
	else:
		_sink = 0.0
	return _sink >= SINK_TIME

## Size, tint and wobble from the active forms (giant / chicken) and the sinking fade. self_modulate, so _flash() keeps its own tween.
func _apply_look() -> void:
	var s := 1.0
	var tint := Color.WHITE
	_sprite.rotation = 0.0
	if buffed("giant"):
		s = GIANT_SCALE
	elif buffed("chicken"):
		s = CHICKEN_SCALE
		tint = Color(1.0, 0.95, 0.4)
		_sprite.rotation = sin(Time.get_ticks_msec() * 0.03) * 0.15
	if buffed("chicken") and Time.get_ticks_msec() > _cluck_at:
		Sfx.play("cluck", global_position)
		_cluck_at = Time.get_ticks_msec() + randi_range(900, 1500)
	_shape.radius = 14.0 * maxf(s, 1.0)   # a giant is also harder to miss
	var sink := clampf(_sink / SINK_TIME, 0.0, 1.0)
	_sprite.scale = Vector2.ONE * s * (1.0 - 0.7 * sink)
	_sprite.position = Vector2(0, -(s - 1.0) * 20.0)   # keep the feet on the ground while resizing
	_sprite.self_modulate = Color(tint, 1.0 - sink)

## Drowned: the owner announces the death, crediting the last player who hit us recently.
func _fall() -> void:
	var killer := last_hit_peer if Time.get_ticks_msec() - last_hit_msec < LAST_HIT_WINDOW * 1000.0 else 0
	_net_died.rpc(killer, "fall")

func _tick_timers(delta: float) -> void:
	_iframes = maxf(_iframes - delta, 0.0)
	_cast_time = maxf(_cast_time - delta, 0.0)
	_queued_time -= delta
	if _queued_time <= 0.0:
		_queued = -1
	knock = knock.move_toward(Vector2.ZERO, KNOCK_DECEL * delta)
	for i in cooldowns.size():
		cooldowns[i] = maxf(cooldowns[i] - delta, 0.0)
	if dash_charges < MAX_DASH:
		dash_recharge -= delta
		if dash_recharge <= 0.0:
			dash_charges += 1
			dash_recharge = DASH_RECHARGE

func _update_aim(move: Vector2) -> void:
	if (player_index == 0 or online) and _mouse_aim:
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
	_cast_time = 0.0  # dash cancels the cast lock
	Sfx.play("dash", global_position)
	_dash_vec = move if move != Vector2.ZERO else aim_dir
	_dash_time = DASH_TIME
	_dash_speed = DASH_SPEED
	_iframes = maxf(_iframes, DASH_TIME + 0.05)
	SheetFrames.play_once(get_parent(), global_position + Vector2(0, 20), "res://assets/tiny_swords/fx/Dust_01.png", 8, 24.0, 0.8)

## True while an attack button is held or the cast anim is still playing (no gap between rapid taps).
func _firing() -> bool:
	if _cast_time > 0.0 or _queued >= 0:
		return true
	if _puppet:
		return false
	for slot in SLOTS:
		if Input.is_action_pressed(_p + slot):
			return true
	return false

func _try_cast() -> void:
	if buffed("chicken"):
		return
	for i in SLOTS.size():
		if Input.is_action_just_pressed(_p + SLOTS[i]) and cooldowns[i] > 0.0:
			_queued = i
			_queued_time = BUFFER_TIME
	for i in SLOTS.size():
		var spell: Spell = spells[i] if i < spells.size() else null
		if spell and cooldowns[i] <= 0.0 and signature_charge >= spell.charge_cost and (_queued == i or Input.is_action_pressed(_p + SLOTS[i])):
			signature_charge -= spell.charge_cost
			_queued = -1
			_net_cast.rpc(i, aim_dir, aim_pos, randi())
			return

## Runs on every peer (offline: just here), so every screen gets the same projectiles / sweeps / explosions.
## Damage still only lands on the victim's own peer (see take_damage).
@rpc("authority", "call_local", "reliable")
func _net_cast(slot: int, dir: Vector2, pos: Vector2, seed_value: int) -> void:
	var spell: Spell = spells[slot]
	rng.seed = seed_value
	var cd := spell.cast(self, dir, pos)
	cooldowns[slot] = cd
	cooldown_max[slot] = cd
	_cast_time = clampf(cd, 0.25, 0.4)  # cover fast-attack cooldowns so tapping never unlocks movement
	_play_cast(slot)

## Alternates cast / cast2 on the basic, and stretches the anim to exactly fill the cast lock.
func _play_cast(slot: int) -> void:
	Sfx.play(spells[slot].sfx, global_position)
	var anim := "cast"
	if slot == 0 and _sprite.sprite_frames.has_animation("cast2"):
		_swing = not _swing
		anim = "cast2" if _swing else "cast"
	var frames := _sprite.sprite_frames
	_sprite.speed_scale = frames.get_frame_count(anim) / frames.get_animation_speed(anim) / _cast_time
	_sprite.play(anim)

func _animate(move: Vector2) -> void:
	_sprite.flip_h = aim_dir.x < 0.0
	if _cast_time > 0.0:
		return
	_sprite.speed_scale = 1.0
	var anim := "run" if move != Vector2.ZERO and not _firing() else "idle"
	if _sprite.animation != anim:
		_sprite.play(anim)

## Called by projectiles/explosions when this player's attack lands: fills the signature meter.
func on_dealt_damage(amount: int) -> void:
	signature_charge = minf(signature_charge + amount * 0.8, MAX_CHARGE)

## Only the player's own peer applies damage; everyone else's copy of the same hit is a no-op (victim-side hits).
func take_damage(amount: int, from_pos: Vector2, silent := false, attacker: Node = null) -> void:
	if not is_multiplayer_authority() or _iframes > 0.0 or down:
		return
	if attacker is Player and attacker.buffed("damage"):   # victim-side hit: read the attacker's copy of the buff
		amount *= 2
	amount = form_damage(roundi(amount * RuleSet.current.damage))
	hp = maxi(hp - amount, 0)
	if attacker is Player:
		last_hit_peer = attacker.get_multiplayer_authority()
		last_hit_msec = Time.get_ticks_msec()
	if not silent:   # rapid-tick hits (blade storm, arrow barrage) neither stagger nor grant i-frames
		_iframes = ONLINE_HIT_IFRAMES if online else 0.7
		knock = (global_position - from_pos).normalized() * knock_for(amount) * form_knock(attacker)
	_flash()
	hp_changed.emit(hp, max_hp)
	if not online:
		if hp == 0:
			_die()
		return
	if hp == 0:
		_net_died.rpc(attacker.get_multiplayer_authority() if attacker is Player else 0, "hit" if attacker is Player else "bomb")   # no attacker = an ownerless Explosion (the hot potato)
	else:
		_net_hp.rpc(hp)

func _flash() -> void:
	_sprite.modulate = Color(1, 0.4, 0.4)
	create_tween().tween_property(_sprite, "modulate", Color.WHITE, 0.25)

func _die() -> void:
	down = true
	queue_redraw()
	buffs.clear()
	velocity = Vector2.ZERO
	_sprite.modulate = Color(0.5, 0.5, 0.6, 0.6)
	_sprite.play("idle")
	downed.emit()

@rpc("authority", "call_remote", "reliable")
func _net_hp(value: int) -> void:
	if value < hp:   # a heal must not flash red
		_flash()
	hp = value
	hp_changed.emit(hp, max_hp)

@rpc("authority", "call_local", "reliable")
func _net_died(killer_peer: int, cause: String) -> void:
	hp = 0
	hp_changed.emit(hp, max_hp)
	Sfx.play("death", global_position)
	_sink = SINK_TIME if cause == "fall" else 0.0   # a drowned player stays under until the respawn
	_die()
	fragged.emit(self, killer_peer, cause)
	if is_multiplayer_authority():
		get_tree().create_timer(RESPAWN_TIME).timeout.connect(_respawn)

func _respawn() -> void:
	if is_inside_tree():
		_net_respawn.rpc(respawn_point.call() if respawn_point.is_valid() else position)

@rpc("authority", "call_local", "reliable")
func _net_respawn(pos: Vector2) -> void:
	position = pos
	net_pos = pos
	knock = Vector2.ZERO
	revive(1.0)
	Sfx.play("respawn", pos)
	_iframes = 2.0

func revive(hp_fraction := 0.5) -> void:
	down = false
	queue_redraw()
	_sink = 0.0
	last_hit_peer = 0
	hp = maxi(int(max_hp * hp_fraction), 1)
	_iframes = 1.5
	_sprite.modulate = Color.WHITE
	hp_changed.emit(hp, max_hp)

func heal(amount: int) -> void:
	if down:
		return
	hp = mini(hp + amount, max_hp)
	hp_changed.emit(hp, max_hp)
