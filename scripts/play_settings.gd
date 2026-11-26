class_name PlaySettings extends RefCounted
## Local feel toggles for playtesting (Esc menu). Per player, per machine: never synced, never part of a match's rules.
## Saved to user://play_settings.cfg so a choice survives a restart.

const PATH := "user://play_settings.cfg"

## false: attacks go toward the mouse (default). true: attacks go the way you face (your last move direction), the
## cursor is ignored and ground-targeted skills land AIM_REACH ahead of you, like on a gamepad without a right stick.
static var aim_facing := false
## true: a melee basic locked onto a foe steps in (up to HeroBasic.LOCK_STEP) to reach it. false (default): it swings
## where you stand; holding the attack still walks you up to the foe (hold-to-chase).
static var melee_step := false
## true: every bot shows its state (Roam / Engage / Retreat / Objective / Hold / Potato) over its head.
static var bot_debug := false

static var _loaded := false

static func load_once() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	aim_facing = bool(cfg.get_value("play", "aim_facing", aim_facing))
	melee_step = bool(cfg.get_value("play", "melee_step", melee_step))
	bot_debug = bool(cfg.get_value("play", "bot_debug", bot_debug))

static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("play", "aim_facing", aim_facing)
	cfg.set_value("play", "melee_step", melee_step)
	cfg.set_value("play", "bot_debug", bot_debug)
	cfg.save(PATH)
