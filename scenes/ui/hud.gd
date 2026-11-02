class_name Hud extends CanvasLayer
## Creates one HeroPanel per player (HP, gear, dash pips, the two skill slots) and the boss bar.

const BAR_TEX := preload("res://assets/tiny_swords/ui/BigBar_Base.png")
const FILL_TEX := preload("res://assets/tiny_swords/ui/BigBar_Fill.png")
const HINTS := [["LMB", "RMB"], ["RT", "B"]]

var with_sheet := true   ## the Tab character sheet pauses the tree, so online matches turn it off
var online := false      ## one local player: always the P1 hints, bottom-left

func add_player(p: Player) -> void:
	var panel := HeroPanel.new()
	panel.player = p
	panel.size = Vector2(340, 140)
	panel.mirror = p.player_index == 1 and not online
	add_child(panel)

var _boss_bar := BossBar.new()

func _ready() -> void:
	_boss_bar.size = Vector2(640, 48)
	add_child(_boss_bar)
	if with_sheet:
		add_child(CharacterSheet.new())

func _process(_delta: float) -> void:
	var vp := get_viewport().get_visible_rect().size
	_boss_bar.position = Vector2((vp.x - _boss_bar.size.x) / 2.0, 24)

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
