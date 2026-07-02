extends VBoxContainer

# ─────────────────────────────────────────────────────────────────────────────
# BackpackPrepPanel — 背包/站位编辑组件（背包实验 + 跑局遭遇 prep 共用）
#
# 拖放交互（Godot 原生拖放，经 DragSlot 委托回本面板）：
#   公共装备栏(pool) ↔ 背包格(bag) ↔ 背包格：拖物品（放到占用格=交换）
#   站位格(squad) ↔ 站位格：拖英雄（放到占用格=交换）
#   物品只能进 bag/pool；英雄只能进 squad（载荷带 type 防错放）。
#
# 只负责"编辑"；开战/结果留给宿主。按引用操作宿主的 roster/owned_items/squad_slots。
#   roster      : Array[{ "hero": Hero, "base": Dictionary, "grid": Dictionary }]
#   owned_items : { item_id: 数量 }（公共装备栏库存；数量到 0 自动移除该格）
#   squad_slots : { Vector2i(col,row): Hero }  row0 前排 / row1 后排
# ─────────────────────────────────────────────────────────────────────────────

const Backpack = preload("res://scripts/systems/backpack/BackpackModel.gd")
const Loadout = preload("res://scripts/systems/backpack/BackpackLoadout.gd")
const DragSlot = preload("res://scripts/ui/DragSlot.gd")
const BagGridView = preload("res://scripts/ui/BagGridView.gd")

# 注入状态（引用宿主对象）
var _roster: Array = []
var _pool: Dictionary = {}
var _squad_slots: Dictionary = {}

# UI 节点引用
var _pool_box: HFlowContainer
var _squad_ui: Dictionary = {}     # Vector2i -> DragSlot
var _bag_views: Array = []         # 每英雄一个 BagGridView（自绘 4×4 多格背包）
var _stat_labels: Array = []       # 每英雄一个 Label


func setup(roster: Array, owned_items: Dictionary, squad_slots: Dictionary) -> void:
	_roster = roster
	_pool = owned_items
	_squad_slots = squad_slots
	add_theme_constant_override("separation", 8)
	_build_ui()
	refresh()


# ── 给宿主用的校验/操作助手 ───────────────────────────────────────────────────

func has_front_row() -> bool:
	for cell in _squad_slots:
		if _squad_slots[cell] != null and cell.y == 0:
			return true
	return false

func any_item_placed() -> bool:
	for entry in _roster:
		if not entry["grid"].is_empty():
			return true
	return false

func return_all_to_pool() -> void:
	for entry in _roster:
		var grid: Dictionary = entry["grid"]
		for cell in grid.keys():
			_owned_add(grid[cell], 1)
		grid.clear()
	refresh()


# ── UI 构建 ───────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	add_child(_section("公共装备栏（拖到下面某人背包格；空着的格子从背包拖回来）"))
	_pool_box = HFlowContainer.new()
	_pool_box.custom_minimum_size = Vector2(700, 0)
	add_child(_pool_box)

	add_child(_section("队伍站位（直接把人拖到另一格 · 前排挨打、后排被保护）"))
	add_child(_build_squad_board())

	add_child(_section("我方小队（每人 4×4 空间背包 · 物品有形状、拖拽落点绿=可放/红=放不下 · 可在背包间互拖）"))
	var heroes_row := HBoxContainer.new()
	heroes_row.add_theme_constant_override("separation", 16)
	for i in range(_roster.size()):
		heroes_row.add_child(_build_hero_panel(i))
	add_child(heroes_row)


func _section(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.modulate = Color(0.65, 0.7, 0.8)
	return l


func _new_slot(kind: String, key, size: Vector2) -> Control:
	var slot := DragSlot.new()
	slot.panel = self
	slot.kind = kind
	slot.key = key
	slot.custom_minimum_size = size
	return slot


func _build_squad_board() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for row in range(2):
		for col in range(3):
			var cell := Vector2i(col, row)
			var slot := _new_slot("squad", cell, Vector2(120, 40))
			_squad_ui[cell] = slot
			grid.add_child(slot)
	box.add_child(grid)
	var legend := Label.new()
	legend.modulate = Color(0.6, 0.6, 0.6)
	legend.text = "站位：前排可打任何人；后排里 近战(战/牧/盗)只能打对方前排、远程(法/弓)可打后排。后排受物理伤×0.7、后排近战输出×0.5（魔法不受影响）；前排至少留1人，前排全灭后排顶上"
	box.add_child(legend)
	return box


func _build_hero_panel(index: int) -> Control:
	var entry: Dictionary = _roster[index]
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	var head := Label.new()
	head.text = entry["hero"].entity_name
	head.add_theme_font_size_override("font_size", 16)
	box.add_child(head)

	var bag := BagGridView.new()
	bag.panel = self
	bag.hero_index = index
	_bag_views.append(bag)
	box.add_child(bag)

	var stat := Label.new()
	stat.custom_minimum_size = Vector2(200, 0)
	stat.modulate = Color(0.8, 0.9, 0.8)
	_stat_labels.append(stat)
	box.add_child(stat)

	return box


# ── 刷新 ──────────────────────────────────────────────────────────────────────

func refresh() -> void:
	_rebuild_pool()
	# 全队最终属性（含光环），与开战时一致——保证"看到的=打出来的"
	var squad: Array = Loadout.squad_stats(_roster, _squad_slots)
	for i in range(_roster.size()):
		_bag_views[i].queue_redraw()   # 自绘背包读 grid 实时重画
		_stat_labels[i].text = _stat_text(_roster[i], squad[i])
	for cell in _squad_ui:
		var h = _squad_slots.get(cell)
		if h != null:
			_squad_ui[cell].set_display(h.entity_name, Color(0.75, 1.0, 0.75))
		else:
			_squad_ui[cell].set_display("·", Color(1, 1, 1))


func _rebuild_pool() -> void:
	for c in _pool_box.get_children():
		_pool_box.remove_child(c)
		c.free()
	var ids: Array = _pool.keys()
	ids.sort()
	for item_id in ids:
		var n: int = int(_pool.get(item_id, 0))
		if n <= 0:
			continue
		var wrap := HBoxContainer.new()
		wrap.add_theme_constant_override("separation", 2)
		var slot := _new_slot("pool", item_id, Vector2(110, 44))
		slot.set_display(Backpack.item_name(item_id), Backpack.tier_color(Backpack.item_tier(item_id)), "×%d" % n)
		slot.tooltip_text = Backpack.item_tooltip(item_id)
		wrap.add_child(slot)
		if n >= 2 and Backpack.is_mergeable(item_id):
			var result: String = Backpack.merge_result(item_id)
			if result != "":
				var merge_btn := Button.new()
				merge_btn.text = "⇪合成"
				merge_btn.custom_minimum_size = Vector2(56, 44)
				merge_btn.tooltip_text = "消耗 2 件 → 合成 1 件 %s" % Backpack.item_name(result)
				merge_btn.pressed.connect(func():
					merge_pool_item(item_id)
					refresh())
				wrap.add_child(merge_btn)
		_pool_box.add_child(wrap)


func _stat_text(entry: Dictionary, fs: Dictionary) -> String:
	# fs = 该英雄最终属性（含光环）；b = 自身背包（协同/技能/暴击显示用）
	var grid: Dictionary = entry["grid"]
	var b: Dictionary = Backpack.compute(grid)
	var syn := ""
	if not b["synergies"].is_empty():
		syn = "  [协同:%s]" % ", ".join(b["synergies"])
	var ck: String = Loadout.class_key(entry["hero"].hero_class)
	var skill_txt: Array = []
	for book in b["books"]:
		var sid: String = book["id"]
		var nm: String = SkillTable.get_display_name(sid)
		if SkillTable.get_skill(sid).get("hero_class", "") == ck:
			skill_txt.append(nm)
		else:
			skill_txt.append(nm + "✗职业不符")
	var skill_line := ""
	if not skill_txt.is_empty():
		skill_line = "\n技: " + ", ".join(skill_txt)
	var ex: Dictionary = b["extra"]
	var crit_txt := ""
	if float(ex.get("crit_chance", 0.0)) > 0.0:
		crit_txt = "  暴击%d%%" % int(float(ex["crit_chance"]) * 100)
		if float(ex.get("crit_dmg", 0.0)) > 0.0:
			crit_txt += "/暴伤+%d%%" % int(float(ex["crit_dmg"]) * 100)
	return "攻%d 防%d 血%d 魔%d 蓝%d%s%s%s" % [
		int(fs["atk"]), int(fs["def"]), int(fs["hp"]), int(fs["magic"]), int(fs["mp"]),
		crit_txt, syn, skill_line]


# ── 拖放回调（被 DragSlot 调用）────────────────────────────────────────────────

## 从某槽位取出载荷（拖起时）。空槽返回 null。
func grab_payload(kind: String, key) -> Variant:
	match kind:
		"bag":
			var grid: Dictionary = _roster[key["hero_index"]]["grid"]
			var c: Vector2i = key["cell"]
			if not grid.has(c):
				return null
			return { "type": "item", "id": grid[c], "label": Backpack.item_name(grid[c]),
					"src": { "kind": "bag", "hero_index": key["hero_index"], "cell": c } }
		"pool":
			if int(_pool.get(key, 0)) <= 0:
				return null
			return { "type": "item", "id": key, "label": Backpack.item_name(key),
					"src": { "kind": "pool", "id": key } }
		"squad":
			var h = _squad_slots.get(key)
			if h == null:
				return null
			return { "type": "hero", "hero": h, "label": h.entity_name, "src_cell": key }
	return null


## 目标槽位能否接收该载荷（物品→bag/pool；英雄→squad）。
func can_accept(kind: String, _key, data: Dictionary) -> bool:
	match data.get("type", ""):
		"item":
			return kind == "bag" or kind == "pool"
		"hero":
			return kind == "squad"
	return false


## 执行放下，然后延迟刷新（避免在拖放回调途中 free 当前槽位而报错）。
func handle_drop(kind: String, key, data: Dictionary) -> void:
	if data.get("type", "") == "item":
		_drop_item(data, kind, key)
	elif data.get("type", "") == "hero" and kind == "squad":
		_drop_hero(data, key)
	call_deferred("refresh")


## 背包目标能否接收该物品（BagGridView 算落点幽灵 + 校验用）。
## 形状感知：锚点处放得下(界内+不重叠) 才行；落在"同基础同色阶可合成"的另一件上 = 合成，
## 也算可放（预览显示为绿）；同背包移动排除物品自身原占用。
func bag_can_drop(hero_index: int, id: String, src: Dictionary, anchor: Vector2i) -> bool:
	if src.get("kind", "") == "pool" and int(_pool.get(id, 0)) <= 0:
		return false
	var dest_grid: Dictionary = _roster[hero_index]["grid"]
	var ignore = null
	if src.get("kind", "") == "bag" and int(src.get("hero_index", -1)) == hero_index:
		ignore = src.get("cell")
	if _merge_target(dest_grid, id, anchor, ignore) != null:
		return true
	return Backpack.can_place(dest_grid, id, anchor, ignore)


## 落点若压在"同基础同色阶、可合成"的现有物品上，返回该物品的锚点（合成目标）；否则 null。
func _merge_target(dest_grid: Dictionary, id: String, anchor: Vector2i, ignore):
	var occ_anchor = Backpack.occupied_cells(dest_grid).get(anchor)
	if occ_anchor == null or occ_anchor == ignore:
		return null
	var existing_id: String = dest_grid[occ_anchor]
	if Backpack.base_id(existing_id) != Backpack.base_id(id) or Backpack.item_tier(existing_id) != Backpack.item_tier(id):
		return null
	if Backpack.merge_result(id) == "":
		return null
	return occ_anchor


func _drop_item(data: Dictionary, dest_kind: String, dest_key) -> void:
	var id: String = data["id"]
	var src: Dictionary = data["src"]

	if dest_kind == "pool":
		if src["kind"] == "bag":      # 背包 → 库存
			_roster[src["hero_index"]]["grid"].erase(src["cell"])
			_owned_add(id, 1)
		return                        # 库存 → 库存：无操作

	# dest_kind == "bag"
	var hi: int = dest_key["hero_index"]
	var anchor: Vector2i = dest_key["cell"]
	var dest_grid: Dictionary = _roster[hi]["grid"]
	var ignore = null
	if src["kind"] == "bag" and int(src.get("hero_index", -1)) == hi:
		ignore = src.get("cell")

	# 落点是同基础同色阶可合成的物品 → 合成：消耗两件，原地生成高一色阶
	var merge_anchor = _merge_target(dest_grid, id, anchor, ignore)
	if merge_anchor != null:
		_consume_dragged(src, id)
		dest_grid[merge_anchor] = Backpack.merge_result(id)
		return

	# 形状感知：放得下才放，不做交换；放不下则原地不动
	if not Backpack.can_place(dest_grid, id, anchor, ignore):
		return                        # 越界/重叠/库存空 → 物品留在原处
	_consume_dragged(src, id)
	dest_grid[anchor] = id


func _consume_dragged(src: Dictionary, id: String) -> void:
	if src["kind"] == "pool":         # 库存 → 消耗一件
		_owned_add(id, -1)
	elif src["kind"] == "bag":        # 背包 → 从原位移除
		_roster[src["hero_index"]]["grid"].erase(src["cell"])


## 库存合成：某物品在库存里 ≥2 件且可合成 → 消耗 2 件、生成 1 件高一色阶。返回是否成功。
func merge_pool_item(item_id: String) -> bool:
	if int(_pool.get(item_id, 0)) < 2:
		return false
	var result: String = Backpack.merge_result(item_id)
	if result == "":
		return false
	_owned_add(item_id, -2)
	_owned_add(result, 1)
	return true


func _drop_hero(data: Dictionary, dest_cell: Vector2i) -> void:
	var src_cell: Vector2i = data["src_cell"]
	if src_cell == dest_cell:
		return
	var moving = _squad_slots.get(src_cell)
	var occupant = _squad_slots.get(dest_cell)
	if occupant != null:
		_squad_slots[src_cell] = occupant   # 交换
	else:
		_squad_slots.erase(src_cell)        # 移动到空格
	_squad_slots[dest_cell] = moving


func _owned_add(id: String, delta: int) -> void:
	var n: int = int(_pool.get(id, 0)) + delta
	if n <= 0:
		_pool.erase(id)
	else:
		_pool[id] = n
