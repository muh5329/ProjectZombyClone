class_name MenuStyle
extends RefCounted
## Shared look for the Round-10 menus (pause menu, main menu): dark
## translucent panel, large buttons, a slot list. Built in code.

const PANEL_BG := Color(0.07, 0.08, 0.09, 0.92)
const TITLE := Color(0.92, 0.86, 0.72)
const MUTED := Color(0.7, 0.72, 0.74)


static func panel(min_size: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = Color(0.45, 0.38, 0.28)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 18
	sb.content_margin_bottom = 18
	p.add_theme_stylebox_override(&"panel", sb)
	p.custom_minimum_size = min_size
	return p


static func title(text: String, size: int = 30) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", TITLE)
	return l


static func label(text: String, size: int = 14, color: Color = MUTED) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", color)
	return l


static func button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(240, 38)
	b.add_theme_font_size_override(&"font_size", 18)
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(cb)
	return b


## "quick — Day 2, 21:40 · Health 83%  (2026-09-23 03:30)" for a
## SaveFile.list_slots() entry; every meta field is type-checked (a
## tampered meta.json shows "?" instead of crashing the menu).
static func slot_text(entry: Variant) -> String:
	var e: Dictionary = entry if entry is Dictionary else {}
	var m: Variant = e.get("meta", {})
	var p := SaveFile.meta_dict(m, "player")
	var hp := ""
	if p.has("health"):
		hp = " · Health %d%%" % int(round(100.0 * SaveFile.meta_num(p, "health") / maxf(SaveFile.meta_num(p, "health_max", 100.0), 1.0)))
	var when := SaveFile.meta_str(m, "datetime")
	var slot: Variant = e.get("slot", "?")
	return "%s — Day %d, %s%s%s" % [str(slot).left(48), int(clampf(SaveFile.meta_num(m, "day", 1.0), 0.0, 100000.0)),
		SaveFile.meta_str(m, "clock", "--:--"), hp, ("  (%s)" % when) if when != "" else ""]
