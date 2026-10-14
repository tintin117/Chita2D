class_name CharacterSheet extends CanvasLayer
## Tab (or gamepad Back) pauses and shows every hero's level, stats, skills and gear.
## Spend skill points while it is open: P1 with keys 1-4, P2 with 5-8. Created by Hud.

const SPEND_KEYS := [[KEY_1, KEY_2, KEY_3, KEY_4], [KEY_5, KEY_6, KEY_7, KEY_8]]
const COL_W := 400.0

var _view := View.new()

func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	add_child(_view)

func _unhandled_input(event: InputEvent) -> void:
	var toggle: bool = (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB) \
		or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_BACK)
	if toggle:
		visible = not visible
		get_tree().paused = visible
		get_viewport().set_input_as_handled()
	elif visible and event is InputEventKey and event.pressed and not event.echo:
		for p: Player in get_tree().get_nodes_in_group("players"):
			var slot: int = SPEND_KEYS[p.player_index % 2].find(event.keycode)
			if slot >= 0:
				p.prog.rank_up(slot)

class View extends Control:
	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var players := get_tree().get_nodes_in_group("players")
		players.sort_custom(func(a: Player, b: Player) -> bool: return a.player_index < b.player_index)
		var vp := get_viewport_rect().size
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.75))
		var x0 := (vp.x - players.size() * CharacterSheet.COL_W) / 2.0 + 20.0
		for n in players.size():
			_draw_player(players[n], Vector2(x0 + n * CharacterSheet.COL_W, 70))
		draw_string(ThemeDB.fallback_font, Vector2(0, vp.y - 24), "Tab: close", HORIZONTAL_ALIGNMENT_CENTER, vp.x, 16, Color(0.7, 0.7, 0.7))

	func _text(pos: Vector2, s: String, font_size := 18, color := Color.WHITE) -> void:
		draw_string(ThemeDB.fallback_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

	func _draw_player(p: Player, o: Vector2) -> void:
		var prog := p.prog
		var need := prog.xp_to_next()
		_text(o, "P%d  %s   Lv %d%s" % [p.player_index + 1, p.hero.display_name, prog.level, " (MAX)" if need == 0 else ""], 26, Color(1, 0.85, 0.4))
		_text(o + Vector2(0, 28), "XP %d / %d" % [prog.xp, need] if need > 0 else "XP maxed", 16, Color(0.6, 0.8, 1.0))
		_text(o + Vector2(0, 52), "Skill points: %d" % prog.skill_points, 18, Color(0.5, 1, 0.5) if prog.skill_points > 0 else Color(0.7, 0.7, 0.7))
		_text(o + Vector2(0, 90), "HP %d    Speed %d    Damage x%.2f    Cooldowns x%.2f" % [p.max_hp, p.speed, p.damage_mult, p.cooldown_mult], 16)
		_text(o + Vector2(0, 126), "Skills", 20, Color(1, 0.85, 0.4))
		var keys: Array = CharacterSheet.SPEND_KEYS[p.player_index % 2]
		for i in mini(4, p.spells.size()):
			var y := 154.0 + i * 30.0
			var sp := p.spells[i]
			var can := prog.can_rank_up(i)
			_text(o + Vector2(0, y), "[%s]" % OS.get_keycode_string(keys[i]), 16, Color(0.5, 1, 0.5) if can else Color(0.5, 0.5, 0.5))
			_text(o + Vector2(36, y), sp.display_name, 18)
			for k in Progression.RANK_CAP:
				draw_rect(Rect2(o + Vector2(190 + k * 14, y - 12), Vector2(10, 12)), Color(1, 0.8, 0.4) if k < prog.ranks[i] else Color(0.3, 0.3, 0.3))
			_text(o + Vector2(268, y), "dmg %d   cd %.2fs" % [sp.damage, sp.cooldown], 14, Color(0.8, 0.8, 0.8))
		_text(o + Vector2(0, 296), "Gear", 20, Color(1, 0.85, 0.4))
		for i in Item.SLOTS.size():
			var it: Item = p.equipment.get(Item.SLOTS[i])
			var y := 324.0 + i * 44.0
			_text(o + Vector2(0, y), Item.SLOTS[i].capitalize() + ":", 16, Color(0.7, 0.7, 0.7))
			if it:
				_text(o + Vector2(80, y), "%s (%s)" % [it.display_name, Item.RARITY_NAMES[it.rarity]], 18, it.color())
				_text(o + Vector2(80, y + 20), it.describe(), 14, Color(0.8, 0.8, 0.8))
			else:
				_text(o + Vector2(80, y), "empty", 16, Color(0.5, 0.5, 0.5))
