class_name Player extends CharacterBody2D
## A hero: move, aim, dash (charges, passes through rocks), and two skills: basic (LMB) and one signature skill (RMB). Input actions are prefixed p1_ / p2_.

signal hp_changed(hp: int, max_hp: int)
signal downed
signal stats_changed   ## level, skill rank or gear changed and stats were recomputed
signal bomb_touch(other: Player)   ## the hot-potato carrier (owner's peer only) touched `other`; the match decides the pass
signal emoted(player: Player)
signal fragged(victim: Player, killer_peer: int, cause: String)   ## online: emitted on every peer when a player dies (killer_peer 0 = no player; cause = "hit" | "fall" | "bomb")

const SLOTS := ["basic", "skill"]   ## input action suffixes; slot 0 = LMB basic, slot 1 = RMB skill
const SOLID_MASK := 1    ## collision layer of rocks and the dummy
const WALL_MASK := 32    ## collision layer of the hard room walls (rocks are not on it): a dash never passes these
const MAX_DASH := 2         ## the dash is what shakes off a lock-on, so it is scarce: one escape, one spare
const DASH_SPEED := 1500.0
const DASH_TIME := 0.16
const DASH_RECHARGE := 2.5
const AIM_REACH := 280.0   ## aim_pos distance for stick aiming
const BUFFER_TIME := 0.15  ## a press this close to coming off cooldown is queued, not dropped
const COLORS := ["Blue", "Yellow", "Red", "Black"]   ## Tiny Swords unit colours, by player_index % 4
const TEAM_SPRITES := ["Red", "Blue"]
const TEAM_COLORS := [Color("ff6a5f"), Color("5fa8ff")]
const NAME_COLORS := [Color("5fa8ff"), Color("ffd84a"), Color("ff6a5f"), Color("b9b9c8"), Color("6fe08a"), Color("e08aff"), Color("ff9a3c"), Color("4fe3e3")]
const RESPAWN_TIME := 3.0
const ONLINE_HIT_IFRAMES := 0.15   ## offline a hit grants 0.7s; online that would swallow most basic attacks
const KNOCK_BASE := 220.0          ## launch speed of a light hit: a flinch (~11 px) so basic combos keep connecting
const KNOCK_LIGHT_DMG := 12        ## hits up to this damage are light; only heavier ones (finishers, skills) launch
const KNOCK_PER_DMG := 20.0        ## extra launch speed per damage above KNOCK_LIGHT_DMG (skills add their own Spell.shove on top)
const KNOCK_LOW_HP := 0.6          ## launch bonus at 0 HP: knockback grows as the victim's health drops (Smash-style), so ring-outs come late in a fight
const KNOCK_MAX := 1500.0
const KNOCK_DECEL := 2200.0        ## slide = v^2 / (2 * this): a 1470 px/s launch carries ~490 px. The Hook sizes its pull from this
const ATTACK_MOVE := 0.75          ## move speed multiplier during the cast lock (not while merely holding the button)
const HIT_SLOW_LIGHT := [0.3, 0.3] ## [speed multiplier, seconds] on the victim of a light hit: this is what lets a chaser stay on them
const HIT_SLOW_HEAVY := [0.5, 0.6]
const SINK_TIME := 0.3             ## seconds over water before you drown
const LAST_HIT_WINDOW := 4.0       ## a fall within this long of a hit is credited to the hitter
const GIANT_SCALE := 1.8
const BOMB_FUSE := 8.0
const BOMB_GRACE := 1.2            ## after getting or passing the bomb, no passing for this long (no instant ping-pong)
const BOMB_PASS_DIST := 56.0
const SLOTS_NAME := ["LMB", "RMB"]
const EMOTES := ["Bonk!", "Haha", "Oops", "GG"]
const EMOTE_COOLDOWN := 1.5
const CHICKEN_SCALE := 0.7

@export var player_index := 0
var ai: BotBrain            ## set before add_child: this player is a bot and its input comes from here, not the keyboard
var team := -1              ## 0/1 in a team match (Red/Blue), -1 = free-for-all
var friendly_fire := true   ## false: hits from a teammate do nothing
var peer_id := 0            ## who this player is in the match (kills, pickups, bombs); the owning peer, or a made-up id for a bot
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
var weapons: Array = [null, null]   ## Friendslop: the FsWeapon held per slot (replaces the basic / skill while it lasts); kept on every peer
var buffs := {}             ## PvP pickup kind -> expiry in seconds (Time.get_ticks_msec); kept on every peer so hits can read the attacker's

var hp := 0
var down := false
var aim_dir := Vector2.RIGHT
var aim_pos := Vector2.ZERO
var cooldowns: Array[float] = [0.0, 0.0]
var cooldown_max: Array[float] = [1.0, 1.0]  ## last applied cooldown, for HUD
var dash_charges := MAX_DASH
var dash_recharge := 0.0
var knock := Vector2.ZERO
var _p := "p1_"
var _dash_time := 0.0
var _dash_vec := Vector2.RIGHT
var _dash_speed := DASH_SPEED
var _ghost := false        ## mid-dash: rocks do not block, only the hard walls
var _slow_mult := 1.0      ## movement slow from a field / aiming; lasts while _slow_left > 0
var _slow_left := 0.0
var _phase_left := 0.0     ## Shadow Step: untargetable and see-through
var _cast_time := 0.0
var _queued := -1          ## buffered slot index, -1 = none
var _queued_time := 0.0
var _puppet := false       ## online and owned by another peer: no input, position comes from net_pos
var _mouse_aim := true     ## P1 only: aim with the mouse until a gamepad is touched, then with the right stick
var _swing := false        ## alternates basic-attack animations (cast / cast2) when the hero has both
var _iframes := 0.0
var _stun_left := 0.0      ## stunned: no moving, casting or dashing. Kept on every peer; only the owner's copy stops input, the rest show it
var _hover: Node2D         ## local human only: the foe the basic attack would lock onto right now (drawn as a ring)
var _chase: Node2D         ## local human only: the foe a held basic attack is walking toward (see _tick_chase)
var hit_sound_msec := 0    ## when this player's last hit sound played on this peer
var _punch := 0.0         ## 1 -> 0 squash on being hit (see _apply_look)
var _sink := 0.0          ## seconds spent over water
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

## True when this peer simulates this player: it is ours, or a bot we run.
func owns() -> bool:
	return ai != null or is_multiplayer_authority()

## Launch speed for a hit of `amount` damage.
static func knock_for(amount: int, hp_left := 1.0) -> float:
	var v := KNOCK_BASE + maxi(amount - KNOCK_LIGHT_DMG, 0) * KNOCK_PER_DMG
	return minf(v * (1.0 + KNOCK_LOW_HP * (1.0 - clampf(hp_left, 0.0, 1.0))), KNOCK_MAX)

## True when `n` is a human player simulated on this peer (not a bot, not a puppet).
static func is_local(n: Node) -> bool:
	var p := n as Player
	return p != null and p.ai == null and p.owns()

## Impact feedback on `victim` for a hit of `amount`: a spark for everyone; hit-stop only when `felt` (the local human
## dealt or took the hit, because hit-stop dips the global time scale); camera shake only when `shaken` (the local human
## is the victim: shake means "you were hit", and landing a hit confirms with the freeze, spark, number and sound instead,
## so the shake never spoils your aim). Also used by the gym dummy.
static func hit_fx(victim: Node2D, amount: int, felt: bool, killed := false, shaken := false) -> void:
	if not victim.is_inside_tree():
		return
	var heavy := amount > KNOCK_LIGHT_DMG
	var fx := "res://assets/tiny_swords/fx/%s.png" % ("Explosion_01" if heavy else "Dust_02")
	SheetFrames.play_once(victim.get_parent(), victim.global_position + Vector2(0, -8), fx, 8 if heavy else 10, 30.0, 0.5 if heavy else 1.0).z_index = 20
	var cam := victim.get_tree().get_first_node_in_group("camera") as GameCamera
	if cam and shaken:
		cam.shake(0.85 if killed else (0.6 if heavy else 0.3))
	if cam and felt and (heavy or killed):   # light hits come several a second: freezing on each one made attacking feel slow
		cam.hit_stop(0.16 if killed else 0.1)
	hit_sound(victim, amount)

## The impact sound of a hit that landed: heavier hits are louder and lower. Played here and nowhere else, so a hit the
## victim's dash dodged is silent. `victim.hit_sound_msec` stops the observer path in _net_hp from doubling it.
static func hit_sound(victim: Node2D, amount: int) -> void:
	if victim is Player:
		victim.hit_sound_msec = Time.get_ticks_msec()
	var weight := clampf(amount / 45.0, 0.0, 1.0)
	Sfx.play("hit_big" if amount > KNOCK_LIGHT_DMG else "hit", victim.global_position, lerpf(-4.0, 3.0, weight), lerpf(1.1, 0.8, weight))

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
	collision_mask = SOLID_MASK | WALL_MASK
	_p = "p1_" if online else "p%d_" % (player_index + 1)
	if peer_id == 0:
		peer_id = get_multiplayer_authority()
	_puppet = online and not owns()
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
	_sprite.sprite_frames = hero.frames(TEAM_SPRITES[team] if team >= 0 else COLORS[player_index % COLORS.size()])
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
	label.modulate = TEAM_COLORS[team] if team >= 0 else NAME_COLORS[player_index % NAME_COLORS.size()]
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
			if owns():
				heal(int(max_hp * 0.5))
				_net_hp.rpc(hp)
		"bomb":
			give_bomb(BOMB_FUSE)
		_:
			if PvpPickup.is_weapon(kind):
				equip_weapon(kind)
			else:   # damage / speed / giant / chicken: timed forms, read from the buffs on every peer
				buffs[kind] = Time.get_ticks_msec() / 1000.0 + BUFF_TIME

# --- Friendslop weapons

## Takes a weapon into its slot (swapping out whatever was there). Runs on every peer.
func equip_weapon(weapon_id: String) -> void:
	var w := FsWeapon.make(weapon_id)
	w.until = Time.get_ticks_msec() / 1000.0 + w.time
	weapons[w.slot] = w
	cooldowns[w.slot] = minf(cooldowns[w.slot], 0.2)   # usable right away
	float_text("%s: %s x%d" % [Player.SLOTS_NAME[w.slot], w.display_name, w.uses], PvpPickup.tier_color(weapon_id), 20)

## True while the slot's weapon has uses and time left.
func weapon_active(slot: int) -> bool:
	var w: FsWeapon = weapons[slot]
	return w != null and w.uses > 0 and w.seconds_left() > 0.0

## What a press of this slot casts right now: the weapon, else the hero's own spell.
func spell_in(slot: int) -> Spell:
	return weapons[slot] if weapon_active(slot) else (spells[slot] if slot < spells.size() else null)

func clear_weapons() -> void:
	weapons = [null, null]

func _tick_weapons() -> void:
	for i in weapons.size():
		var w: FsWeapon = weapons[i]
		# other peers allow a little slack: a cast the owner made just before its own expiry must still find the weapon
		if w != null and (w.uses <= 0 or w.seconds_left() <= (0.0 if owns() else -0.6)):
			weapons[i] = null
			float_text("%s gone" % w.display_name, Color(0.8, 0.8, 0.8))

func _speed_mult() -> float:
	var m := (SPEED_BUFF if buffed("speed") else 1.0) * (_slow_mult if _slow_left > 0.0 else 1.0)
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
	if is_instance_valid(_hover) and not down:   # lock-on marker: this is who the next basic attack goes for
		var chasing := _hover == _chase   # orange while a held attack is walking to it
		draw_arc(to_local(_hover.global_position) + Vector2(0, 14), 30.0, 0.0, TAU, 28, Color(1.0, 0.55, 0.15, 0.95) if chasing else Color(1.0, 0.3, 0.25, 0.9), 4.0 if chasing else 3.0)
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
	if ai:
		var e := ai.take_emote()
		if e >= 0:
			_emote_cd = EMOTE_COOLDOWN
			_net_emote.rpc(e)
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
	l.position = Vector2(-80 + randf_range(-22.0, 22.0), -90)   # jitter so stacked hit numbers stay readable
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
	if _puppet or ai != null or (player_index != 0 and not online):
		return
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		_mouse_aim = true
	elif event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5):
		_mouse_aim = false

func _physics_process(delta: float) -> void:
	_tick_bomb(delta)
	_tick_weapons()
	if _puppet:
		_puppet_tick(delta)
		return
	_tick_timers(delta)
	if down:
		return
	if ai:
		ai.think(delta)
	var move := ai.move if ai else Input.get_vector(_p + "left", _p + "right", _p + "up", _p + "down")
	_update_aim(move)
	var chase := Vector2.ZERO
	if ai == null and not spells.is_empty():
		chase = _tick_chase(move)
		var seen: Node2D = null
		if _stun_left <= 0.0:
			seen = spell_in(0).target(self, aim_pos, aim_dir)
			if seen == null and is_instance_valid(_chase):
				seen = _chase
		if seen != _hover or seen != null:   # redraw while a ring is up: it follows the target
			_hover = seen
			queue_redraw()
	if _dash_time > 0.0:
		_dash_time -= delta
		velocity = _dash_vec * _dash_speed
	elif _stun_left > 0.0:
		velocity = Vector2.ZERO   # knockback (a hook's pull, a launch) still carries a stunned player
	else:
		if _dash_pressed() and dash_charges > 0:
			_start_dash(move)
		velocity = (move + chase) * speed * _speed_mult() * (ATTACK_MOVE if _cast_time > 0.0 else 1.0)  # a swing slows you a little instead of rooting you (move or chase is zero)
		_try_cast()
		_try_emote()
	velocity += knock
	move_and_slide()
	if _ghost and _dash_time <= 0.0:
		_end_ghost()
	net_pos = position
	_animate(move + chase)
	if _update_sink(delta):
		_fall()
	_apply_look()

const CHASE_MAX := 1100.0   ## a held attack gives up on a foe this far away
const SHORE_LOOK := 56.0    ## hold-to-chase never steps toward water closer than this

## Hold-to-chase (the Dota "attack-move"): while the basic attack is held and a foe is out of its reach, walk toward that
## foe until it is in reach, then the normal lock-on attack takes over. The foe is the one under the cursor when the
## button goes down; it stays chased until the button is released, it dies, or it gets away (CHASE_MAX). Any movement
## key wins over the chase, a stun or a dash interrupts it, and it never walks you into water. Returns the move vector.
func _tick_chase(move: Vector2) -> Vector2:
	var spell := spell_in(0)
	if not _held(0) or spell.reach() <= 0.0 or buffed("chicken"):
		_chase = null
		return Vector2.ZERO
	if not is_instance_valid(_chase) or _chase.down or _chase.global_position.distance_to(global_position) > CHASE_MAX:
		_chase = null
		if spell.target(self, aim_pos, aim_dir) == null:   # nobody lockable in reach already: pick the foe under the cursor
			_chase = Spell.pick_foe(self, aim_pos, aim_dir, HeroBasic.LOCK_RADIUS, 0.0, CHASE_MAX)
			if _chase:
				Sfx.play("emote", Vector2.INF, -6.0, 1.5)   # a small "target acquired" click
	if _chase == null or move != Vector2.ZERO or _stun_left > 0.0 or _dash_time > 0.0:
		return Vector2.ZERO
	var off := _chase.global_position - global_position
	aim_dir = off.normalized()
	if off.length() <= spell.reach() * 0.9:
		return Vector2.ZERO
	if _over_water(position + aim_dir * SHORE_LOOK):
		return Vector2.ZERO
	return aim_dir

## Another peer's player: ease toward the replicated position, animate from the movement.
func _puppet_tick(delta: float) -> void:
	_cast_time = maxf(_cast_time - delta, 0.0)
	_stun_left = maxf(_stun_left - delta, 0.0)
	_phase_left = maxf(_phase_left - delta, 0.0)
	_update_sink(delta)   # puppets only show the sinking; the owner decides when it kills
	_apply_look()
	if down:
		return
	var off := net_pos - position
	var before := position
	position = net_pos if off.length() > 300.0 else position.lerp(net_pos, 1.0 - exp(-20.0 * delta))
	velocity = (position - before) / delta   # never moved by physics here; the soft lock leads a puppet by this
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
	var tint := hero.tint
	_sprite.rotation = 0.0
	if buffed("giant"):
		s = GIANT_SCALE
	elif buffed("chicken"):
		s = CHICKEN_SCALE
		tint = hero.tint * Color(1.0, 0.95, 0.4)
		_sprite.rotation = sin(Time.get_ticks_msec() * 0.03) * 0.15
	if buffed("chicken") and Time.get_ticks_msec() > _cluck_at:
		Sfx.play("cluck", global_position)
		_cluck_at = Time.get_ticks_msec() + randi_range(900, 1500)
	if _stun_left > 0.0:
		_sprite.rotation = sin(Time.get_ticks_msec() * 0.025) * 0.22   # dizzy wobble
		tint = tint * Color(1.0, 1.0, 0.55)
	if down:
		_sprite.rotation = PI / 2.0   # knocked flat until the respawn (the sheets have no death animation)
	_shape.radius = 14.0 * maxf(s, 1.0)   # a giant is also harder to miss
	var sink := clampf(_sink / SINK_TIME, 0.0, 1.0)
	_punch = move_toward(_punch, 0.0, get_physics_process_delta_time() * 7.0)
	_sprite.scale = Vector2(1.0 + 0.3 * _punch, 1.0 - 0.3 * _punch) * s * (1.0 - 0.7 * sink)
	_sprite.position = Vector2(0, -(s - 1.0) * 20.0)   # keep the feet on the ground while resizing
	_sprite.self_modulate = Color(tint, (1.0 - sink) * (0.35 if _phase_left > 0.0 else 1.0))

## Drowned: the owner announces the death, crediting the last player who hit us recently.
func _fall() -> void:
	var killer := last_hit_peer if Time.get_ticks_msec() - last_hit_msec < LAST_HIT_WINDOW * 1000.0 else 0
	_net_died.rpc(killer, "fall")

func _tick_timers(delta: float) -> void:
	_iframes = maxf(_iframes - delta, 0.0)
	_cast_time = maxf(_cast_time - delta, 0.0)
	_slow_left = maxf(_slow_left - delta, 0.0)
	_stun_left = maxf(_stun_left - delta, 0.0)
	_phase_left = maxf(_phase_left - delta, 0.0)
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

func _dash_pressed() -> bool:
	return ai.take_dash() if ai else Input.is_action_just_pressed(_p + "dash")

func _held(slot: int) -> bool:
	return ai.held[slot] if ai else Input.is_action_pressed(_p + SLOTS[slot])

func _update_aim(move: Vector2) -> void:
	if ai:
		aim_pos = ai.aim_pos
		aim_dir = (aim_pos - global_position).normalized() if aim_pos.distance_to(global_position) > 4.0 else aim_dir
		return
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

## Slows movement to `mult` for `secs` (refreshing, not stacking). Only the owner simulates movement, so only it needs this.
func apply_slow(mult: float, secs: float) -> void:
	_slow_mult = mult
	_slow_left = maxf(_slow_left, secs)

## Stunned for `secs` (the longer of this and what is left). Safe on any peer: see _stun_left.
func stun(secs: float) -> void:
	if down or secs <= 0.0:
		return
	if _stun_left <= 0.0:
		float_text("STUNNED", Color(1.0, 0.95, 0.4), 18)
		if is_inside_tree():
			Sfx.play("crown", global_position, -8.0, 1.6)   # the bell clip, high and quiet: a stun "ding"
	_stun_left = maxf(_stun_left, secs)

func stunned() -> bool:
	return _stun_left > 0.0

## True while a real dash or a phase is on: a locked-on bolt loses its target (a melee lunge does not count).
## ponytail: _ghost is only known on the owner's peer, so a shooter's own screen can show a bolt still homing on a
## dash that dodged it; the victim's peer decides the hit. Replicate the dash state if that looks wrong online.
func dodging() -> bool:
	return _ghost or _phase_left > 0.0

## Untargetable and see-through for `secs` (Shadow Step).
func phase(secs: float) -> void:
	_phase_left = secs
	_iframes = maxf(_iframes, secs)

## The dash is over: the rocks are solid again, so make sure we are not standing inside one.
func _end_ghost() -> void:
	_ghost = false
	collision_mask = SOLID_MASK | WALL_MASK
	position = free_spot(position)

## Mid Shadow Step: attacks and projectiles pass through.
func phased() -> bool:
	return _phase_left > 0.0

## True if a solid (rock, wall, dummy) overlaps the body when its origin is at `pos` (a local position).
func _blocked_at(pos: Vector2) -> bool:
	if not is_inside_tree():
		return false
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = _shape
	q.transform = Transform2D(0.0, to_global(pos - position) + Vector2(0, 14))
	q.collision_mask = SOLID_MASK | WALL_MASK
	q.exclude = [get_rid()]
	return not get_world_2d().direct_space_state.intersect_shape(q, 1).is_empty()

func _over_water(pos: Vector2) -> bool:
	return water_check.is_valid() and water_check.call(to_global(pos - position) + Vector2(0, 14))

## The closest spot to `pos` (searched in rings, always in the same order) that is not inside a solid. Never trades dry land
## for water: a spot over water is only taken if `pos` itself was already over water. Returns `pos` if it is already free.
func free_spot(pos: Vector2) -> Vector2:
	if not _blocked_at(pos):
		return pos
	var wet := _over_water(pos)
	for ring in range(1, 17):
		var r := ring * 12.0
		for k in 16:
			var c := pos + Vector2.from_angle(k * TAU / 16.0 + ring * 0.4) * r
			if not _blocked_at(c) and (wet or not _over_water(c)):
				return c
	return pos

## Teleports toward `dest` (Shadow Step): stops at a hard wall on the way, never lands in a rock, and prefers dry ground.
func blink_to(dest: Vector2) -> void:
	var target := dest
	if is_inside_tree():
		var q := PhysicsRayQueryParameters2D.create(global_position, dest, WALL_MASK)
		var hit := get_world_2d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			target = hit.position - (dest - global_position).normalized() * 24.0
	var back := (position - target).normalized() * 16.0   # over water but we started on land: walk back toward where we were
	var tries := 0
	while _over_water(target) and not _over_water(position) and tries < 40 and target.distance_to(position) > 16.0:
		target += back
		tries += 1
	position = free_spot(target)
	net_pos = position
	velocity = Vector2.ZERO
	knock = Vector2.ZERO

func _start_dash(move: Vector2) -> void:
	dash_charges -= 1
	if dash_recharge <= 0.0:
		dash_recharge = DASH_RECHARGE
	_cast_time = 0.0  # dash cancels the cast lock
	Sfx.play("dash", global_position)
	_dash_vec = move if move != Vector2.ZERO else aim_dir
	_dash_time = DASH_TIME
	_dash_speed = DASH_SPEED
	_ghost = true
	collision_mask = WALL_MASK   # rocks are passable for the dash; the room walls still hold
	_iframes = maxf(_iframes, DASH_TIME + 0.05)
	SheetFrames.play_once(get_parent(), global_position + Vector2(0, 20), "res://assets/tiny_swords/fx/Dust_01.png", 8, 24.0, 0.8)

## True while an attack button is held or the cast anim is still playing (no gap between rapid taps).
func _firing() -> bool:
	if _cast_time > 0.0 or _queued >= 0:
		return true
	if _puppet:
		return false
	for i in SLOTS.size():
		if _held(i) and not (i == 0 and _chase_pending()):
			return true
	return false

## True while a held basic attack is still walking toward a foe it cannot reach yet. Like Dota's attack order, nothing
## is swung or fired until the foe is in reach (a foe already lockable by the cursor or aim cone still counts as in reach).
func _chase_pending() -> bool:
	if not is_instance_valid(_chase) or _chase.down:
		return false
	return global_position.distance_to(_chase.global_position) > spell_in(0).reach()

func _try_cast() -> void:
	if buffed("chicken"):
		return
	for i in SLOTS.size():
		if ai == null and Input.is_action_just_pressed(_p + SLOTS[i]) and cooldowns[i] > 0.0:
			_queued = i
			_queued_time = BUFFER_TIME
	for i in SLOTS.size():
		var spell := spell_in(i)
		if spell and cooldowns[i] <= 0.0 and (_queued == i or _held(i)):
			var foe := spell.target(self, aim_pos, aim_dir)   # lock-on: the cast goes for this foe on every peer
			if foe == null and i == 0 and is_instance_valid(_chase) and not _chase.down:
				if _chase_pending():
					continue   # still walking up to it: no swing, no shot until it is in reach
				foe = _chase   # the foe a held attack walked up to, even if the cursor has left it
			# No target: the attack goes where you aim, a free swing or shot at the ground. The visible whiff is the
			# feedback that teaches new players to aim at someone; lock-on only assists.
			_queued = -1
			var dir := (foe.global_position - global_position).normalized() if foe else spell.aim(self, aim_dir)
			_net_cast.rpc(i + (2 if weapon_active(i) else 0), dir, aim_pos, randi(), foe.get_path() if foe else NodePath())   # slot 2/3 = the weapon in slot 0/1
			return

## Runs on every peer (offline: just here), so every screen gets the same projectiles / sweeps / explosions.
## Damage still only lands on the victim's own peer (see take_damage).
@rpc("authority", "call_local", "reliable")
func _net_cast(slot: int, dir: Vector2, pos: Vector2, seed_value: int, lock_path := NodePath()) -> void:
	var weapon: FsWeapon = weapons[slot - 2] if slot >= 2 else null
	slot %= 2
	var spell: Spell = weapon if weapon != null else spells[slot]
	rng.seed = seed_value
	spell.lock = null if lock_path.is_empty() else get_node_or_null(lock_path) as Node2D   # node paths match on every peer
	var cd := spell.cast(self, dir, pos)
	spell.lock = null
	if weapon != null:
		cd *= cooldown_mult
		weapon.uses -= 1
		if weapon.uses <= 0:
			weapons[slot] = null
			float_text("%s empty" % weapon.display_name, Color(0.8, 0.8, 0.8))
	cooldowns[slot] = cd
	cooldown_max[slot] = cd
	_cast_time = clampf(cd, 0.25, SWING_TIME)  # cover fast-attack cooldowns so tapping never unlocks movement
	_play_cast(slot, spell)

## The cast lock and its animation last this long at most, so the blade comes down when the hit lands
## (0.1 s windup + 0.12 s active) and you are free to move again right after.
const SWING_TIME := 0.3

## Alternates cast / cast2 on the basic, and stretches the anim to exactly fill the cast lock.
func _play_cast(slot: int, spell: Spell) -> void:
	Sfx.play(spell.sfx, global_position, spell.cast_vol, spell.cast_pitch)
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

## Only the player's own peer applies damage; everyone else's copy of the same hit is a no-op (victim-side hits).
## Returns true when the hit landed (on other peers: when it looks like it did), so stuns and pulls skip a dodged hit.
func take_damage(amount: int, from_pos: Vector2, silent := false, attacker: Node = null) -> bool:
	if down:
		return false
	if attacker is Player and attacker != self and team >= 0 and attacker.team == team and not friendly_fire:
		return false
	if not owns():
		# Our own hit on somebody else's player: show the impact now instead of waiting for their peer's reply.
		# ponytail: predicted, so it also fires when their i-frames ate the hit; replicate _iframes if that reads wrong.
		if not silent and is_local(attacker):
			_punch = 1.0
			_flash()
			hit_fx(self, amount, true)   # our hit on somebody else: the freeze, never a shake
		return true
	if _iframes > 0.0:
		return false
	if attacker is Player and attacker.buffed("damage"):   # victim-side hit: read the attacker's copy of the buff
		amount *= 2
	amount = form_damage(roundi(amount * RuleSet.current.damage))
	hp = maxi(hp - amount, 0)
	if attacker is Player:
		last_hit_peer = attacker.peer_id
		last_hit_msec = Time.get_ticks_msec()
	if not silent:   # rapid-tick hits (an ember field's burn) neither stagger nor grant i-frames
		_iframes = ONLINE_HIT_IFRAMES if online else 0.7
		knock = (global_position - from_pos).normalized() * knock_for(amount, float(hp) / max_hp) * form_knock(attacker)
		var slow: Array = HIT_SLOW_HEAVY if amount > KNOCK_LIGHT_DMG else HIT_SLOW_LIGHT
		apply_slow(slow[0], slow[1])
		_punch = 1.0
		if hp > 0 or not online:   # an online kill gets its bigger impact from _net_died, on every peer
			hit_fx(self, amount, is_local(self) or is_local(attacker), hp == 0, is_local(self))
	_hit_number(amount)
	_flash()
	hp_changed.emit(hp, max_hp)
	if not online:
		if hp == 0:
			_die()
		return true
	if hp == 0:
		_net_died.rpc(attacker.peer_id if attacker is Player else 0, "hit" if attacker is Player else "bomb")   # no attacker = an ownerless Explosion (the hot potato)
	else:
		_net_hp.rpc(hp)
	return true

func _flash() -> void:
	_sprite.modulate = Color(2.5, 1.1, 1.1)   # overbright, so it reads as an impact and not just a tint
	create_tween().tween_property(_sprite, "modulate", Color.WHITE, 0.2)

func _hit_number(amount: int) -> void:
	float_text(str(amount), Color(1.0, 0.9, 0.5), 16 + mini(amount / 2, 14))

func _die() -> void:
	down = true
	queue_redraw()
	buffs.clear()
	clear_weapons()
	velocity = Vector2.ZERO
	_sprite.modulate = Color(0.5, 0.5, 0.6, 0.6)
	_sprite.rotation = PI / 2.0   # the owner stops calling _apply_look while down, so set the knocked-flat pose here too
	_sprite.play("idle")
	downed.emit()

@rpc("authority", "call_remote", "reliable")
func _net_hp(value: int) -> void:
	if value < hp:   # a heal must not flash red
		_flash()
		_hit_number(hp - value)
		if Time.get_ticks_msec() - hit_sound_msec > 500:   # a bystander's peer: nothing predicted this hit, so the sound is due now
			hit_sound(self, hp - value)
	hp = value
	hp_changed.emit(hp, max_hp)

@rpc("authority", "call_local", "reliable")
func _net_died(killer_peer: int, cause: String) -> void:
	hp = 0
	hp_changed.emit(hp, max_hp)
	Sfx.play("death", global_position)
	_sink = SINK_TIME if cause == "fall" else 0.0   # a drowned player stays under until the respawn
	_die()
	if cause != "fall":   # everyone sees the burst; only the killer and the victim feel the shake and the freeze
		hit_fx(self, 99, is_local(self) or (cause == "hit" and killer_peer == Net.local_id()), true, is_local(self))
	fragged.emit(self, killer_peer, cause)
	if owns():
		get_tree().create_timer(RESPAWN_TIME).timeout.connect(_respawn)

func _respawn() -> void:
	if is_inside_tree():
		_net_respawn.rpc(respawn_point.call() if respawn_point.is_valid() else position)

@rpc("authority", "call_local", "reliable")
func _net_respawn(pos: Vector2) -> void:
	position = pos
	net_pos = pos
	knock = Vector2.ZERO
	_dash_time = 0.0
	_slow_left = 0.0
	_stun_left = 0.0
	_phase_left = 0.0
	if _ghost:
		_end_ghost()
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
