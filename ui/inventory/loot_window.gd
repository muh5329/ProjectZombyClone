class_name LootWindow
extends CanvasLayer
## Inventory screen + loot window controller (Project Zomboid reference 4
## layout): two ItemListPanels along the top of the screen.
##
## Left, the PLAYER panel: a column of container tabs (Inventory, the worn
## bag) + the "Carrying X / 8 kg" load readout, and the active tab's list
## (Inventory tab: equipped items first, then stacks grouped under
## category headers). The header shows the tab's storage as "Space W /
## Cap kg" — a different number from the load. The active tab is the
## TARGET of everything taken from the container.
## Right, the open CONTAINER (LootContainer or a bag on the ground).
##
## - Opens on EventBus.container_opened for the player, closes on
##   container_closed (walk away, E / Esc, Tab). Tab alone toggles the
##   inventory screen. Emits EventBus.inventory_screen_toggled.
## - Row click: container open → move the stack (Shift: one), else select;
##   Ctrl+click: split half in place; right-click: ItemContextMenu
##   (ItemActions / Take); G drops the hovered (else selected) player row;
##   drag and drop via InventoryDragDrop.
## - Pure presentation: moves go through the container node's
##   take/put/take_all/put_all and the Player verbs. Refreshes are
##   deferred + coalesced and the panels only rebind rows that changed.
## Test API: transfer_index/transfer_item/loot_all/transfer_all/rows/
## row_enabled/row_node/row_for/visible_row_count/select_tab/player_tabs/
## drag_payload/can_drop_payload/drop_payload/context_actions/
## perform_context/click_row/drop_selected/panel().

const SIDE_PLAYER := &"player"
const SIDE_CONTAINER := &"container"
const TARGET_PLAYER := &"player"
const TARGET_CONTAINER := &"container"
const DRAG_KIND := InventoryDragDrop.KIND
const PANEL_W := 350.0
const TAB_W := 74.0
const TAB_H := 54.0
const LEFT := 150.0
const TOP := 6.0
const COL_TEXT := ItemListPanel.COL_TEXT
const COL_DIM := ItemListPanel.COL_DIM
const COL_WARN := Color(1.0, 0.62, 0.3)
const COL_EQUIPPED := ItemListPanel.COL_EQUIPPED
const COL_TAB := Color(0.14, 0.14, 0.16, 0.95)
const COL_TAB_ACTIVE := Color(0.32, 0.27, 0.16, 0.98)
## Load readout colours by encumbrance state (HUD uses the same).
const LOAD_COLORS := {&"ok": Color(0.85, 0.9, 0.85), &"light": Color(0.95, 0.88, 0.45), &"heavy": Color(1.0, 0.6, 0.2), &"overloaded": Color(1.0, 0.25, 0.2)}
## Short category labels (ItemData.Category order) for the "Type" column.
const CATEGORY_SHORT: Array[String] = ["Food", "Drink", "Med", "Weapon", "Tool", "Mat", "Cloth", "Bag", "Misc"]
## Category group headers (ItemData.Category order).
const CATEGORY_TITLES: Array[String] = ["Food", "Drink", "Medical", "Weapons", "Tools", "Materials", "Clothing", "Containers", "Misc"]
const SLOT_SHORT := {&"primary_hand": "Hands", &"secondary_hand": "Hand 2", &"back": "Back"}

## The player (GameManager.player when unset).
var player: Node
## The container open for the player (LootContainer / bag WorldItem; null = none).
var container: Node
## Player panel opened with Tab (stays after the container closes).
var inventory_pinned: bool = false
## Index into player_tabs() of the active player container.
var active_tab: int = 0
## Last clicked player row (G / Drop target when nothing is hovered).
var selected: ItemInstance = null
## Row under the mouse (ItemInstance) and its side.
var hovered: ItemInstance = null
var hovered_side: StringName = &""

var root: VBoxContainer
var player_panel: ItemListPanel
var container_panel: ItemListPanel
var tab_buttons: Array[Button] = []
## "Carrying X / 8 kg" under the tabs (the load, not the space).
var load_label: Label
var footer: Label
var status_label: Label
var context_menu: ItemContextMenu
var drag_drop: InventoryDragDrop

var player_title: Label:
	get: return player_panel.title
var player_weight: Label:
	get: return player_panel.weight
var container_title: Label:
	get: return container_panel.title
var container_weight: Label:
	get: return container_panel.weight
var transfer_all_button: Button:
	get: return player_panel.button
var loot_all_button: Button:
	get: return container_panel.button
var player_list: VBoxContainer:
	get: return player_panel.list
var container_list: VBoxContainer:
	get: return container_panel.list
var player_scroll: ScrollContainer:
	get: return player_panel.scroll
var container_scroll: ScrollContainer:
	get: return container_panel.scroll

var _status_time: float = 0.0
var _refresh_queued: bool = false
var _tab_styles: Array[StyleBox] = []
var _screen_visible: bool = false


func _ready() -> void:
	drag_drop = InventoryDragDrop.new(self)
	_build()
	EventBus.container_opened.connect(_on_container_opened)
	EventBus.container_closed.connect(_on_container_closed)
	EventBus.inventory_changed.connect(_on_inventory_changed)
	EventBus.interaction_refused.connect(_on_refused)
	EventBus.item_transferred.connect(_on_item_transferred)
	EventBus.item_dropped.connect(_on_item_dropped)
	EventBus.equipment_changed.connect(_on_equipment_changed)
	EventBus.encumbrance_changed.connect(_on_encumbrance_changed)
	_update_visibility()


func _player() -> Node:
	if player != null and is_instance_valid(player):
		return player
	return GameManager.player


func _player_inventory() -> ItemContainer:
	return LootContainer.inventory_of(_player())


func _equipment() -> Equipment:
	var p := _player()
	return p.get_node_or_null("Equipment") as Equipment if p else null


func panel(side: StringName) -> ItemListPanel:
	return player_panel if side == SIDE_PLAYER else container_panel


func is_open() -> bool:
	return container != null


## True while the inventory screen (player panel) is on screen.
func is_visible_screen() -> bool:
	return root.visible


func player_panel_visible() -> bool:
	return player_panel.visible


func container_panel_visible() -> bool:
	return container_panel.visible


# --- Player containers (tabs) ----------------------------------------------------

## [{id, name, container: ItemContainer, bag: ItemInstance}] — main
## inventory, then the worn bag.
func player_tabs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var inv := _player_inventory()
	if inv == null:
		return out
	out.append({"id": &"inventory", "name": "Inventory", "container": inv, "bag": null})
	var eq := _equipment()
	if eq != null and eq.back_bag() != null:
		var b := eq.back_bag()
		out.append({"id": &"bag", "name": b.display_name(), "container": b.contents, "bag": b})
	return out


## The player container loot goes into (the active tab).
func active_player_container() -> ItemContainer:
	var tabs := player_tabs()
	if tabs.is_empty():
		return null
	return tabs[clampi(active_tab, 0, tabs.size() - 1)].container


## Click a container tab: it becomes the list shown and the loot target.
func select_tab(index: int) -> void:
	active_tab = clampi(index, 0, maxi(player_tabs().size() - 1, 0))
	selected = null
	refresh()


# --- Events ------------------------------------------------------------------

func _on_container_opened(actor: Node, c: Node) -> void:
	if actor == null or actor != _player() or c == null or not c.has_method(&"take"):
		return
	container = c
	_set_status("")
	_update_visibility()
	refresh()


func _on_container_closed(_actor: Node, c: Node) -> void:
	if c != container:
		return
	container = null
	_update_visibility()
	refresh()


func _on_inventory_changed(owner: Node) -> void:
	if owner == _player() or (container != null and owner == container):
		_queue_refresh()


func _on_equipment_changed(c: Node, _slot: StringName, _item: Dictionary) -> void:
	if c == _player():
		active_tab = clampi(active_tab, 0, maxi(player_tabs().size() - 1, 0))
		_queue_refresh()


func _on_encumbrance_changed(c: Node, state: StringName, w: float) -> void:
	if c == _player():
		_show_load(state, w)


func _on_refused(actor: Node, _target: Node, reason: String) -> void:
	if actor == _player() and root.visible:
		_set_status(reason, true)


func _on_item_transferred(from: Node, to: Node, item: Dictionary) -> void:
	if container == null or (from != container and to != container):
		return
	var n := int(item.get("count", 0))
	var nm := String(item.get("name", ""))
	if nm == "":
		_set_status("Moved %d item%s" % [n, "" if n == 1 else "s"])
	else:
		_set_status("%s %s%s" % ["Took" if from == container else "Stored", nm, " ×%d" % n if n > 1 else ""])


func _on_item_dropped(c: Node, item: Dictionary) -> void:
	if c == _player() and root.visible:
		var n := int(item.get("count", 1))
		_set_status("Dropped %s%s" % [String(item.get("name", "item")), " ×%d" % n if n > 1 else ""])


# --- Input ---------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_inventory"):
		toggle_inventory()
		get_viewport().set_input_as_handled()
	elif is_open() and (event.is_action_pressed(&"interact") or event.is_action_pressed(&"ui_cancel")):
		close()
		get_viewport().set_input_as_handled()
	elif root.visible and not is_open() and event.is_action_pressed(&"ui_cancel"):
		toggle_inventory()
		get_viewport().set_input_as_handled()
	elif root.visible and event.is_action_pressed(&"drop_item"):
		drop_selected()
		get_viewport().set_input_as_handled()


## Tab: with a container open, closes everything; otherwise toggles the
## player's inventory screen on its own.
func toggle_inventory() -> void:
	if is_open():
		inventory_pinned = false
		close()
	else:
		inventory_pinned = not inventory_pinned
	if context_menu.visible:
		context_menu.hide()
	_update_visibility()
	refresh()


## Close the open container (and with it the container panel).
func close() -> void:
	if container != null and is_instance_valid(container):
		container.close()
	container = null
	_update_visibility()


# --- Actions (buttons, rows, tests) --------------------------------------------

## Move the stack at [index] of [side] (display order, see rows()).
func transfer_index(side: StringName, index: int, one: bool = false) -> Dictionary:
	if container == null:
		return {"ok": false, "reason": "Nothing open", "moved": 0}
	var list := side_items(side)
	if index < 0 or index >= list.size():
		return {"ok": false, "reason": "Not here", "moved": 0}
	return transfer_item(side, list[index], one)


## Move the stack [item] (shown on [side]) to the other side. Rows bind
## to the ItemInstance, never to a list index.
func transfer_item(side: StringName, item: ItemInstance, one: bool = false) -> Dictionary:
	if container == null:
		return {"ok": false, "reason": "Nothing open", "moved": 0}
	var count := 1 if one else -1
	if side == SIDE_PLAYER:
		return container.put(_player(), item, count)
	return container.take(_player(), item, count, active_player_container())


## "Loot All" (container → active player tab), one transaction.
func loot_all() -> Dictionary:
	if container == null:
		return {"ok": false, "reason": "Nothing open", "moved": 0}
	return container.take_all(_player(), active_player_container())


## "Transfer All" (active player tab → container; equipped items stay).
func transfer_all() -> Dictionary:
	if container == null:
		return {"ok": false, "reason": "Nothing open", "moved": 0}
	return container.put_all(_player(), active_player_container())


## A row click as the mouse does it: Ctrl splits, with a container open
## it transfers (Shift: one), otherwise it selects.
func click_row(side: StringName, item: ItemInstance, shift: bool = false, ctrl: bool = false) -> Dictionary:
	if item == null:
		return {"ok": false, "reason": "Nothing there"}
	if ctrl:
		return split_row(side, item)
	if container == null:
		selected = item if side == SIDE_PLAYER else null
		_queue_refresh()
		return {"ok": true, "selected": true}
	return transfer_item(side, item, shift)


## Ctrl+click: half of the stack becomes a new stack in the same container.
func split_row(side: StringName, item: ItemInstance) -> Dictionary:
	if item == null or item.stack < 2:
		_set_status("Can't split one item", true)
		return {"ok": false, "reason": "Can't split one item"}
	if side == SIDE_PLAYER:
		var p := _player()
		return p.call(&"split_item", item) if p and p.has_method(&"split_item") else {"ok": false}
	var inv: ItemContainer = container.inventory if container else null
	if inv == null or not inv.has(item):
		return {"ok": false, "reason": "Not here"}
	var out := inv.split_stack(item, item.stack / 2)
	return {"ok": out != null, "item": out}


## G: drop the hovered player row, else the selected one.
func drop_selected() -> Dictionary:
	var it := hovered if hovered != null and hovered_side == SIDE_PLAYER else selected
	var p := _player()
	if it == null or p == null or not p.has_method(&"drop_item") or not bool(p.call(&"carries", it)):
		_set_status("Select an item to drop", true)
		return {"ok": false, "reason": "Nothing selected"}
	var r: Dictionary = p.call(&"drop_item", it, -1)
	if r.get("ok", false) and selected == it:
		selected = null
	return r


## Items of [side] in display order (player: equipped first, then the
## active container's stacks grouped by category; container: as stored).
func side_items(side: StringName) -> Array[ItemInstance]:
	var out: Array[ItemInstance] = []
	if side == SIDE_CONTAINER:
		var inv: ItemContainer = container.inventory if container != null else null
		if inv != null:
			out.append_array(inv.items)
		return out
	var c := active_player_container()
	if c == null:
		return out
	var eq := _equipment()
	if eq != null and active_tab == 0:
		out.append_array(eq.equipped_items())
	# Stable bucket sort by category (no per-compare lambda: cheap for 400 rows).
	var buckets: Array = []
	buckets.resize(CATEGORY_TITLES.size() + 1)
	for i in buckets.size():
		buckets[i] = []
	for it in c.items:
		var cat := it.data.category if it.data and it.data.category >= 0 and it.data.category < CATEGORY_TITLES.size() else CATEGORY_TITLES.size()
		(buckets[cat] as Array).append(it)
	for b in buckets:
		out.append_array(b)
	return out


## Row data of [side] in display order: [{name, category, count, weight,
## condition, id, enabled, reason, equipped}].
func rows(side: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var eq := _equipment()
	var target: ItemContainer = null
	if container != null:
		target = active_player_container() if side == SIDE_CONTAINER else container.inventory
	# move_block_reason cached per (item kind, unit weight) for this pass.
	var reasons := {}
	for it in side_items(side):
		var r := row_texts(it)
		r["id"] = it.id()
		var slot := eq.slot_of(it) if eq != null and side == SIDE_PLAYER else &""
		r["equipped"] = slot != &""
		if slot != &"":
			r["category"] = "Both" if slot == Equipment.PRIMARY and it.is_two_handed() else SLOT_SHORT.get(slot, "Worn")
			if slot == Equipment.BACK:
				var eff := Encumbrance.worn_bag_weight(it)
				r["name"] = "%s %.1f→%.2f" % [it.display_name(), it.total_weight(), eff]
				r["weight"] = "%.2f" % eff
				r["tip"] = "Worn: weighs %.2f kg, counts %.2f kg toward your load" % [it.total_weight(), eff]
		var why := ""
		if target != null:
			var key: Variant = it.data if it.contents == null else it
			if reasons.has(key):
				why = reasons[key]
			else:
				why = move_block_reason(it, target)
				reasons[key] = why
		r["enabled"] = why == ""
		r["reason"] = why
		out.append(r)
	return out


func row_enabled(side: StringName, index: int) -> bool:
	var r := rows(side)
	return index >= 0 and index < r.size() and bool(r[index].enabled)


## Number of visible item rows on [side] (headers excluded).
func visible_row_count(side: StringName) -> int:
	return panel(side).visible_row_count()


## The pooled row node showing item [i] (display order) of [side].
func row_node(side: StringName, i: int) -> Button:
	return panel(side).row_node(i)


func row_for(side: StringName, item: ItemInstance) -> Button:
	return panel(side).row_for(item)


# --- Drag and drop ----------------------------------------------------------------

func drag_payload(side: StringName, item: ItemInstance) -> Dictionary:
	return drag_drop.payload(side, item)


func can_drop_payload(target: StringName, data: Variant) -> bool:
	return drag_drop.can_drop(target, data)


func drop_payload(target: StringName, data: Variant) -> Dictionary:
	return drag_drop.drop(target, data)


# --- Context menu ------------------------------------------------------------------

## The menu entries for [item] on [side] ({id, label, enabled, reason}).
func context_actions(side: StringName, item: ItemInstance) -> Array[Dictionary]:
	if side == SIDE_CONTAINER:
		var out: Array[Dictionary] = []
		out.append({"id": &"take", "label": "Take", "enabled": true, "reason": ""})
		if item != null and item.stack > 1:
			out.append({"id": &"take_one", "label": "Take one", "enabled": true, "reason": ""})
		return out
	return ItemActions.for_item(_player(), item)


func perform_context(side: StringName, item: ItemInstance, id: StringName) -> Dictionary:
	if side == SIDE_CONTAINER:
		if container == null:
			return {"ok": false, "reason": "Nothing open"}
		return container.take(_player(), item, 1 if id == &"take_one" else -1, active_player_container())
	var r := ItemActions.perform(_player(), item, id)
	_queue_refresh()
	return r


func open_context_menu(side: StringName, item: ItemInstance, screen_pos: Vector2) -> void:
	context_menu.open_for(side, item, context_actions(side, item), screen_pos)


# --- Pure formatting ------------------------------------------------------------

## "0.25 / 18" (+ " kg" when [unit]).
static func format_weight(w: float, cap: float, unit: bool = false) -> String:
	var c := "∞" if cap < 0.0 else (("%d" % int(cap)) if is_equal_approx(cap, roundf(cap)) else ("%.1f" % cap))
	return "%.2f / %s%s" % [w, c, " kg" if unit else ""]


## Storage of a container: "Space 4.70 / 20 kg" (not the carried load).
static func format_space(w: float, cap: float) -> String:
	return "Space " + format_weight(w, cap, true)


## {name, category, count, weight, condition} display strings for one stack.
static func row_texts(it: ItemInstance) -> Dictionary:
	var cond := ""
	if it.data and it.data.has_condition():
		cond = "%d%%" % int(round(it.condition_fraction() * 100.0))
	return {
		"name": it.display_name(),
		"category": category_short(it.data),
		"count": ("×%d" % it.stack) if it.stack > 1 else "",
		"weight": "%.2f" % it.total_weight(),
		"condition": cond,
	}


static func category_short(d: ItemData) -> String:
	if d == null or d.category < 0 or d.category >= CATEGORY_SHORT.size():
		return ""
	return CATEGORY_SHORT[d.category]


## Why one item of [it] cannot move into [to] ("" when it can).
static func move_block_reason(it: ItemInstance, to: ItemContainer) -> String:
	if to == null:
		return "Nowhere to put it"
	if to.equipment_slot != &"":
		return "Use Equip"
	var nest := to.accept_reason(it)
	if nest != "":
		return nest
	if to.fit_count(it.data, 1, it.unit_weight()) < 1:
		return ItemContainer.REASON_HEAVY
	return ""


# --- View ------------------------------------------------------------------------

func _queue_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	call_deferred(&"refresh")


## Rebuild tabs, headers and lists from the models (rows are diffed).
func refresh() -> void:
	_refresh_queued = false
	var tabs := player_tabs()
	active_tab = clampi(active_tab, 0, maxi(tabs.size() - 1, 0))
	_refresh_tabs(tabs)
	var pc := active_player_container()
	player_panel.title.text = String(tabs[active_tab].name) if not tabs.is_empty() else "Inventory"
	player_panel.weight.text = format_space(pc.total_weight(), pc.capacity) if pc else ""
	player_panel.button.disabled = container == null or pc == null or pc.is_empty()
	# Hidden screen: skip the row work (refreshed again when shown).
	var h := player_panel.show_entries(_entries(SIDE_PLAYER)) if root.visible else ItemListPanel.LIST_MIN_H
	if container != null:
		var inv: ItemContainer = container.inventory
		container_panel.title.text = String(container.display_name)
		container_panel.weight.text = format_space(inv.total_weight(), inv.capacity) if inv else ""
		container_panel.button.disabled = inv == null or inv.is_empty()
		h = maxf(h, container_panel.show_entries(_entries(SIDE_CONTAINER)))
	else:
		container_panel.clear_rows()
	player_panel.scroll.custom_minimum_size.y = h
	container_panel.scroll.custom_minimum_size.y = h
	var enc := _player().get_node_or_null("Encumbrance") as Encumbrance if _player() else null
	if enc:
		_show_load(enc.state, enc.weight)


## Panel entries (header / item rows) for [side].
func _entries(side: StringName) -> Array:
	var data := rows(side)
	var items := side_items(side)
	var out: Array = []
	var last_cat := -2
	for i in data.size():
		if side == SIDE_PLAYER:
			var cat := -1 if bool(data[i].equipped) else (items[i].data.category if items[i].data else -1)
			if cat != last_cat:
				out.append({"header": "Equipped" if cat < 0 else CATEGORY_TITLES[cat]})
				last_cat = cat
		out.append({"item": items[i], "row": data[i], "selected": side == SIDE_PLAYER and items[i] == selected})
	return out


func _show_load(state: StringName, w: float) -> void:
	var enc := _player().get_node_or_null("Encumbrance") as Encumbrance if _player() else null
	var cap := enc.capacity() if enc else 8.0
	load_label.text = "Carrying\n%.1f / %s kg" % [w, ("%d" % int(cap)) if is_equal_approx(cap, roundf(cap)) else ("%.1f" % cap)]
	load_label.add_theme_color_override(&"font_color", LOAD_COLORS.get(state, COL_TEXT))
	load_label.tooltip_text = "Load: everything you carry (worn bags count less). %s" % Encumbrance.state_label(state)


func _refresh_tabs(tabs: Array[Dictionary]) -> void:
	while tab_buttons.size() < tabs.size():
		tab_buttons.append(_make_tab(tab_buttons.size()))
	for i in tab_buttons.size():
		var b := tab_buttons[i]
		b.visible = i < tabs.size()
		if not b.visible:
			continue
		var t: Dictionary = tabs[i]
		var c: ItemContainer = t.container
		(b.get_meta(&"label") as Label).text = String(t.name)
		var icon: ColorRect = b.get_meta(&"icon")
		icon.color = (t.bag as ItemInstance).data.color if t.bag != null else Color(0.75, 0.62, 0.42)
		var tip := "%s — %s" % [t.name, format_space(c.total_weight(), c.capacity)]
		if t.bag != null and (t.bag as ItemInstance).data is ContainerItemData:
			var red := ((t.bag as ItemInstance).data as ContainerItemData).weight_reduction
			tip += "\nWorn: contents count %d %%" % int(round((1.0 - red) * 100.0))
		tip += "\nClick: show / loot into this container. Drop items here to move them."
		b.tooltip_text = tip
		b.add_theme_stylebox_override(&"normal", _tab_styles[1 if i == active_tab else 0])
		b.add_theme_stylebox_override(&"hover", _tab_styles[1 if i == active_tab else 2])


func _update_visibility() -> void:
	container_panel.visible = container != null
	player_panel.visible = container != null or inventory_pinned
	root.visible = player_panel.visible
	if not root.visible:
		hovered = null
		if context_menu and context_menu.visible:
			context_menu.hide()
	if root.visible != _screen_visible:
		_screen_visible = root.visible
		EventBus.inventory_screen_toggled.emit(_screen_visible)
	footer.text = "Click: move  ·  Shift: one  ·  Ctrl: split  ·  Drag: move  ·  Right-click: menu  ·  E / Esc close" \
			if container != null else "Click: select · Ctrl: split · Right-click: menu · G: drop · Drag: move · Tab: close"


func _set_status(text: String, warn: bool = false) -> void:
	status_label.text = text
	status_label.add_theme_color_override(&"font_color", COL_WARN if warn else COL_TEXT)
	_status_time = 2.0 if text != "" else 0.0


func _process(delta: float) -> void:
	if _status_time > 0.0:
		_status_time = maxf(_status_time - delta, 0.0)
		if _status_time == 0.0:
			status_label.text = ""


# --- Construction ------------------------------------------------------------------

func _build() -> void:
	var active := ItemListPanel.flat(COL_TAB_ACTIVE)
	active.border_width_left = 3
	active.border_color = COL_EQUIPPED
	_tab_styles = [ItemListPanel.flat(COL_TAB), active, ItemListPanel.flat(COL_TAB.lightened(0.12))]
	root = VBoxContainer.new()
	root.name = "Root"
	root.position = Vector2(LEFT, TOP)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_theme_constant_override(&"separation", 2)
	add_child(root)
	var hb := HBoxContainer.new()
	hb.name = "Panels"
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_theme_constant_override(&"separation", 6)
	root.add_child(hb)
	player_panel = _make_panel(true)
	hb.add_child(player_panel)
	container_panel = _make_panel(false)
	hb.add_child(container_panel)
	player_panel.tab_column.custom_minimum_size = Vector2(TAB_W, 0)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player_panel.tab_column.add_child(spacer)
	load_label = ItemListPanel.make_label("", COL_TEXT, 11)
	load_label.name = "Load"
	load_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	load_label.mouse_filter = Control.MOUSE_FILTER_PASS
	player_panel.tab_column.add_child(load_label)
	var foot := PanelContainer.new()
	foot.name = "Footer"
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_theme_stylebox_override(&"panel", ItemListPanel.flat(Color(0, 0, 0, 0.6), 8.0))
	root.add_child(foot)
	var fh := HBoxContainer.new()
	fh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_child(fh)
	footer = ItemListPanel.make_label("", COL_DIM, 11)
	footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.clip_text = true
	fh.add_child(footer)
	status_label = ItemListPanel.make_label("", COL_TEXT, 12)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fh.add_child(status_label)
	context_menu = ItemContextMenu.new()
	context_menu.action_chosen.connect(func(side, item, id): perform_context(side, item, id))
	add_child(context_menu)


func _make_panel(is_player: bool) -> ItemListPanel:
	var p := ItemListPanel.new()
	var side := SIDE_PLAYER if is_player else SIDE_CONTAINER
	p.setup(is_player, "PlayerPanel" if is_player else "ContainerPanel", "Transfer All" if is_player else "Loot All", PANEL_W)
	p.button.pressed.connect(func(): transfer_all() if is_player else loot_all())
	p.drag_data = func(item: ItemInstance): return drag_payload(side, item)
	p.can_drop = func(data): return can_drop_payload(side, data)
	p.drop = func(data): drop_payload(side, data)
	p.row_pressed.connect(func(item: ItemInstance):
		click_row(side, item, Input.is_key_pressed(KEY_SHIFT), Input.is_key_pressed(KEY_CTRL)))
	p.row_right_clicked.connect(func(item: ItemInstance, at: Vector2):
		if is_player:
			selected = item
		open_context_menu(side, item, at))
	p.row_hovered.connect(func(item: ItemInstance, inside: bool):
		if inside:
			hovered = item
			hovered_side = side
		elif hovered == item:
			hovered = null
			hovered_side = &"")
	return p


func _make_tab(index: int) -> Button:
	var b := Button.new()
	b.name = "Tab%d" % index
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(TAB_W, TAB_H)
	b.add_theme_stylebox_override(&"pressed", _tab_styles[1])
	b.add_theme_stylebox_override(&"hover", _tab_styles[2])
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override(&"separation", 3)
	b.add_child(v)
	var ic_holder := CenterContainer.new()
	ic_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(ic_holder)
	var border := ColorRect.new()
	border.custom_minimum_size = Vector2(24, 20)
	border.color = Color(0, 0, 0, 0.85)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic_holder.add_child(border)
	var icon := ColorRect.new()
	icon.position = Vector2(2, 2)
	icon.size = Vector2(20, 16)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	border.add_child(icon)
	var l := ItemListPanel.make_label("", COL_TEXT, 11)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.custom_minimum_size = Vector2(TAB_W - 4, 0)
	v.add_child(l)
	b.set_meta(&"label", l)
	b.set_meta(&"icon", icon)
	b.pressed.connect(func(): select_tab(index))
	var target := StringName("tab_%d" % index)
	b.set_drag_forwarding(func(_p): return null, func(_p, data): return can_drop_payload(target, data), func(_p, data): drop_payload(target, data))
	player_panel.tab_column.add_child(b)
	player_panel.tab_column.move_child(b, index)
	return b
