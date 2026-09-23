class_name ItemListPanel
extends PanelContainer
## One panel of the inventory / loot screen (reference 4 top bars): a
## dark title bar (player: title · button · space; container: button ·
## title · space), a column header (Name / Type / Qty / kg / Cond) and a
## scrolling list of pooled rows. The player panel also has a tab column
## on its left ([tab_column], filled by the controller).
##
## Rows are pooled and DIFFED: show_entries() rebinds only rows whose
## entry changed since the last call ([last_rebound] counts them), so a
## refresh after one transfer touches a handful of rows even with
## hundreds of stacks. Entries: {"header": "Food"} or {"item":
## ItemInstance, "row": {name, category, count, weight, condition,
## enabled, reason, equipped}, "selected": bool}.
##
## Pure view: emits row_pressed / row_right_clicked / row_hovered; drag
## and drop goes through the Callables the controller sets
## ([drag_data] item -> Variant, [can_drop] data -> bool, [drop] data).

signal row_pressed(item: ItemInstance)
signal row_right_clicked(item: ItemInstance, screen_pos: Vector2)
signal row_hovered(item: ItemInstance, inside: bool)

const ROW_H := 22.0
const HEADER_H := 16.0
const LIST_H := 264.0
const LIST_MIN_H := 70.0
const COL_W_CAT := 44.0
const COL_W_QTY := 32.0
const COL_W_KG := 40.0
const COL_W_COND := 38.0
const COL_PANEL := Color(0.09, 0.09, 0.1, 0.88)
const COL_HEADER := Color(0.015, 0.015, 0.02, 0.97)
const COL_TEXT := Color(0.9, 0.9, 0.87)
const COL_DIM := Color(0.58, 0.58, 0.56)
const COL_EQUIPPED := Color(1.0, 0.84, 0.45)
const COL_ROW_ALT := Color(1, 1, 1, 0.035)
const COL_ROW_HOVER := Color(1, 1, 1, 0.12)
const COL_ROW_SELECTED := Color(1.0, 0.8, 0.35, 0.22)
const FONT := 13

var is_player: bool = false
var list_width: float = 350.0
var title: Label
var weight: Label
var button: Button
var list: VBoxContainer
var scroll: ScrollContainer
var empty_label: Label
## Left tab column (player panel only).
var tab_column: VBoxContainer
## Pooled row Buttons (item rows and header rows mixed, display order).
var pool: Array[Button] = []
## Rows rebound by the last show_entries() (diffing, tests / perf).
var last_rebound: int = 0

var drag_data: Callable
var can_drop: Callable
var drop: Callable

## Row node per key (ItemInstance, or "h:<header>") from the last call.
var _by_key: Dictionary = {}
var _styles: Array[StyleBox] = []


static func flat(c: Color, margin: float = 0.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.content_margin_left = margin
	s.content_margin_right = margin
	s.content_margin_top = margin * 0.5
	s.content_margin_bottom = margin * 0.5
	return s


static func make_label(text: String, col: Color = COL_TEXT, size: int = FONT) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override(&"font_color", col)
	l.add_theme_font_size_override(&"font_size", size)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


static func _cell(text: String, width: float, col: Color) -> Label:
	var l := make_label(text, col)
	l.custom_minimum_size = Vector2(width, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return l


## Build the panel (call once, before adding it to the tree).
func setup(p_is_player: bool, p_name: String, button_text: String, width: float) -> void:
	is_player = p_is_player
	name = p_name
	list_width = width
	_styles = [flat(Color(0, 0, 0, 0)), flat(COL_ROW_ALT), flat(COL_ROW_HOVER), flat(COL_ROW_SELECTED)]
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override(&"panel", flat(COL_PANEL))
	var outer := HBoxContainer.new()
	outer.add_theme_constant_override(&"separation", 0)
	add_child(outer)
	if is_player:
		tab_column = VBoxContainer.new()
		tab_column.name = "Tabs"
		tab_column.add_theme_constant_override(&"separation", 2)
		outer.add_child(tab_column)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(width, 0)
	v.add_theme_constant_override(&"separation", 0)
	outer.add_child(v)
	var bar := PanelContainer.new()
	bar.name = "TitleBar"
	bar.add_theme_stylebox_override(&"panel", flat(COL_HEADER, 8.0))
	v.add_child(bar)
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 10)
	bar.add_child(h)
	title = make_label("", COL_TEXT, 14)
	title.name = "Title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	button = Button.new()
	button.name = button_text.replace(" ", "")
	button.text = button_text
	button.focus_mode = Control.FOCUS_NONE
	button.flat = true
	button.add_theme_font_size_override(&"font_size", 13)
	button.add_theme_color_override(&"font_color", COL_TEXT)
	button.add_theme_color_override(&"font_hover_color", Color(1, 0.85, 0.45))
	button.add_theme_color_override(&"font_disabled_color", Color(0.45, 0.45, 0.45))
	weight = make_label("", COL_TEXT, 13)
	weight.name = "Weight"
	weight.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	weight.custom_minimum_size = Vector2(112, 0)
	weight.tooltip_text = "Space used in this container / its capacity"
	weight.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(make_label("◆", COL_DIM, 11))
	if is_player:
		h.add_child(title)
		h.add_child(button)
	else:
		h.add_child(button)
		h.add_child(title)
	h.add_child(weight)
	var colbar := MarginContainer.new()
	colbar.add_theme_constant_override(&"margin_left", 6)
	colbar.add_theme_constant_override(&"margin_right", 6)
	colbar.add_theme_constant_override(&"margin_top", 2)
	v.add_child(colbar)
	var ch := HBoxContainer.new()
	ch.add_theme_constant_override(&"separation", 6)
	colbar.add_child(ch)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(16, 0)
	ch.add_child(sp)
	var n := make_label("Name", COL_DIM, 11)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ch.add_child(n)
	var type_h := _cell("Type", COL_W_CAT, COL_DIM)
	type_h.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	ch.add_child(type_h)
	ch.add_child(_cell("Qty", COL_W_QTY, COL_DIM))
	ch.add_child(_cell("kg", COL_W_KG, COL_DIM))
	ch.add_child(_cell("Cond", COL_W_COND, COL_DIM))
	for l in ch.get_children():
		if l is Label:
			l.add_theme_font_size_override(&"font_size", 11)
	scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, LIST_H)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	list = VBoxContainer.new()
	list.name = "List"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override(&"separation", 0)
	scroll.add_child(list)
	empty_label = make_label("(empty)", COL_DIM)
	empty_label.name = "Empty"
	empty_label.custom_minimum_size = Vector2(0, ROW_H)
	empty_label.visible = false
	list.add_child(empty_label)
	# Drops anywhere on the panel / list, not only on rows.
	for ctl: Control in [self, scroll, list]:
		ctl.set_drag_forwarding(func(_p): return null, _can_drop_at, _drop_at)


## Show [entries] (see class doc). Keyed reconciliation: every item /
## header keeps its row node between calls; a row is rebound only when its
## content changed, re-striped only when its parity changed, and moved
## only when its position changed (a removed row goes to the end first,
## so the rows after it do not all move). Returns the content height.
func show_entries(entries: Array) -> float:
	last_rebound = 0
	empty_label.visible = entries.is_empty()
	var new_map := {}
	var order: Array[Button] = []
	var height := 0.0
	# 1) Match entries to existing nodes.
	for e: Dictionary in entries:
		var k: Variant = e.item if e.has("item") else "h:" + String(e.header)
		var b: Button = _by_key.get(k)
		if b != null and not new_map.has(k):
			new_map[k] = b
		else:
			new_map[k] = null
		order.append(new_map[k])
	# 2) Release rows whose key vanished; move them to the end.
	var used := {}
	for b in order:
		if b != null:
			used[b] = true
	var free: Array[Button] = []
	for b in pool:
		if used.has(b):
			continue
		if b.visible:
			_release(b)
		free.append(b)
	for b in free:
		list.move_child(b, list.get_child_count() - 1)
	# 3) Fill gaps with free / new nodes, bind, order.
	for i in entries.size():
		var e: Dictionary = entries[i]
		var k: Variant = e.item if e.has("item") else "h:" + String(e.header)
		var b := order[i]
		if b == null:
			if not free.is_empty():
				b = free.pop_front()
			else:
				b = _make_row(pool.size())
				list.add_child(b)
				pool.append(b)
			new_map[k] = b
			b.set_meta(&"content", null)
		if list.get_child(i + 1) != b:
			list.move_child(b, i + 1)
		if e.has("header"):
			height += HEADER_H
			if _meta(b, &"content") != ["h", e.header]:
				b.set_meta(&"content", ["h", e.header])
				_bind_header(b, String(e.header))
				last_rebound += 1
		else:
			height += ROW_H
			var sel := bool(e.get("selected", false))
			var content := [e.item, e.row, sel]
			if not b.visible or _meta(b, &"content") != content:
				b.set_meta(&"content", content)
				_bind_row(b, e.row, e.item)
				b.set_meta(&"stripe", -1)
				last_rebound += 1
			# No zebra striping: a removal would re-style every row below it.
			var stripe := 3 if sel else 0
			if int(b.get_meta(&"stripe", -1)) != stripe:
				b.set_meta(&"stripe", stripe)
				b.add_theme_stylebox_override(&"normal", _styles[stripe])
	_by_key = new_map
	return clampf(height + 4.0, LIST_MIN_H, LIST_H)


static func _meta(b: Object, k: StringName) -> Variant:
	return b.get_meta(k) if b.has_meta(k) else null


func _release(b: Button) -> void:
	b.visible = false
	if b.has_meta(&"item"):
		b.remove_meta(&"item")
	b.set_meta(&"content", null)


func clear_rows() -> void:
	show_entries([])
	empty_label.visible = false


## The ItemInstance a pooled row shows (null: header / hidden). Note:
## set_meta(k, null) removes a key and get_meta(k, null) then errors.
static func row_item(b: Button) -> ItemInstance:
	return b.get_meta(&"item") as ItemInstance if b.has_meta(&"item") else null


## Visible rows in display order (headers included).
func _shown() -> Array[Button]:
	var out: Array[Button] = []
	for ch in list.get_children():
		if ch is Button and ch.visible:
			out.append(ch)
	return out


## Number of visible item rows (headers excluded).
func visible_row_count() -> int:
	var n := 0
	for b in _shown():
		if row_item(b) != null:
			n += 1
	return n


## Visible header rows.
func header_count() -> int:
	var n := 0
	for b in _shown():
		if row_item(b) == null:
			n += 1
	return n


## The row showing item row [i] (display order, headers skipped).
func row_node(i: int) -> Button:
	var k := 0
	for b in _shown():
		if row_item(b) != null:
			if k == i:
				return b
			k += 1
	return null


func row_for(item: ItemInstance) -> Button:
	var b: Button = _by_key.get(item)
	return b if b != null and b.visible else null


# --- Rows ------------------------------------------------------------------------

func _make_row(index: int) -> Button:
	var b := Button.new()
	b.name = "Row%d" % index
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, ROW_H)
	b.add_theme_stylebox_override(&"hover", _styles[2])
	b.add_theme_stylebox_override(&"pressed", _styles[2])
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 6
	h.offset_right = -6
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override(&"separation", 6)
	b.add_child(h)
	var icon_holder := CenterContainer.new()
	icon_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(icon_holder)
	var border := ColorRect.new()
	border.custom_minimum_size = Vector2(16, 16)
	border.color = Color(0, 0, 0, 0.8)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_holder.add_child(border)
	var icon := ColorRect.new()
	icon.name = "Icon"
	icon.position = Vector2(2, 2)
	icon.size = Vector2(12, 12)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	border.add_child(icon)
	var nm := make_label("", COL_TEXT)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.clip_text = true
	h.add_child(nm)
	var cells := [nm, _cell("", COL_W_CAT, COL_TEXT), _cell("", COL_W_QTY, COL_TEXT), _cell("", COL_W_KG, COL_TEXT), _cell("", COL_W_COND, COL_TEXT)]
	cells[1].horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	for i in range(1, cells.size()):
		h.add_child(cells[i])
	b.set_meta(&"icon", icon)
	b.set_meta(&"icon_border", border)
	b.set_meta(&"cells", cells)
	b.pressed.connect(func():
		var it := row_item(b)
		if it != null:
			row_pressed.emit(it))
	b.gui_input.connect(_on_row_gui_input.bind(b))
	b.mouse_entered.connect(func(): row_hovered.emit(row_item(b), true))
	b.mouse_exited.connect(func(): row_hovered.emit(row_item(b), false))
	b.set_drag_forwarding(_row_drag.bind(b), _can_drop_at, _drop_at)
	return b


func _bind_header(b: Button, text: String) -> void:
	b.visible = true
	if b.has_meta(&"item"):
		b.remove_meta(&"item")
	b.disabled = true
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.custom_minimum_size = Vector2(0, HEADER_H)
	b.modulate = Color.WHITE
	b.tooltip_text = ""
	b.add_theme_stylebox_override(&"normal", _styles[0])
	b.add_theme_stylebox_override(&"disabled", _styles[0])
	b.set_meta(&"stripe", 0)
	(b.get_meta(&"icon_border") as Control).visible = false
	var cells: Array = b.get_meta(&"cells")
	for i in cells.size():
		cells[i].text = text.to_upper() if i == 0 else ""
		cells[i].add_theme_color_override(&"font_color", COL_DIM)
		cells[i].add_theme_font_size_override(&"font_size", 10)


func _bind_row(b: Button, d: Dictionary, item: ItemInstance) -> void:
	b.visible = true
	b.disabled = false
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.custom_minimum_size = Vector2(0, ROW_H)
	b.set_meta(&"item", item)
	var equipped := bool(d.get("equipped", false))
	var tip := String(d.reason) if not bool(d.enabled) else (item.data.description if item.data else "")
	if equipped:
		tip = "Equipped (%s). %s" % [String(d.category), String(d.get("tip", tip))]
	b.tooltip_text = tip
	(b.get_meta(&"icon_border") as Control).visible = true
	(b.get_meta(&"icon") as ColorRect).color = item.data.color if item.data else Color.GRAY
	var col := COL_EQUIPPED if equipped else (COL_TEXT if bool(d.enabled) else COL_DIM)
	var cells: Array = b.get_meta(&"cells")
	var texts := [String(d.name), String(d.category), String(d.count), String(d.weight), String(d.condition)]
	for i in cells.size():
		cells[i].text = texts[i]
		cells[i].add_theme_font_size_override(&"font_size", FONT)
		cells[i].add_theme_color_override(&"font_color", col if i != 1 else (COL_EQUIPPED if equipped else COL_DIM))
	# Round 7: spoiled food stands out in the condition column.
	if texts[4] == "Rotten":
		cells[4].add_theme_color_override(&"font_color", Color(0.95, 0.35, 0.3))
	elif texts[4] == "Stale":
		cells[4].add_theme_color_override(&"font_color", Color(0.9, 0.75, 0.35))
	b.modulate = Color(1, 1, 1, 1.0 if bool(d.enabled) else 0.55)


func _on_row_gui_input(event: InputEvent, b: Button) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_RIGHT:
		return
	var item := row_item(b)
	if item == null:
		return
	b.accept_event()
	row_right_clicked.emit(item, b.get_screen_position() + mb.position)


# --- Drag and drop (forwarded to the controller's Callables) ------------------------

func _row_drag(_at: Vector2, b: Button) -> Variant:
	var item := row_item(b)
	if item == null or not drag_data.is_valid():
		return null
	var data: Variant = drag_data.call(item)
	if data == null:
		return null
	var bg := PanelContainer.new()
	bg.add_theme_stylebox_override(&"panel", flat(Color(0.1, 0.1, 0.12, 0.9), 6.0))
	bg.add_child(make_label("  %s%s" % [item.display_name(), (" ×%d" % item.stack) if item.stack > 1 else ""], COL_TEXT, 13))
	b.set_drag_preview(bg)
	return data


func _can_drop_at(_at: Vector2, data: Variant) -> bool:
	return can_drop.is_valid() and bool(can_drop.call(data))


func _drop_at(_at: Vector2, data: Variant) -> void:
	if drop.is_valid():
		drop.call(data)
