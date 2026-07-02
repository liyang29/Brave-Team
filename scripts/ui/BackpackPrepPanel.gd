extends VBoxContainer

# ─────────────────────────────────────────────────────────────────────────────
# BackpackPrepPanel — 背包/站位编辑组件（背包实验 + 跑局遭遇 prep 共用）
#
# 拖放交互（Godot 原生拖放，经 DragSlot/BagGridView 委托回本面板）：
#   驮兽仓库(mule) ↔ 背包格(bag) ↔ 背包格：拖物品（放到占用格=交换/同款同色阶=合成）
#   任意物品 → 丢弃桶(trash)：直接消失，腾地方
#   站位格(squad) ↔ 站位格：拖英雄（放到占用格=交换）
#   物品只能进 bag/mule/trash；英雄只能进 squad（载荷带 type 防错放）。
#
# 只负责"编辑"；开战/结果留给宿主。按引用操作宿主的 roster/mule_grid/squad_slots。
#   roster    : Array[{ "hero": Hero, "base": Dictionary, "grid": Dictionary }]
#   mule_grid : { Vector2i(锚点): item_id }（驮兽仓库，跟英雄 grid 同一套空间逻辑，
#                见 Backpack.MULE_GRID_W/H；卖出只能在村庄，见 MulePanel）
#   squad_slots : { Vector2i(col,row): Hero }  row0 前排 / row1 后排
# ─────────────────────────────────────────────────────────────────────────────

const Backpack = preload("res://scripts/systems/backpack/BackpackModel.gd")
const Loadout = preload("res://scripts/systems/backpack/BackpackLoadout.gd")
const DragSlot = preload("res://scripts/ui/DragSlot.gd")
const BagGridView = preload("res://scripts/ui/BagGridView.gd")

# 注入状态（引用宿主对象）
var _roster: Array = []
var _mule: Dictionary = {}
var _squad_slots: Dictionary = {}

# UI 节点引用
var _mule_view: BagGridView
var _squad_ui: Dictionary = {}     # Vector2i -> DragSlot
var _bag_views: Array = []         # 每英雄一个 BagGridView（自绘 4×4 多格背包）
var _stat_labels: Array = []       # 每英雄一个 Label


func setup(roster: Array, mule_grid: Dictionary, squad_slots: Dictionary) -> void:
	_roster = roster
	_mule = mule_grid
	_squad_slots = squad_slots
	add_theme_constant_override("separation", 8)
	_build_ui()
	refresh()

## 供 BagGridView(kind="mule") 读——驮兽仓库的原始 Dictionary 引用。
func mule_grid_ref() -> Dictionary:
	return _mule


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

## 把所有英雄背包里的东西尽量挪回驮兽（驮兽装不下的那件留在原背包不动——不会凭空消失）。
func return_all_to_mule() -> void:
	for entry in _roster:
		var grid: Dictionary = entry["grid"]
		for cell in grid.keys().duplicate():
			var anchor: Vector2i = Backpack.first_free_anchor(_mule, grid[cell], Backpack.MULE_GRID_W, Backpack.MULE_GRID_H)
			if anchor == Vector2i(-1, -1):
				continue   # 驮兽满了，这件留在背包里
			_mule[anchor] = grid[cell]
			grid.erase(cell)
	refresh()


# ── UI 构建 ───────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	add_child(_section("驮兽仓库（%d×%d 空间背包 · 拖到下面某人背包格装备；装满了先在这丢弃/去村庄卖）" %
		[Backpack.MULE_GRID_W, Backpack.MULE_GRID_H]))
	var mule_row := HBoxContainer.new()
	mule_row.add_theme_constant_override("separation", 12)
	_mule_view = BagGridView.new()
	_mule_view.panel = self
	_mule_view.kind = "mule"
	_mule_view.grid_w = Backpack.MULE_GRID_W
	_mule_view.grid_h = Backpack.MULE_GRID_H
	mule_row.add_child(_mule_view)
	var trash := _new_slot("trash", null, Vector2(72, 72))
	trash.set_display("🗑丢弃", Color(0.85, 0.55, 0.55))
	trash.tooltip_text = "把任意物品拖到这丢弃，直接消失、不进任何背包（腾地方用）"
	mule_row.add_child(trash)
	add_child(mule_row)

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
	var dead: bool = not entry["hero"].is_alive()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	if dead:
		box.modulate = Color(0.5, 0.5, 0.5)   # 整块变灰（含背包/属性文字），跟 HP 列表统一视觉语言

	var head := Label.new()
	head.text = entry["hero"].entity_name + ("（阵亡）" if dead else "")
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
	_mule_view.queue_redraw()
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
		"mule":
			var anchor: Vector2i = key
			if not _mule.has(anchor):
				return null
			return { "type": "item", "id": _mule[anchor], "label": Backpack.item_name(_mule[anchor]),
					"src": { "kind": "mule", "anchor": anchor } }
		"squad":
			var h = _squad_slots.get(key)
			if h == null:
				return null
			return { "type": "hero", "hero": h, "label": h.entity_name, "src_cell": key }
	return null


## 目标槽位能否接收该载荷（物品→bag/mule/trash；英雄→squad）。
func can_accept(kind: String, _key, data: Dictionary) -> bool:
	match data.get("type", ""):
		"item":
			return kind == "bag" or kind == "mule" or kind == "trash"
		"hero":
			return kind == "squad"
	return false


## 执行放下，然后延迟刷新（避免在拖放回调途中 free 当前槽位而报错）。
func handle_drop(kind: String, key, data: Dictionary) -> void:
	if data.get("type", "") == "item":
		if kind == "trash":
			_consume_dragged(data["src"], data["id"])   # 纯消耗，不落进任何地方
		else:
			_drop_item(data, kind, key)
	elif data.get("type", "") == "hero" and kind == "squad":
		_drop_hero(data, key)
	call_deferred("refresh")


## 英雄背包目标能否接收该物品（BagGridView 算落点幽灵 + 校验用）。
func bag_can_drop(hero_index: int, id: String, src: Dictionary, anchor: Vector2i) -> bool:
	var dest_grid: Dictionary = _roster[hero_index]["grid"]
	var ignore = null
	if src.get("kind", "") == "bag" and int(src.get("hero_index", -1)) == hero_index:
		ignore = src.get("cell")
	if Backpack.merge_target(dest_grid, id, anchor, ignore) != null:
		return true
	return Backpack.can_place(dest_grid, id, anchor, ignore)


## 驮兽仓库目标能否接收该物品（同 bag_can_drop，网格换成 _mule + 尺寸 6×6）。
func mule_can_drop(id: String, src: Dictionary, anchor: Vector2i) -> bool:
	var ignore = null
	if src.get("kind", "") == "mule":
		ignore = src.get("anchor")
	if Backpack.merge_target(_mule, id, anchor, ignore) != null:
		return true
	return Backpack.can_place(_mule, id, anchor, ignore, Backpack.MULE_GRID_W, Backpack.MULE_GRID_H)


func _drop_item(data: Dictionary, dest_kind: String, dest_key) -> void:
	var id: String = data["id"]
	var src: Dictionary = data["src"]

	var dest_grid: Dictionary = _mule if dest_kind == "mule" else _roster[dest_key["hero_index"]]["grid"]
	var anchor: Vector2i = dest_key if dest_kind == "mule" else dest_key["cell"]
	var w: int = Backpack.MULE_GRID_W if dest_kind == "mule" else Backpack.GRID_W
	var h: int = Backpack.MULE_GRID_H if dest_kind == "mule" else Backpack.GRID_H

	var ignore = null
	if dest_kind == "mule" and src.get("kind", "") == "mule":
		ignore = src.get("anchor")
	elif dest_kind == "bag" and src.get("kind", "") == "bag" and int(src.get("hero_index", -1)) == dest_key["hero_index"]:
		ignore = src.get("cell")

	# 落点是同基础同色阶可合成的物品 → 合成：消耗两件，原地生成高一色阶
	var merge_anchor = Backpack.merge_target(dest_grid, id, anchor, ignore)
	if merge_anchor != null:
		_consume_dragged(src, id)
		dest_grid[merge_anchor] = Backpack.merge_result(id)
		return

	# 形状感知：放得下才放，不做交换；放不下则原地不动
	if not Backpack.can_place(dest_grid, id, anchor, ignore, w, h):
		return                        # 越界/重叠 → 物品留在原处
	_consume_dragged(src, id)
	dest_grid[anchor] = id


func _consume_dragged(src: Dictionary, id: String) -> void:
	if src["kind"] == "mule":         # 驮兽 → 从原位移除
		_mule.erase(src["anchor"])
	elif src["kind"] == "bag":        # 背包 → 从原位移除
		_roster[src["hero_index"]]["grid"].erase(src["cell"])


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
