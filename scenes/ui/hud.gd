class_name Hud extends CanvasLayer
## Per-player panel: HP bar (Tiny Swords bar art), dash pips, 4 spell slots with cooldown overlay, signature meter.

const BAR_TEX := preload("res://assets/tiny_swords/ui/BigBar_Base.png")
const FILL_TEX := preload("res://assets/tiny_swords/ui/BigBar_Fill.png")
const HINTS := [["LMB", "RMB", "Q", "R"], ["RT", "LB", "RB", "Y"]]

func add_player(p: Player) -> void:
	var panel := PlayerPanel.new()
	panel.player = p
	panel.size = Vector2(340, 130)
	panel.mirror = p.player_index == 1
	add_child(panel)

var _boss_bar := BossBar.new()

func _ready() -> void:
	_boss_bar.size = Vector2(640, 48)
	add_child(_boss_bar)

func _process(_delta: float) -> void:
	var vp := get_viewport().get_visible_rect().size
	_boss_bar.position = Vector2((vp.x - _boss_bar.size.x) / 2.0, 24)
	for c in get_children():
		if c is PlayerPanel:
			c.position = Vector2(vp.x - c.size.x - 20 if c.mirror else 20.0, vp.y - c.size.y - 16)

## 3-slice bar from the Tiny Swords sheet (left cap / middle / right cap with gaps in the source).
static func draw_bar(c: CanvasItem, w: float, ratio: float) -> void:
	var base: Texture2D = BAR_TEX
	var fill: Texture2D = FILL_TEX
	var cap := 24.0  # caps sit at the inner edge of their 64px cells in the source sheet
	c.draw_texture_rect_region(base, Rect2(0, 0, cap, 48), Rect2(32, 0, 32, 64))
	c.draw_texture_rect_region(base, Rect2(cap, 0, w - 2.0 * cap, 48), Rect2(128, 0, 64, 64))
	c.draw_texture_rect_region(base, Rect2(w - cap, 0, cap, 48), Rect2(256, 0, 32, 64))
	var fw := (w - 2.0 * cap) * clampf(ratio, 0.0, 1.0)
	if fw > 0.5:
		c.draw_texture_rect_region(fill, Rect2(cap, 13, fw, 22), Rect2(0, 0, 64, 64))

class BossBar extends Control:
	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var boss := get_tree().get_first_node_in_group("boss") as Enemy
		if boss == null:
			return
		Hud.draw_bar(self, size.x, float(boss.hp) / boss.max_hp)
		draw_string(ThemeDB.fallback_font, Vector2(0, 40), "BLACK LANCER", HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, Color.WHITE)

class PlayerPanel extends Control:
	var player: Player
	var mirror := false

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if not is_instance_valid(player):
			return
		var font := ThemeDB.fallback_font
		# HP bar: 3-slice base (left cap / middle / right cap) with gaps in the source sheet
		Hud.draw_bar(self, 300.0, float(player.hp) / player.max_hp)
		draw_string(font, Vector2(24, 31), "P%d  %d/%d" % [player.player_index + 1, player.hp, player.max_hp], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
		if player.down:
			draw_string(font, Vector2(130, 31), "DOWN", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 0.4, 0.4))
		# Dash pips
		for i in Player.MAX_DASH:
			var c := Vector2(12 + i * 22, 64)
			draw_circle(c, 8, Color(0, 0, 0, 0.6))
			if i < player.dash_charges:
				draw_circle(c, 6, Color(0.5, 0.85, 1.0))
		# Spell slots
		var hints: Array = Hud.HINTS[player.player_index % 2]
		for i in 4:
			var r := Rect2(90 + i * 56, 50, 50, 50)
			draw_rect(r, Color(0, 0, 0, 0.6))
			var spell: Spell = player.spells[i] if i < player.spells.size() else null
			if spell:
				var name_short := spell.display_name.substr(0, 1)
				draw_string(font, r.position + Vector2(0, 32), name_short, HORIZONTAL_ALIGNMENT_CENTER, 50, 26, Color(1, 0.8, 0.4))
				var cd := player.cooldowns[i]
				if cd > 0.0:
					var frac := clampf(cd / maxf(player.cooldown_max[i], 0.01), 0.0, 1.0)
					draw_rect(Rect2(r.position, Vector2(50, 50 * frac)), Color(0, 0, 0, 0.65))
				if spell.charge_cost > player.signature_charge:
					draw_rect(r, Color(0, 0, 0, 0.5))
			draw_rect(r, Color(0.9, 0.75, 0.4), false, 2.0)
			draw_string(font, r.position + Vector2(0, 62), hints[i], HORIZONTAL_ALIGNMENT_CENTER, 50, 12, Color(0.9, 0.9, 0.9))
		# Signature meter
		var m := Rect2(90, 114, 218, 8)
		draw_rect(m, Color(0, 0, 0, 0.6))
		var full := player.signature_charge >= Player.MAX_CHARGE
		draw_rect(Rect2(m.position, Vector2(m.size.x * player.signature_charge / Player.MAX_CHARGE, m.size.y)),
			Color(1.0, 0.85, 0.3) if full else Color(0.9, 0.45, 0.15))
