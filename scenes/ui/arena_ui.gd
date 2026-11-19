class_name ArenaUi extends RefCounted

const THEME := preload("res://assets/ui/arena_theme.tres")
const BODY := preload("res://assets/ui/pixelify_ui.tres")
const DISPLAY := BODY
const BACKDROP := preload("res://assets/ui/arena-diorama.png")
const LOGO := preload("res://assets/ui/chita-mark.png")
const ABILITIES := preload("res://assets/ui/ability-icons.png")
const EQUIPMENT := preload("res://assets/ui/equipment-icons.png")
const PORTRAITS := preload("res://assets/ui/fighter-sprites.png")
const CROWN := preload("res://assets/ui/crown.png")
const SWORDS := preload("res://assets/ui/crossed-swords.png")
const GOLD := Color("#e2b668")
const INK := Color("#e7e7cd")
const MUTED := Color("#acbcb7")
const SHADE := Color("#182127")
const SLATE := Color("#263742")
const EDGE := Color("#546771")
const MOSS := Color("#c5df77")
const DANGER := Color("#d86e51")
const NIGHT := Color("#10191f")

# Atlas order matches the numbered isometric character folders.
const PORTRAIT_CELLS := {
	"1Knight": 0, "2Archer": 1, "3Wizard": 2, "4Paladin": 3, "5CamoArcher": 4,
	"6Mage": 5, "7DeathKnight": 6, "8DarkLord": 7, "9Longbow": 8,
}
const SKILL_COLUMNS := 5
const SKILL_COLUMNS_BY_HERO := {"knight": 0, "rogue": 1, "wizard": 2, "ranger": 3, "bonker": 4}

static var _skills: Dictionary[int, Texture2D] = {}

static func backdrop(root: Control, veil := 0.0) -> void:
	root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var background := ColorRect.new()
	background.color = NIGHT
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)
	var art := picture(BACKDROP, Vector2.ZERO)
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	art.offset_left = -640
	art.offset_top = -360
	art.offset_right = 640
	art.offset_bottom = 360
	root.add_child(art)
	if veil > 0.0:
		scrim(root, veil)

static func scrim(root: Control, opacity: float) -> void:
	var shade := ColorRect.new()
	shade.color = Color(NIGHT, opacity)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(shade)

static func picture(texture: Texture2D, extent: Vector2) -> TextureRect:
	var art := TextureRect.new()
	art.texture = texture
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.custom_minimum_size = extent
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return art

static func heading(text: String, px: int) -> Label:
	var node := label(text, px)
	node.theme_type_variation = &"DisplayLabel"
	return node

static func label(text: String, px: int = 20, shade := INK) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", px)
	node.add_theme_color_override("font_color", shade)
	return node

static func button(text: String, action: Callable, primary := false) -> Button:
	var node := Button.new()
	node.text = text
	node.custom_minimum_size.y = 42
	if primary:
		node.theme_type_variation = &"PrimaryButton"
	if action.is_valid():
		node.pressed.connect(action)
	return node

static func panel(canvas: CanvasItem, box: Rect2) -> void:
	canvas.draw_style_box(THEME.get_stylebox("panel", "Panel"), box)

static func defer_focus(target: Control) -> void:
	var select := func() -> void:
		if is_instance_valid(target) and target.is_inside_tree() and target.is_visible_in_tree():
			if not target is BaseButton or not target.disabled:
				target.grab_focus()
	select.call_deferred()

static func focusable(node: Control) -> Array[Control]:
	var items: Array[Control] = []
	for child in node.get_children():
		if child is Control and child.visible:
			if child.focus_mode == Control.FOCUS_ALL and (not child is BaseButton or not child.disabled):
				items.append(child)
			items.append_array(focusable(child))
	return items

static func portrait(hero: Hero, color: String) -> Texture2D:
	var variant := maxi(Hero.COLOR_ORDER.find(color), 0) % hero.units.size()
	return _atlas_cell(PORTRAITS, PORTRAIT_CELLS.get(hero.units[variant], 0), 3)

static func skill_icon(hero: Hero, slot: int) -> Texture2D:
	var column: int = SKILL_COLUMNS_BY_HERO.get(hero.id, 0)
	var cell := column + slot * SKILL_COLUMNS
	if not _skills.has(cell):
		_skills[cell] = _atlas_cell(ABILITIES, cell, SKILL_COLUMNS)
	return _skills[cell]

static func gear_icon(slot: String) -> Texture2D:
	var cell: int = {"weapon": 1, "armor": 2, "trinket": 3}[slot]
	return _atlas_cell(EQUIPMENT, cell, 2)

static func _atlas_cell(texture: Texture2D, cell: int, columns: int) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	@warning_ignore("integer_division")
	var side := texture.get_width() / columns
	@warning_ignore("integer_division")
	atlas.region = Rect2((cell % columns) * side, (cell / columns) * side, side, side)
	atlas.filter_clip = true
	return atlas
