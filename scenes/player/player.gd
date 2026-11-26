class_name Player extends CharacterBody2D
## A hero: move, aim, dash (charges, passes through rocks), and two skills: basic (LMB) and one signature skill (RMB). Input actions are prefixed p1_ / p2_.

signal hp_changed(hp: int, max_hp: int)
signal downed
signal stats_changed   ## level, skill rank or gear changed and stats were recomputed
signal bomb_touch(other: Player)   ## the hot-potato carrier (owner's peer only) touched `other`; the match decides the pass
signal emoted(player: Player)
signal fragged(victim: Player, killer_peer: int, cause: String)   ## online: emitted on every peer when a player dies (killer_peer 0 = no player; cause = "hit" | "fall" | "bomb" | "meteor" | "reflect")

const SLOTS := ["basic", "skill", "ult"]   ## input action suffixes; slot 0 = LMB basic, slot 1 = RMB skill, slot 2 = F ult (only heroes that have one)
const ULT_SLOT := 2
const ULT_TAKEN := 0.35    ## damage taken fills the ult at this rate of damage dealt: the one getting beaten on gets a way back
const WEAPON_CAST := 10    ## _net_cast slot offset meaning "the Friendslop weapon held in that slot"
const SOLID_MASK := 1    ## collision layer of rocks and the dummy
const WALL_MASK := 32    ## collision layer of the hard room walls (rocks are not on it): a dash never passes these
const LOW_MASK := 64     ## collision layer of low rails (Colosseum): walking bumps into them, shots and dashes go over
const MAX_DASH := 2         ## the dash is what shakes off a lock-on, so it is scarce: one escape, one spare
const DASH_SPEED := 1500.0
const DASH_TIME := 0.16
const DASH_RECHARGE := 2.5
const AIM_REACH := 280.0   ## aim_pos distance for stick aiming
const BUFFER_TIME := 0.25  ## a press this close to coming off cooldown is queued, not dropped (was 0.15: mashing between swings ate presses)
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
const SLOTS_NAME := ["LMB", "RMB", "F"]
const EMOTES := ["Bonk!", "Haha", "Oops", "GG"]
const EMOTE_COOLDOWN := 1.5
const CHICKEN_SCALE := 0.7
const HIT_STOP := [0.05, 0.09, 0.14]   ## sprite hit-stop seconds: light hit, heavy hit, kill
const STUN_IMMUNITY := 1.0             ## after a stun wears off, no new stun for this long: no stunlocks in a brawl

@export var player_index := 0
var ai: BotBrain            ## set before add_child: this player is a bot and its input comes from here, not the keyboard
var team := -1              ## 0/1 in a team match (Red/Blue), -1 = free-for-all
var friendly_fire := true   ## false: hits from a teammate do nothing
var peer_id := 0            ## who this player is in the match (kills, pickups, bombs); the owning peer, or a made-up id for a bot
var online := false         ## set by the match before add_child; the node's multiplayer authority is then the owning peer
var display_name := ""
var respawn_point := Callable()   ## online: returns a Vector2; set by the match
var water_check := Callable()     ## online: (Vector2) -> bool, true over deadly water; set by the match
var ground_check := Callable()    ## (Vector2) -> bool, true where there is no standing ground (water or past a wall); dashes stop short of it. Falls back to water_check
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
var shield_hp := 0          ## Shield drop: damage it still absorbs (owner's state; synced so every screen draws the ring)
var channeling := 0.0       ## 0 = not taking a drop, else the channel 0..1. Synced: every screen sees the ring fill
var _channel_pk: PvpPickup = null   ## owner only: the drop being channelled
var _move_in := Vector2.ZERO        ## owner only: this frame's move input (a channel needs it to be zero)
var _tag: Node2D            ## the name tag (hidden in Fog for everyone but yourself)

var hp := 0
var down := false
var aim_dir := Vector2.RIGHT
var aim_pos := Vector2.ZERO
var cooldowns: Array[float] = [0.0, 0.0, 0.0]
var cooldown_max: Array[float] = [1.0, 1.0, 1.0]  ## last applied cooldown, for HUD
var ult_charge := 0.0       ## owner only: damage banked toward the ult (full at hero.ult_cost); kept through death
var _ult_lock := 0.0        ## seconds after an ult during which nothing charges it (the ult cannot pay for itself)
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
var pointer_on_ui := false ## the mouse is over a clickable panel (the gym's): its clicks are not attacks
var _swing := false        ## alternates basic-attack animations (cast / cast2) when the hero has both
var _iframes := 0.0
var _stun_immune := 0.0   ## post-stun immunity left (see STUN_IMMUNITY); ticked on every peer like _stun_left
var _freeze := 0.0        ## sprite hit-stop left (see hit_fx)
var _stun_left := 0.0      ## stunned: no moving, casting or dashing. Kept on every peer; only the owner's copy stops input, the rest show it
var _frozen_left := 0.0    ## frozen (Shadow Rush): no moving, dashing or turning, but attacks still go out the locked way. Same rules as a stun
var _frozen_aim := Vector2.RIGHT   ## the facing a freeze locked
var _charge_slot := -1     ## owner only: the slot being drawn (hold-and-release, Power Shot), -1 = none
var _charge := 0.0         ## owner only: charge built so far (seconds, sped up by Steady Aim)
var _charge_held := 0.0    ## owner only: real seconds held (caps at the spell's max_hold)
var _charge_drawn := false ## the aim line was drawn last frame (one more redraw clears it)
var charge_show := 0.0     ## 0 = not drawing, else the draw 0..1. Synced, so every screen shows the aim line growing
const DRAW_SLOW := 0.5     ## move speed while drawing

# --- kit statuses (Kindling burn, Paladin, Shade, Scout). The timed ones are set by a cast, which runs on every peer.
const BURN_MAX := 12        ## Kindling: Burn stacks cap
const BURN_TICK := 1.0      ## seconds between burn ticks; each tick deals `burn` damage (1 per stack per second)
const BURN_DECAY := 1.2     ## one stack falls off every this many seconds
const ANGEL_STEAL := 0.5    ## Guardian Angel: share of your damage dealt that heals you while it lasts
const RIPOSTE_RANGE := 320.0   ## Riposte: an attacker within this reach is countered (the Shade blinks to it)
const RIPOSTE_CRIT := 2.5   ## Riposte counter: the basic's damage times this
var burn := 0               ## Burn stacks on this player. The owner ticks them; synced so every screen shows the flames
var _burn_by: Node = null   ## who lit them: credited for the burn damage (and kills)
var _burn_tick := 0.0
var _burn_decay := 0.0
var _burning := false       ## inside a burn tick: a burn tick never adds stacks
var _burn_shown := 0
var _angel_left := 0.0      ## Guardian Angel (Paladin ult): no damage taken, hits heal
var _parry_left := 0.0      ## Riposte stance (Shade): the next hit is cancelled and countered
var _spin_left := 0.0       ## Blade Fury (Shade ult): cannot be stunned or frozen, cannot attack
var _empowered_left := 0.0  ## Tumble (Scout): the next basic within this long is empowered
var _rooted_left := 0.0     ## Assassinate (Scout): cannot move or dash while aiming (can still turn)
var _veiled_left := 0.0     ## Smoke Screen (Rogue): unseen by others, untargetable by lock-on, every stab a backstab. Refreshed by the smoke
var _smoked_left := 0.0     ## Smoke Screen: this player's attacks may miss (SMOKE_MISS). Refreshed by the smoke
var _revealed_left := 0.0   ## Lightning Bolt: a veil does not hide you for this long
var _ff_left := 0.0         ## Focus Fire (Ranger ult): seconds of auto-fire left (every peer: set by the cast)
var _ff_target: Node2D      ## and at whom
const SMOKE_MISS := 0.5     ## chance a smoked attacker's hit misses
const STEADY_RATE := 2.0   ## Steady Aim (Ranger passive): charge rate while standing still
var _hover: Node2D         ## local human only: the foe the basic attack would lock onto right now (drawn as a ring)
var _chase: Node2D         ## local human only: the foe a held basic attack is walking toward (see _tick_chase)
var hit_sound_msec := 0    ## when this player's last hit sound played on this peer
var _punch := 0.0         ## 1 -> 0 squash on being hit (see _apply_look)
var _sink := 0.0          ## seconds spent over water
var crowned := false: set = _set_crowned   ## wears the match crown (set by the match); drawn as a crown and a beam
var crown_speed := 1.0     ## Crown mode: the king's move speed multiplier, and below 1 he cannot dash (the king cannot run)
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
var _dirs: Array[SpriteFrames] = []   ## one per facing, see SheetFrames.face
const SPRITE_SCALE := 1.5   ## the isometric sheets are 128 px frames with a ~60 px body

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

## Impact feedback on `victim` for a hit of `amount`: a spark and a sprite hit-stop (victim and `attacker` hold their frame
## and shudder; purely visual, the simulation and Engine.time_scale never pause, so peers stay in step) for everyone;
## camera shake only when `shaken` (the local human is the victim: shake means "you were hit", and landing a hit
## confirms with the freeze, spark, number and sound instead, so the shake never spoils your aim). `felt` (the local
## human dealt or took it) adds a beat to the freeze. Also used by the gym dummy.
static func hit_fx(victim: Node2D, amount: int, felt: bool, killed := false, shaken := false, attacker: Node = null) -> void:
	if not victim.is_inside_tree():
		return
	var heavy := amount > KNOCK_LIGHT_DMG
	var fx := SheetFrames.FX + ("AoE/FireAoE/" if heavy else "AoE/SwordAoE/")
	SheetFrames.play_once(victim.get_parent(), victim.global_position + Vector2(0, -8), fx, 0, 40.0, 0.25 if heavy else 0.4).z_index = 20
	var cam := victim.get_tree().get_first_node_in_group("camera") as GameCamera
	if cam and shaken:
		cam.shake(0.85 if killed else (0.6 if heavy else 0.3))
	var stop: float = HIT_STOP[2 if killed else (1 if heavy else 0)] + (0.02 if felt else 0.0)
	if victim is Player:
		victim.hit_freeze(stop)
	if attacker is Player and attacker != victim:
		attacker.hit_freeze(stop * 0.7)
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
	PlaySettings.load_once()   # the saved playtest toggles (aim mode, melee step-in) apply from the first frame
	collision_layer = 2
	collision_mask = SOLID_MASK | WALL_MASK | LOW_MASK
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
	_dirs = hero.dir_frames(TEAM_SPRITES[team] if team >= 0 else COLORS[player_index % COLORS.size()])
	_sprite.sprite_frames = _dirs[1]
	_sprite.offset = Vector2(0, -16)  # feet sit 41 px below the 128 px frame centre; at SPRITE_SCALE that lands them on the collider
	add_child(_sprite)
	_sprite.play("idle")
	add_child(OverheadHpBar.new())
	if online:
		_setup_online()
	hp_changed.emit(hp, max_hp)

func _setup_online() -> void:
	net_pos = position
	var cfg := SceneReplicationConfig.new()
	for prop in [":net_pos", ":aim_dir", ":aim_pos", ":charge_show", ":burn", ":channeling", ":shield_hp"]:
		cfg.add_property(NodePath(prop))
		cfg.property_set_replication_mode(NodePath(prop), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	sync.replication_config = cfg
	sync.replication_interval = 0.033
	sync.set_multiplayer_authority(get_multiplayer_authority())   # children added after set_multiplayer_authority do not inherit it
	add_child(sync)
	_tag = world_text(display_name, 14, 4)
	_tag.position = Vector2(0, -64)
	_tag.modulate = TEAM_COLORS[team] if team >= 0 else NAME_COLORS[player_index % NAME_COLORS.size()]
	_tag.z_index = 50
	add_child(_tag)

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
	damage_mult = (1.0 + prog.damage_bonus()) * (1.0 + _gear("damage")) * hero.damage_dealt   # damage_dealt: Glass Cannon
	cooldown_mult = maxf(1.0 - _gear("cooldown"), 0.5) / rules.attack_rate
	for i in mini(spells.size(), _base_spells.size()):
		var ranked := i < Progression.SLOTS   # the ult has no skill ranks
		spells[i].damage = roundi(_base_spells[i][0] * damage_mult * (prog.skill_damage_mult(i) if ranked else 1.0))
		spells[i].cooldown = _base_spells[i][1] * cooldown_mult * (prog.skill_cooldown_mult(i) if ranked else 1.0)
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
const BUFF_TIMES := {"speed": 8.0, "shield": 8.0, "warcry": 8.0}   ## per kind; the rest last BUFF_TIME
const SPEED_BUFF := 1.5
const TIMED_BUFFS := ["damage", "speed", "shield", "warcry", "giant", "chicken"]   ## what the HUD lists

func buffed(kind: String) -> bool:
	return buff_left(kind) > 0.0

func buff_left(kind: String) -> float:
	return maxf(buffs.get(kind, 0.0) - Time.get_ticks_msec() / 1000.0, 0.0)

## A PvP pickup was taken by this player. Runs on every peer; only the owner touches its own HP, ult and cooldowns.
func apply_pickup(kind: String) -> void:
	float_text(PvpPickup.LABELS[kind], PvpPickup.COLORS[kind])
	match kind:
		"heal":
			if owns():
				var share: float = PvpPickup.HEAL_FRACTION_FS if GameMode.is_friendslop(Net.mode) else PvpPickup.HEAL_FRACTION
				heal(int(max_hp * share))
				_net_hp.rpc(hp)
		"bomb":
			give_bomb(BOMB_FUSE)
		"ult":   # half an ult, straight in (past the ult lock: a drop is not the ult paying for itself)
			if owns() and spells.size() > ULT_SLOT:
				var was := ult_ready()
				ult_charge = minf(ult_charge + hero.ult_cost * PvpPickup.ULT_SPARK, hero.ult_cost)
				if was:
					float_text("ULT FULL", Color(0.8, 0.8, 0.8), 16)
				elif ult_ready() and is_local(self):
					float_text("ULT READY  [F]", Color(0.85, 0.5, 1.0), 22)
					Sfx.play("crown", global_position, -4.0, 1.5)
		"reset":   # every cooldown and both dashes, now
			if owns():
				for i in cooldowns.size():
					cooldowns[i] = 0.0
				dash_charges = MAX_DASH
				dash_recharge = 0.0
		"shield":
			shield_hp = PvpPickup.SHIELD_HP
			buffs[kind] = Time.get_ticks_msec() / 1000.0 + BUFF_TIMES[kind]
		_:
			if PvpPickup.is_weapon(kind):
				equip_weapon(kind)
			else:   # damage / speed / warcry / giant / chicken: timed forms, read from the buffs on every peer
				buffs[kind] = Time.get_ticks_msec() / 1000.0 + BUFF_TIMES.get(kind, BUFF_TIME)

# --- taking a drop: the channel (docs §6.3). Stand still on it, no swing, no dash; a hit, a step or a dash drops it.

## The drop this player is channelling, or null.
func channel_target() -> PvpPickup:
	return _channel_pk if is_instance_valid(_channel_pk) else null

## True when a channel could run right now: standing still, not swinging, drawing, dashing, stunned, frozen or flying.
func can_channel() -> bool:
	if down or _puppet or _dash_time > 0.0 or _stun_left > 0.0 or _frozen_left > 0.0 or _cast_time > 0.0 or _charge_slot >= 0 or _spin_left > 0.0:
		return false
	if _move_in.length() > 0.1 or knock.length() > 60.0:
		return false
	for i in SLOTS.size():
		if _held(i):
			return false
	return true

## Called by the drop every frame this player stands on it (owner only).
func start_channel(pk: PvpPickup) -> void:
	_channel_pk = pk
	channeling = 0.001
	Sfx.play("swing", global_position, -8.0, 1.3)

func stop_channel() -> void:
	_channel_pk = null
	channeling = 0.0

## A hit landed: the channel breaks (the taker's own peer).
func break_channel() -> void:
	if channel_target() != null:
		float_text("INTERRUPTED", Color(1.0, 0.45, 0.4), 16)
	stop_channel()

func _tick_channel(delta: float) -> void:
	var pk := channel_target()
	if pk == null:
		if channeling > 0.0:
			channeling = 0.0
		return
	if not can_channel() or global_position.distance_to(pk.global_position) > PvpPickup.RADIUS + 6.0:
		stop_channel()
		return
	channeling = minf(channeling + delta / maxf(pk.channel_time, 0.05), 1.0)
	if channeling >= 1.0:
		pk.finish_channel(self)
		stop_channel()

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
	if slot >= weapons.size():
		return false   # the ult slot never holds a weapon
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
	if crowned:
		m *= crown_speed
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
	if attacker is Player and attacker.buffed("warcry"):   # Warcry drop: every hit shoves twice as hard
		m *= PvpPickup.WARCRY_KNOCK
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

## True when the hero has an ult and it is fully charged.
func ult_ready() -> bool:
	return spells.size() > ULT_SLOT and ult_charge >= hero.ult_cost

## 0..1 for the HUD.
func ult_fraction() -> float:
	return clampf(ult_charge / maxf(hero.ult_cost, 1.0), 0.0, 1.0) if spells.size() > ULT_SLOT else 0.0

## Banks `amount` of damage toward the ult. Owner only (the charge is the owner's state; the cast travels by RPC).
func charge_ult(amount: float) -> void:
	if spells.size() <= ULT_SLOT or _ult_lock > 0.0 or down or amount <= 0.0:
		return
	var was := ult_ready()
	ult_charge = minf(ult_charge + amount, hero.ult_cost)
	if not was and ult_ready() and is_inside_tree() and is_local(self):
		float_text("ULT READY  [F]", Color(0.85, 0.5, 1.0), 22)
		Sfx.play("crown", global_position, -4.0, 1.5)

## True while wearing a crown that slows and grounds its king (Crown mode): no dash, slower feet.
func burdened() -> bool:
	return crowned and crown_speed < 1.0

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
	if not down:
		_draw_statuses()
		_draw_drop_states()
	if charge_show > 0.0 and not down:   # a drawn bow: everyone sees where it points and how full it is
		var cs := charge_spell()
		if cs:
			cs.draw_charge(self, aim_dir, charge_show)
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
	var l := world_text(text, font_size, 5)
	l.modulate = color
	l.z_index = 100
	l.position = Vector2(randf_range(-22.0, 22.0), -90 + font_size)   # jitter so stacked hit numbers stay readable
	add_child(l)
	var t := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS).set_parallel()   # ticked like the body, so it interpolates with it
	t.tween_property(l, "position:y", -140.0 + font_size, 1.2)
	t.tween_property(l, "modulate:a", 0.0, 0.6).set_delay(0.7)
	t.chain().tween_callback(l.queue_free)

## Outlined text centred on its origin's x, baseline at its y. A Node2D and not a Label: Controls are not physics-
## interpolated, so a Label riding on a running hero jitters against the smoothly drawn sprite.
static func world_text(text: String, font_size: int, outline: int) -> Node2D:
	var n := Node2D.new()
	var font := ThemeDB.fallback_font
	n.draw.connect(func() -> void:
		n.draw_string_outline(font, Vector2(-80, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 160, font_size, outline, Color.BLACK)
		n.draw_string(font, Vector2(-80, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 160, font_size))
	return n

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
	if _tag:   # Fog: name tags off for everyone but yourself
		_tag.visible = not MatchEvent.is_on(MatchEvent.FOG) or is_local(self)
	if channeling > 0.0 or shield_hp > 0 or buffed("warcry") or MatchEvent.current != MatchEvent.NONE:
		queue_redraw()   # the drop / event marks animate
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
	if _frozen_left > 0.0:   # cannot turn: attacks go out the locked way, as far as the cursor is
		aim_dir = _frozen_aim
		aim_pos = global_position + _frozen_aim * maxf(aim_pos.distance_to(global_position), 40.0)
		move = Vector2.ZERO
	if _rooted_left > 0.0:   # rooted: can turn and aim, not walk
		move = Vector2.ZERO
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
	_move_in = move + chase
	_tick_channel(delta)
	if _dash_time > 0.0:
		var part := minf(delta, _dash_time) / delta   # the last frame moves only what is left: no overshoot past the plan
		_dash_time -= delta
		velocity = _dash_vec * _dash_speed * part
		if not _ghost and shore_guard(velocity) != velocity:   # a lunge (Shield Charge) runs on the ground: it stops at the shore
			_dash_time = 0.0
			velocity = Vector2.ZERO
	elif _stun_left > 0.0:
		velocity = Vector2.ZERO   # knockback (a hook's pull, a launch) still carries a stunned player
		if _charge_slot >= 0:
			cancel_charge()   # a stun breaks the draw
	else:
		if _dash_pressed() and dash_charges > 0 and not burdened() and _frozen_left <= 0.0 and _rooted_left <= 0.0:
			_start_dash(move)
		if _frozen_left > 0.0:
			chase = Vector2.ZERO   # rooted: a held attack cannot walk you anywhere either
		velocity = (move + chase) * speed * _speed_mult() * (ATTACK_MOVE if _cast_time > 0.0 else 1.0)  # a swing slows you a little instead of rooting you (move or chase is zero)
		velocity = shore_guard(velocity)   # you never walk into the water yourself: only a knockback (added below) puts you in
		_try_cast()
		_try_emote()
	knock = knock_guard(knock)
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
	_tick_status(delta)
	_cast_time = maxf(_cast_time - delta, 0.0)
	_tick_stun(delta)
	_phase_left = maxf(_phase_left - delta, 0.0)
	_update_sink(delta)   # puppets only show the sinking; the owner decides when it kills
	_apply_look()
	if down:
		return
	var off := net_pos - position
	var before := position
	if off.length() > 300.0:
		position = net_pos
		reset_physics_interpolation()   # a teleport (respawn, blink): no streak across the map
	else:
		position = position.lerp(net_pos, 1.0 - exp(-20.0 * delta))
	velocity = (position - before) / delta   # never moved by physics here; the soft lock leads a puppet by this
	_animate(off if off.length() > 3.0 else Vector2.ZERO)

## Counts time over water (shared by owner and puppets so everyone sees the sinking). True once the drowning is complete.
func _update_sink(delta: float) -> bool:
	if down or not water_check.is_valid():
		return false
	if water_check.call(global_position + Vector2(0, 14)):
		if _sink == 0.0:
			Sfx.play("splash", global_position)
			SheetFrames.play_once(get_parent(), global_position + Vector2(0, 20), SheetFrames.FX + "AoE/IceAoE/", 0, 30.0, 0.25).modulate = Color(0.55, 0.75, 1.0)
		_sink += delta
	else:
		_sink = 0.0
	return _sink >= SINK_TIME

## Size, tint and wobble from the active forms (giant / chicken) and the sinking fade. self_modulate, so _flash() keeps its own tween.
func _apply_look() -> void:
	if burn != _burn_shown or _angel_left > 0.0 or _parry_left > 0.0 or _spin_left > 0.0 or _empowered_left > 0.0 or (ai and PlaySettings.bot_debug):
		_burn_shown = burn
		queue_redraw()   # the status marks below follow every frame while one is on
	if charge_show > 0.0 or _charge_drawn:   # the aim line follows the aim every frame while drawing, on every screen
		_charge_drawn = charge_show > 0.0
		queue_redraw()
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
	elif _frozen_left > 0.0:
		tint = tint * Color(0.55, 0.85, 1.35)   # iced over, standing stiff (no wobble: it can still swing)
	elif _stun_immune > 0.0:
		tint = tint.lerp(Color(1.4, 1.4, 1.6), 0.35 + 0.15 * sin(Time.get_ticks_msec() * 0.03))   # pale shimmer: can't be stunned
	if down:
		_sprite.rotation = PI / 2.0   # knocked flat until the respawn (the sheets have no death animation)
	_shape.radius = 14.0 * maxf(s, 1.0)   # a giant is also harder to miss
	var sink := clampf(_sink / SINK_TIME, 0.0, 1.0)
	_punch = move_toward(_punch, 0.0, get_physics_process_delta_time() * 7.0)
	_sprite.scale = Vector2(1.0 + 0.3 * _punch, 1.0 - 0.3 * _punch) * s * (1.0 - 0.7 * sink) * SPRITE_SCALE
	_sprite.position = Vector2(0, -(s - 1.0) * 20.0)   # keep the feet on the ground while resizing
	if _freeze > 0.0:
		_freeze -= get_physics_process_delta_time()
		_sprite.position.x += 3.0 if Engine.get_physics_frames() % 2 else -3.0   # shudder while the frame holds
		if _freeze <= 0.0 and not down:
			_sprite.play()   # resumes the paused animation where it stopped
	_sprite.self_modulate = Color(tint, (1.0 - sink) * (0.35 if _phase_left > 0.0 or veiled() else 1.0))
	modulate.a = 0.0 if veiled() and not is_local(self) else 1.0   # veiled: gone from everyone else's screen, name and bar too

## Drowned: the owner announces the death, crediting the last player who hit us recently.
func _fall() -> void:
	var killer := last_hit_peer if Time.get_ticks_msec() - last_hit_msec < LAST_HIT_WINDOW * 1000.0 else 0
	_net_died.rpc(killer, "fall")

func _tick_timers(delta: float) -> void:
	_tick_status(delta)
	_tick_burn(delta)
	_iframes = maxf(_iframes - delta, 0.0)
	_cast_time = maxf(_cast_time - delta, 0.0)
	_slow_left = maxf(_slow_left - delta, 0.0)
	_tick_stun(delta)
	_phase_left = maxf(_phase_left - delta, 0.0)
	_queued_time -= delta
	if _queued_time <= 0.0:
		_queued = -1
	knock = knock.move_toward(Vector2.ZERO, KNOCK_DECEL * delta)
	for i in cooldowns.size():
		cooldowns[i] = maxf(cooldowns[i] - delta, 0.0)
	_ult_lock = maxf(_ult_lock - delta, 0.0)
	if dash_charges < MAX_DASH:
		dash_recharge -= delta
		if dash_recharge <= 0.0:
			dash_charges += 1
			dash_recharge = DASH_RECHARGE

func _dash_pressed() -> bool:
	return ai.take_dash() if ai else Input.is_action_just_pressed(_p + "dash")

## The mouse buttons (LMB, RMB) belong to the panel under the cursor; the ult's key still works.
func _on_ui(slot: int) -> bool:
	return pointer_on_ui and slot < ULT_SLOT

func _held(slot: int) -> bool:
	if slot >= spells.size() or _on_ui(slot):
		return false   # also a hero with no ult: F does nothing
	return ai.held[slot] if ai else Input.is_action_pressed(_p + SLOTS[slot])

func _update_aim(move: Vector2) -> void:
	if ai:
		aim_pos = ai.aim_pos
		aim_dir = (aim_pos - global_position).normalized() if aim_pos.distance_to(global_position) > 4.0 else aim_dir
		return
	if (player_index == 0 or online) and _mouse_aim and PlaySettings.aim_facing:
		if move != Vector2.ZERO:   # playtest toggle: attacks go the way you walk, the cursor does nothing
			aim_dir = move.normalized()
		aim_pos = global_position + aim_dir * AIM_REACH
	elif (player_index == 0 or online) and _mouse_aim:
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

## Jump by `offset` over `time` seconds (Judgement): a slow ghost dash, so it sails over rocks but not the room walls,
## and lands on a free spot (_end_ghost). Owner only, like any movement.
func leap(offset: Vector2, time: float) -> void:
	_cast_time = 0.0
	_dash_vec = offset.normalized() if offset.length() > 1.0 else aim_dir
	_dash_time = time
	_dash_speed = offset.length() / maxf(time, 0.01)
	_ghost = true
	collision_mask = WALL_MASK
	knock = Vector2.ZERO

## Bulwark (Knight passive): true when a hit coming from `from_pos` lands on the side this player is facing.
func faces(from_pos: Vector2) -> bool:
	var off := from_pos - global_position
	return off.length() > 1.0 and aim_dir.dot(off.normalized()) > 0.3

## Slows movement to `mult` for `secs` (refreshing, not stacking). Only the owner simulates movement, so only it needs this.
func apply_slow(mult: float, secs: float) -> void:
	_slow_mult = mult
	_slow_left = maxf(_slow_left, secs)

func _tick_stun(delta: float) -> void:
	_stun_immune = maxf(_stun_immune - delta, 0.0)
	if _stun_left > 0.0:
		_stun_left -= delta
		if _stun_left <= 0.0:
			_stun_left = 0.0
			_stun_immune = STUN_IMMUNITY
	if _frozen_left > 0.0:   # a freeze is a hold like a stun: when it thaws, the same immunity follows
		_frozen_left -= delta
		if _frozen_left <= 0.0:
			_frozen_left = 0.0
			_stun_immune = STUN_IMMUNITY

## Frozen for `secs`: rooted, no dash, facing locked, but still able to attack. Shares the stun rules: never stacks
## onto a stun or another freeze, never lands during the immunity after one, and starts that immunity when it thaws,
## so a stun and a freeze cannot be chained either. Safe on any peer, like stun().
func freeze(secs: float) -> void:
	if down or secs <= 0.0 or _stun_left > 0.0 or _frozen_left > 0.0 or _stun_immune > 0.0 or _spin_left > 0.0:
		return
	float_text("FROZEN", ShadowRush.ICE, 18)
	if is_inside_tree():
		Sfx.play("crown", global_position, -8.0, 2.2)   # the stun "ding", higher and glassier
	_frozen_left = secs
	_frozen_aim = aim_dir

func frozen() -> bool:
	return _frozen_left > 0.0

## Stunned for `secs`. A stun never stacks onto or extends another, and none lands for STUN_IMMUNITY after one wears
## off, so the longest a player can be held is one stun. Safe on any peer: see _stun_left. Every peer runs the same
## stun calls in the same order, so they agree on the immunity too.
func stun(secs: float) -> void:
	if down or secs <= 0.0 or _stun_left > 0.0 or _frozen_left > 0.0 or _stun_immune > 0.0 or _spin_left > 0.0:
		return
	float_text("STUNNED", Color(1.0, 0.95, 0.4), 18)
	if is_inside_tree():
		Sfx.play("crown", global_position, -8.0, 1.6)   # the bell clip, high and quiet: a stun "ding"
	_stun_left = secs

## Sprite hit-stop: hold the current frame for `secs`. Visual only: movement, timers and the network never pause.
func hit_freeze(secs: float) -> void:
	if down or not is_instance_valid(_sprite):
		return
	_freeze = maxf(_freeze, secs)
	_sprite.pause()

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
	collision_mask = SOLID_MASK | WALL_MASK | LOW_MASK
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
	q.collision_mask = SOLID_MASK | WALL_MASK | LOW_MASK   # never land inside a rail either
	q.exclude = [get_rid()]
	return not get_world_2d().direct_space_state.intersect_shape(q, 1).is_empty()

const SHORE_LOOK_WALK := 18.0   ## a step this far ahead of the feet must stay dry
const DASH_SHORE_MARGIN := 20.0 ## a dash cut short by the water stops this far before the edge

## Walking velocity `v` with any part that would step into deadly water taken out: straight on if dry, else slide along
## the shore on one axis, else stop. Knockback is added after this, so a hit still throws you in.
func shore_guard(v: Vector2) -> Vector2:
	if v.length() < 1.0 or not water_check.is_valid():
		return v
	var feet := global_position + Vector2(0, 14)
	if water_check.call(feet):
		return v   # already in (knocked in): no rescue, the sinking decides
	if not water_check.call(feet + v.normalized() * SHORE_LOOK_WALK):
		return v
	for part: Vector2 in [Vector2(v.x, 0.0), Vector2(0.0, v.y)]:
		if part.length() > 1.0 and not water_check.call(feet + part.normalized() * SHORE_LOOK_WALK):
			return part
	return Vector2.ZERO

const KNOCK_SHORE_MIN := 350.0   ## a knock slower than this is a flinch, not a launch: it never tips anyone into the water

## A flinch (a light hit's little shove, under KNOCK_SHORE_MIN) that would tip us into the water is dropped; a real
## launch (a finisher, a charge, a Meteor, a full Power Shot, a hit at low HP) goes through: that is the ring-out.
func knock_guard(k: Vector2) -> Vector2:
	if k.length() < 1.0 or k.length() >= KNOCK_SHORE_MIN or not water_check.is_valid():
		return k
	var feet := global_position + Vector2(0, 14)
	if water_check.call(feet) or not water_check.call(feet + k.normalized() * SHORE_LOOK_WALK):
		return k
	return Vector2.ZERO

## Dash length check: a dash of `offset` from `from` that would end over water is cut short to end on the last dry
## ground along its path (it may still cross a narrow channel if the far side is dry). Returns the dash time to use.
func dash_time_to_shore(from: Vector2, offset: Vector2, full_time: float) -> float:
	var off := ground_check if ground_check.is_valid() else water_check
	if not off.is_valid() or offset.length() < 1.0:
		return full_time
	var feet := from + Vector2(0, 14)
	if off.call(feet) or not off.call(feet + offset):
		return full_time
	var step := offset.normalized() * 12.0
	var reach := offset.length()
	var d := reach
	while d > 0.0 and off.call(feet + offset.normalized() * d):
		d -= step.length()
	d -= DASH_SHORE_MARGIN   # stop a little short of the edge, not on it
	return full_time * maxf(d, 0.0) / reach

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
	reset_physics_interpolation()
	net_pos = position
	velocity = Vector2.ZERO
	knock = Vector2.ZERO

func _start_dash(move: Vector2) -> void:
	dash_charges -= 1
	cancel_charge()   # the dash is the escape: it drops a drawn bow
	if dash_recharge <= 0.0:
		dash_recharge = DASH_RECHARGE
	_cast_time = 0.0  # dash cancels the cast lock
	Sfx.play("dash", global_position)
	_dash_vec = move if move != Vector2.ZERO else aim_dir
	_dash_time = dash_time_to_shore(global_position, _dash_vec * DASH_SPEED * DASH_TIME, DASH_TIME)
	_dash_speed = DASH_SPEED
	_ghost = true
	collision_mask = WALL_MASK   # rocks are passable for the dash; the room walls still hold
	_iframes = maxf(_iframes, DASH_TIME + 0.05)
	SheetFrames.play_once(get_parent(), global_position + Vector2(0, 20), SheetFrames.FX + "AoE/IceAoE/", 0, 30.0, 0.18).modulate = Color(1, 1, 1, 0.6)

## True while an attack button is held or the cast anim is still playing (no gap between rapid taps).
func _firing() -> bool:
	if _cast_time > 0.0 or _queued >= 0:
		return true
	if _puppet:
		return false
	for i in SLOTS.size():
		if _held(i):
			return true
	return false

## True while a held basic attack is still walking toward a foe it cannot reach yet. Like Dota's attack order, nothing
## is swung or fired until the foe is in reach (a foe already lockable by the cursor or aim cone still counts as in reach).
func _chase_pending() -> bool:
	if not is_instance_valid(_chase) or _chase.down:
		return false
	return global_position.distance_to(_chase.global_position) > spell_in(0).reach()

## Hold-and-release (Power Shot). Owner only. Holding builds `charge` (faster standing still with Steady Aim), the aim
## stays free the whole time (puppets see it through the synced aim_dir and charge_show), and letting go, or holding to
## the spell's max_hold, sends the cast with power = charge / charge_time. A stun or a dash drops the draw (no cooldown).
func _tick_charge(delta: float) -> bool:
	if _charge_slot < 0:
		return false
	var spell := spell_in(_charge_slot)
	if spell == null or spell.charge_time() <= 0.0 or buffed("chicken"):
		cancel_charge()
		return false
	_charge += delta * draw_rate()
	_charge_held += delta
	apply_slow(DRAW_SLOW, 0.1)
	var was_full := charge_show >= 1.0
	charge_show = clampf(_charge / spell.charge_time(), 0.01, 1.0)
	if charge_show >= 1.0 and not was_full and is_local(self):
		Sfx.play("crown", global_position, -6.0, 1.8)   # full draw: the ding that says let go
	var release: bool = (not _held(_charge_slot)) if ai == null else (charge_show >= 1.0 or not ai.held[_charge_slot])   # a bot always draws to full
	if release or _charge_held >= spell.max_hold():
		var slot := _charge_slot
		var p := charge_show
		cancel_charge()
		_net_cast.rpc(slot, spell.aim(self, aim_dir), aim_pos, randi(), NodePath(), p)
	return true

# --- kit statuses -------------------------------------------------------------------------------------------

## Why a hit from `attacker` would not land on this player, checked before any damage maths: "miss" (the attacker is
## in a foe's Smoke Screen and swung blind; rolled here, once, on the victim's peer), "immune" (Guardian Angel, Blade
## Fury), "parry" (a Riposte stance), or "" (it lands). A burn tick only stops on "immune".
func hit_blocked(attacker: Node, reflected := false) -> String:
	if not _burning and not reflected and attacker is Player and attacker != self and attacker.smoked() and randf() < SMOKE_MISS:
		return "miss"
	if _angel_left > 0.0 or _spin_left > 0.0:
		return "immune"
	if _parry_left > 0.0 and not _burning and not reflected:
		return "parry"
	return ""

## Our hit landed on `amount`. Owner of the attacker only (see take_damage): banks the ult and heals for any lifesteal
## (Paladin Hammer, Guardian Angel).
func on_hit_landed(amount: int) -> void:
	charge_ult(amount)
	if hero == null or down or amount <= 0:
		return
	var steal := hero.lifesteal + (ANGEL_STEAL if _angel_left > 0.0 else 0.0)
	if steal > 0.0 and hp < max_hp:
		heal(maxi(roundi(amount * steal), 1))
		if online and is_inside_tree():
			_net_hp.rpc(hp)

## Kindling: `n` more Burn stacks (capped), lit by `by`. Victim's owner only (take_damage).
func add_burn(n: int, by: Node) -> void:
	if down:
		return
	if burn == 0:
		_burn_tick = BURN_TICK
		_burn_decay = BURN_DECAY
	burn = mini(burn + n, BURN_MAX)
	_burn_by = by

func _tick_burn(delta: float) -> void:
	if burn <= 0 or down:
		return
	_burn_tick -= delta
	if _burn_tick <= 0.0:
		_burn_tick += BURN_TICK
		_burning = true
		take_damage(burn, global_position, true, _burn_by if is_instance_valid(_burn_by) else null)
		_burning = false
	_burn_decay -= delta
	if _burn_decay <= 0.0:
		_burn_decay += BURN_DECAY
		burn = maxi(burn - 1, 0)

## The timed kit statuses, ticked on every peer (they were all started by a cast that ran everywhere).
func _tick_status(delta: float) -> void:
	_angel_left = maxf(_angel_left - delta, 0.0)
	_parry_left = maxf(_parry_left - delta, 0.0)
	_spin_left = maxf(_spin_left - delta, 0.0)
	_empowered_left = maxf(_empowered_left - delta, 0.0)
	_rooted_left = maxf(_rooted_left - delta, 0.0)
	_veiled_left = maxf(_veiled_left - delta, 0.0)
	_smoked_left = maxf(_smoked_left - delta, 0.0)
	_revealed_left = maxf(_revealed_left - delta, 0.0)
	_ff_left = maxf(_ff_left - delta, 0.0)
	if _parry_left > 0.0 and owns():
		apply_slow(0.5, 0.1)   # braced: a slow shuffle

func guardian(secs: float) -> void:
	_angel_left = secs

func parry(secs: float) -> void:
	_parry_left = secs

func spin(secs: float) -> void:
	_spin_left = secs
	_frozen_left = 0.0   # a freeze that landed the same frame as the cast does not survive it (a stunned player cannot cast at all)

func empower(secs: float) -> void:
	_empowered_left = secs

func root(secs: float) -> void:
	_rooted_left = maxf(_rooted_left, secs)

func rooted() -> bool:
	return _rooted_left > 0.0

## Smoke Screen keeps these up while you stand in it (refreshing, like a slow).
func veil(secs: float) -> void:
	_veiled_left = maxf(_veiled_left, secs)

func veiled() -> bool:
	return _veiled_left > 0.0 and _revealed_left <= 0.0

## Focus Fire: auto-fire the basic at `t` for `secs` (FocusFire.RATE x faster, FocusFire.DAMAGE_MULT per arrow).
func focus_fire_on(t: Node2D, secs: float) -> void:
	_ff_target = t
	_ff_left = secs

func focus_firing() -> bool:
	return _ff_left > 0.0 and is_instance_valid(_ff_target)

## Owner only: while focusing, the basic fires at the target by itself whenever it is ready and the target is in reach.
## Returns true if it fired this frame.
func _try_focus_fire() -> bool:
	if not focus_firing() or _ff_target.down or spells.is_empty() or cooldowns[0] > 0.0 or weapon_active(0):
		return false
	var b := spell_in(0)
	if global_position.distance_to(_ff_target.global_position) > b.reach() + 40.0:
		return false   # out of range: the fire pauses until it is back in reach
	var dir := (_ff_target.global_position - global_position).normalized()
	_net_cast.rpc(0, dir, _ff_target.global_position, randi(), _ff_target.get_path(), 1.0)
	return true

## Lightning Bolt: seen through any Smoke Screen for `secs`.
func reveal(secs: float) -> void:
	_revealed_left = maxf(_revealed_left, secs)

func smoke(secs: float) -> void:
	_smoked_left = maxf(_smoked_left, secs)

func smoked() -> bool:
	return _smoked_left > 0.0

func guarded() -> bool:
	return _angel_left > 0.0

func parrying() -> bool:
	return _parry_left > 0.0

func spinning() -> bool:
	return _spin_left > 0.0

## Tumble: true (and spent) if the next basic is empowered. Called by the basic's cast on every peer, so all agree.
func consume_empower() -> bool:
	if _empowered_left <= 0.0:
		return false
	_empowered_left = 0.0
	return true

## Riposte: the victim's owner (this Shade) counters `attacker`: blinks next to it if it is close enough, and every
## peer applies a guaranteed crit from the basic. Out of reach, the hit is still cancelled.
func _riposte(attacker: Player) -> void:
	if global_position.distance_to(attacker.global_position) > RIPOSTE_RANGE:
		return
	var side := (global_position - attacker.global_position).normalized()
	blink_to(attacker.global_position + (side if side != Vector2.ZERO else Vector2.LEFT) * 56.0)
	aim_dir = (attacker.global_position - global_position).normalized()
	_net_riposte.rpc(attacker.get_path())

@rpc("authority", "call_local", "reliable")
func _net_riposte(target_path: NodePath) -> void:
	var t := get_node_or_null(target_path) as Node2D
	if t == null or spells.is_empty():
		return
	Sfx.play("swing", global_position, 3.0, 0.6)
	SheetFrames.play_once(get_parent(), t.global_position + Vector2(0, 10), SheetFrames.FX + "AoE/SwordAoE/", 0, 30.0, 0.3)
	if t.has_method("float_text"):
		t.float_text("RIPOSTE CRIT", Color(0.7, 0.95, 1.0), 22)
	t.take_damage(roundi(spells[0].damage * RIPOSTE_CRIT), global_position, false, self)
	var b := spells[0] as HeroBasic
	if b:
		b.prime_focus(t)   # Focus: the counter leaves you one hit from the next crit

func _draw_statuses() -> void:
	var font := ThemeDB.fallback_font
	if ai and PlaySettings.bot_debug:   # playtest: what the bot is doing right now
		var label: String = ai.state_name()
		draw_string_outline(font, Vector2(-60, -112), label, HORIZONTAL_ALIGNMENT_CENTER, 120, 14, 4, Color.BLACK)
		draw_string(font, Vector2(-60, -112), label, HORIZONTAL_ALIGNMENT_CENTER, 120, 14, BotBrain.STATE_COLORS[ai.state])
	if burn > 0:   # flames over the head and the stack count
		var col := Color(1.0, 0.45 + 0.03 * (BURN_MAX - burn), 0.1)
		for i in mini(burn, 6):
			var x := -15.0 + i * 6.0
			draw_colored_polygon(PackedVector2Array([Vector2(x, -74), Vector2(x - 3, -66), Vector2(x + 3, -66)]), col)
		draw_string_outline(font, Vector2(22, -64), "%d" % burn, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color.BLACK)
		draw_string(font, Vector2(22, -64), "%d" % burn, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col)
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.015)
	if _angel_left > 0.0:   # a golden halo and wings of light
		draw_arc(Vector2(0, -92), 16.0, 0.0, TAU, 24, Color(1.0, 0.9, 0.5, 0.9), 3.0)
		draw_circle(Vector2(0, -20), 46.0 + 4.0 * pulse, Color(1.0, 0.9, 0.5, 0.15))
		for sx in [-1.0, 1.0]:
			draw_colored_polygon(PackedVector2Array([Vector2(8 * sx, -50), Vector2(46 * sx, -78), Vector2(36 * sx, -30)]), Color(1.0, 0.95, 0.7, 0.45))
	if _parry_left > 0.0:   # a bright arc in front: hit me now and regret it
		draw_arc(Vector2(0, -10), 40.0, aim_dir.angle() - 1.1, aim_dir.angle() + 1.1, 16, Color(0.75, 0.95, 1.0, 0.6 + 0.4 * pulse), 5.0)
	if _spin_left > 0.0:
		var a := Time.get_ticks_msec() * 0.03
		for k in 3:
			var ang := a + k * TAU / 3.0
			draw_arc(Vector2(0, 0), 110.0, ang, ang + 1.2, 12, Color(0.3, 1.0, 0.55, 0.55), 6.0)
	if _empowered_left > 0.0:
		draw_arc(Vector2(0, 14), 30.0, 0.0, TAU, 20, Color(1.0, 0.85, 0.3, 0.5 + 0.5 * pulse), 3.0)

## Drop and event reads on every screen: the channel ring, the shield, Warcry, Blademail's spikes.
func _draw_drop_states() -> void:
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.015)
	if channeling > 0.0:   # taking a drop: a white ring fills clockwise round the feet, so everyone knows to come stop it
		draw_arc(Vector2(0, 14), 34.0, 0.0, TAU, 32, Color(1, 1, 1, 0.25), 5.0)
		draw_arc(Vector2(0, 14), 34.0, -PI / 2.0, -PI / 2.0 + TAU * channeling, 32, Color(1, 1, 1, 0.95), 5.0)
	if shield_hp > 0 and buffed("shield"):   # a white bubble; its alpha is what is left
		var k := float(shield_hp) / PvpPickup.SHIELD_HP
		draw_circle(Vector2(0, -20), 44.0, Color(0.9, 0.95, 1.0, 0.08 + 0.12 * k))
		draw_arc(Vector2(0, -20), 44.0 + 2.0 * pulse, 0.0, TAU, 32, Color(0.92, 0.96, 1.0, 0.35 + 0.55 * k), 3.0)
	if buffed("warcry"):   # red-orange glow and a shove arrow the way you face
		draw_circle(Vector2(0, 14), 36.0 + 4.0 * pulse, Color(1.0, 0.4, 0.2, 0.18 + 0.1 * pulse))
		var tip := Vector2(0, 14) + aim_dir * 50.0
		var side := aim_dir.orthogonal() * 9.0
		draw_colored_polygon(PackedVector2Array([tip, tip - aim_dir * 16.0 + side, tip - aim_dir * 16.0 - side]), Color(1.0, 0.5, 0.25, 0.75))
	if MatchEvent.is_on(MatchEvent.BLADEMAIL):   # thin spiked ring: every hit on this one bites back
		var c := MatchEvent.color(MatchEvent.BLADEMAIL)
		for i in 10:
			var a := TAU * i / 10.0 + Time.get_ticks_msec() * 0.0006
			var base := Vector2(0, 14) + Vector2(cos(a), sin(a) * 0.55) * 30.0
			draw_line(base, base + Vector2(cos(a), sin(a) * 0.55) * 7.0, Color(c, 0.7), 2.0)

## How fast a draw fills: STEADY_RATE standing still with Steady Aim (Ranger passive), else 1.
func draw_rate() -> float:
	return STEADY_RATE if hero and hero.steady_aim and velocity.length() < 12.0 else 1.0

## The kit's hold-and-release spell (the one charge_show belongs to), or null.
func charge_spell() -> Spell:
	for sp in spells:
		if sp and sp.charge_time() > 0.0:
			return sp
	return null

## Drops a draw without casting (a stun, a dash, death).
func cancel_charge() -> void:
	_charge_slot = -1
	_charge = 0.0
	_charge_held = 0.0
	charge_show = 0.0

func _try_cast() -> void:
	if buffed("chicken") or _spin_left > 0.0:
		return   # a chicken cannot cast; Blade Fury is the attack while it spins
	if _tick_charge(get_physics_process_delta_time()):
		return   # the bow is drawn: nothing else goes out until it is loosed
	_try_focus_fire()   # Focus Fire: the basic goes by itself; the other buttons still work
	for i in SLOTS.size():
		if ai == null and i < spells.size() and not _on_ui(i) and Input.is_action_just_pressed(_p + SLOTS[i]):
			if i == ULT_SLOT and ult_ready() and not spells[i].can_cast(self, aim_pos):
				float_text("Nobody in reach", Color(0.8, 0.8, 0.8), 16)   # the charge is kept
			elif cooldowns[i] > 0.0:
				_queued = i
				_queued_time = BUFFER_TIME
	for i in SLOTS.size():
		var spell := spell_in(i)
		if i == ULT_SLOT and (not ult_ready() or spell == null or not spell.can_cast(self, aim_pos)):
			continue
		if spell and cooldowns[i] <= 0.0 and (_queued == i or _held(i)):
			var foe := spell.target(self, aim_pos, aim_dir)   # lock-on: the cast goes for this foe on every peer
			if foe == null and i == 0 and is_instance_valid(_chase) and not _chase.down and not _chase_pending():
				foe = _chase   # the foe a held attack walked up to, even if the cursor has left it
			# Out of reach: the attack still goes, at full range toward the cursor (holding keeps walking you closer).
			# No target: the attack goes where you aim, a free swing or shot at the ground. The visible whiff is the
			# feedback that teaches new players to aim at someone; lock-on only assists.
			_queued = -1
			if spell.charge_time() > 0.0 and not weapon_active(i):   # hold-and-release: start drawing, the cast goes out on release
				_charge_slot = i
				_charge = 0.0
				_charge_held = 0.0
				charge_show = 0.01
				Sfx.play("swing", global_position, -6.0, 0.7)
				return
			var dir := (foe.global_position - global_position).normalized() if foe else spell.aim(self, aim_dir)
			_net_cast.rpc(i + (WEAPON_CAST if weapon_active(i) else 0), dir, aim_pos, randi(), foe.get_path() if foe else NodePath(), 1.0)
			return

## Runs on every peer (offline: just here), so every screen gets the same projectiles / sweeps / explosions.
## Damage still only lands on the victim's own peer (see take_damage).
@rpc("authority", "call_local", "reliable")
func _net_cast(slot: int, dir: Vector2, pos: Vector2, seed_value: int, lock_path := NodePath(), cast_power := 1.0) -> void:
	var weapon: FsWeapon = null
	if slot >= WEAPON_CAST:   # the Friendslop weapon held in slot - WEAPON_CAST
		slot -= WEAPON_CAST
		weapon = weapons[slot]
	if weapon == null and slot >= spells.size():
		return
	var spell: Spell = weapon if weapon != null else spells[slot]
	if slot == ULT_SLOT:
		ult_charge = 0.0
		_ult_lock = spell.ult_lock()   # nothing charges the next ult until this one is over (its own ticks never pay for it)
		if is_local(self):
			Sfx.play("crown", global_position, -2.0, 1.3)
	rng.seed = seed_value
	spell.lock = null if lock_path.is_empty() else get_node_or_null(lock_path) as Node2D   # node paths match on every peer
	spell.power = cast_power
	var cd := spell.cast(self, dir, pos)
	spell.lock = null
	spell.power = 1.0
	if weapon != null:
		cd *= cooldown_mult
		weapon.uses -= 1
		if weapon.uses <= 0:
			weapons[slot] = null
			float_text("%s empty" % weapon.display_name, Color(0.8, 0.8, 0.8))
	if slot == 0 and weapon == null and _ff_left > 0.0:
		cd /= FocusFire.RATE   # Focus Fire: the bow sings
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

## Locomotion sheets by where the legs go, a quarter turn at a time clockwise from the aim (screen y points down,
## so clockwise of the facing is the hero's right).
const RUN_ANIMS := ["run", "strafe_r", "run_back", "strafe_l"]
const RUN_SHEETS := {"run": "Run.png", "strafe_r": "StrafeRight.png", "run_back": "RunBackwards.png", "strafe_l": "StrafeLeft.png"}

## Always faces the aim (aim_dir is replicated, so puppets and bots show the same facing); the legs pick
## run / strafe / backpedal from the move direction relative to it, so walking away from the cursor never moonwalks.
func _animate(move: Vector2) -> void:
	SheetFrames.face(_sprite, _dirs, aim_dir)
	if _cast_time > 0.0:
		return
	_sprite.speed_scale = 1.0
	var anim := "idle" if move == Vector2.ZERO else _run_anim(move)
	if _sprite.animation == anim:
		return
	if anim != "idle" and _sprite.animation in RUN_ANIMS:   # same 15-frame stride: keep the step, only swap the sheet
		var fr := _sprite.frame
		var prog := _sprite.frame_progress
		_sprite.play(anim)
		_sprite.set_frame_and_progress(fr, prog)
	else:
		_sprite.play(anim)

func _run_anim(move: Vector2) -> String:
	var rel := angle_difference(aim_dir.angle(), move.angle())
	var cur := RUN_ANIMS.find(_sprite.animation)
	if cur >= 0 and absf(angle_difference(cur * PI / 2.0, rel)) < PI / 4.0 + SheetFrames.FACE_HYSTERESIS:
		return _sprite.animation   # still near the current sheet's quarter: no flip-flop on a diagonal
	var anim: String = RUN_ANIMS[wrapi(roundi(rel / (PI / 2.0)), 0, 4)]
	return anim if _sprite.sprite_frames.has_animation(anim) else "run"

## Only the player's own peer applies damage; everyone else's copy of the same hit is a no-op (victim-side hits).
## Returns true when the hit landed (on other peers: when it looks like it did), so stuns and pulls skip a dodged hit.
## `cause` names the death in the kill feed when this hit kills ("" = "hit" from a player, "bomb" otherwise; an
## Explosion passes its own; "reflect" = Blademail, which also skips every attacker-side effect so it never chains).
func take_damage(amount: int, from_pos: Vector2, silent := false, attacker: Node = null, cause := "") -> bool:
	if down:
		return false
	if attacker is Player and attacker != self and team >= 0 and attacker.team == team and not friendly_fire:
		return false
	var reflected := cause == "reflect"
	if not owns():
		# Our own hit on somebody else's player: show the impact now instead of waiting for their peer's reply.
		# ponytail: predicted, so it also fires when their i-frames ate the hit; replicate _iframes if that reads wrong.
		if not silent and is_local(attacker):
			_punch = 1.0
			_flash()
			hit_fx(self, amount, true, false, false, attacker)   # our hit on somebody else: the freeze, never a shake
		if attacker is Player and attacker != self and attacker.owns() and not reflected:
			attacker.on_hit_landed(amount)   # predicted like the impact above: the attacker's peer is the only one that banks it
			_reflect(attacker, amount)
		return true
	if _iframes > 0.0 and not _burning and not reflected:   # i-frames stop hits, not a burn already lit or a reflection
		return false
	match hit_blocked(attacker, reflected):
		"miss":   # Smoke Screen: the attacker swings blind
			if not silent:
				float_text("MISS", Color(0.75, 0.75, 0.8), 16)
			return false
		"immune":   # Guardian Angel / Blade Fury: nothing gets through
			if not silent:
				float_text("IMMUNE", Color(1.0, 0.9, 0.5), 16)
			return false
		"parry":   # Riposte: the hit is cancelled, a player who struck us is countered
			_parry_left = 0.0
			float_text("PARRY!", Color(0.7, 0.95, 1.0), 22)
			if attacker is Player and attacker != self:
				_riposte(attacker)
			return false
	if attacker is Player and attacker.buffed("damage") and not reflected:   # victim-side hit: read the attacker's copy of the buff
		amount *= 2
	if hero and hero.front_mult < 1.0 and faces(from_pos) and not reflected:   # Bulwark: the shield takes the front
		var blocked := amount - roundi(amount * hero.front_mult)
		amount -= blocked
		if blocked >= 3:
			float_text("BLOCK", Color(0.7, 0.85, 1.0), 16)
	if attacker is Player and attacker != self and attacker.hero and attacker.hero.static_field > 0.0 and not _burning and not reflected:
		amount += roundi(hp * attacker.hero.static_field)   # Static Field (Sorcerer): a slice of what you have left
	if hero and hero.taken_mult != 1.0:   # Glass Cannon (Scout) takes more
		amount = maxi(roundi(amount * hero.taken_mult), 1)
	amount = form_damage(roundi(amount * RuleSet.current.damage))
	break_channel()   # any hit drops a drop channel
	if shield_hp > 0 and buffed("shield") and amount > 0:   # Shield drop: the bubble eats it first
		var absorbed := mini(shield_hp, amount)
		shield_hp -= absorbed
		amount -= absorbed
		float_text("ABSORB %d" % absorbed, Color(0.92, 0.96, 1.0), 16)
		if shield_hp <= 0:
			buffs.erase("shield")
		if amount <= 0:
			_flash()
			return true   # the hit landed (a stun or pull still takes), it just did not hurt
	if attacker is Player and attacker != self and attacker.owns() and not reflected:
		attacker.on_hit_landed(amount)   # attacker and victim simulated on the same peer (a bot, offline co-op)
	if attacker is Player and attacker != self and attacker.hero and attacker.hero.kindling and not _burning and not reflected:
		add_burn(1, attacker)   # Kindling: every Mage hit stacks another Burn
	charge_ult(amount * ULT_TAKEN)
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
			hit_fx(self, amount, is_local(self) or is_local(attacker), hp == 0, is_local(self), attacker)
	if reflected:   # Blademail: a grey number and a tink, so the attacker reads what just bit him
		float_text("-%d" % amount, MatchEvent.color(MatchEvent.BLADEMAIL), 15)
		Sfx.play("hit", global_position, -10.0, 1.7)
	else:
		_hit_number(amount)
	_flash()
	hp_changed.emit(hp, max_hp)
	if not reflected and attacker is Player and attacker != self and attacker.owns():
		_reflect(attacker, amount)
	if not online:
		if hp == 0:
			_die()
		return true
	if hp == 0:
		if cause == "":
			cause = "hit" if attacker is Player else "bomb"   # no attacker = an ownerless Explosion (the hot potato)
		_net_died.rpc(attacker.peer_id if attacker is Player else 0, cause)
	else:
		_net_hp.rpc(hp)
	return true

## Blademail (match event): the attacker takes REFLECT of what it just dealt us. Runs on the attacker's own peer (the one
## that just called our take_damage), never for a burn tick, never for a reflection.
func _reflect(attacker: Player, amount: int) -> void:
	if not MatchEvent.is_on(MatchEvent.BLADEMAIL) or _burning or amount <= 0 or attacker.down:
		return
	attacker.take_damage(maxi(roundi(amount * MatchEvent.REFLECT), 1), global_position, true, self, "reflect")

func _flash() -> void:
	_sprite.modulate = Color(2.5, 1.1, 1.1)   # overbright, so it reads as an impact and not just a tint
	create_tween().tween_property(_sprite, "modulate", Color.WHITE, 0.2)

func _hit_number(amount: int) -> void:
	float_text(str(amount), Color(1.0, 0.9, 0.5), 16 + mini(amount / 2, 14))

func _die() -> void:
	down = true
	cancel_charge()
	stop_channel()
	shield_hp = 0
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
	reset_physics_interpolation()
	net_pos = pos
	knock = Vector2.ZERO
	_dash_time = 0.0
	_slow_left = 0.0
	_stun_left = 0.0
	_frozen_left = 0.0
	_stun_immune = 0.0
	burn = 0
	_angel_left = 0.0
	_parry_left = 0.0
	_spin_left = 0.0
	_empowered_left = 0.0
	_rooted_left = 0.0
	_veiled_left = 0.0
	_smoked_left = 0.0
	_revealed_left = 0.0
	_ff_left = 0.0
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
