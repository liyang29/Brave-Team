extends VBoxContainer

# ─────────────────────────────────────────────────────────────────────────────
# BackpackPrepPanel — 背包/站位编辑组件（背包实验 + 跑局遭遇 prep 共用）
#
# 只负责「编辑」：物品池 + 站位板 + 每人背包格子 + 实时属性显示。
# 开战按钮 / 战斗结果留给宿主（实验场景 / Encounter 各一套，开战逻辑不同）。
#
# 操作"注入进来的状态"（按引用，直接改宿主的数据，无需回写）：
#   roster      : Array[{ "hero": Hero, "base": Dictionary, "grid": Dictionary }]
#   owned_items : { item_id: 数量 }（拥有但未摆入背包的库存）
#   squad_slots : { Vector2i(col,row): Hero }  row0 前排 / row1 后排
#
# 故意不带 class_name（preload 引入），同项目其它脚本一致。
# ─────────────────────────────────────────────────────────────────────────────

const Backpack = preload("res://scripts/experiments/BackpackModel.gd")
const Loadout = preload("res://scripts/systems/BackpackLoadout.gd")

const BAG_COLS := 3
const BAG_ROWS := 2

# 注入的状态（引用宿主对象）
var _roster: Array = []
var _pool: Dictionary = {}
var _squad_slots: Dictionary = {}

# 选择态
var _selected_item: String = ""
var _selected_slot = null

# UI 节点引用
var _pool_box: FlowContainer
var _pool_buttons: Dictionary = {}      # item_id -> Button
var _slot_buttons: Dictionary = {}      # Vector2i -> Button
var _cell_buttons: Array = []           # 每英雄一份 { Vector2i: Button }
var _stat_labels: Array = []            # 每英雄一个 Label


## 注入状态并构建 UI。宿主在把本组件加入场景后调用。
func setup(roster: Array, owned_items: Dictionary, squad_slots: Dictionary) -> void:
	_roster = roster
	_pool = owned_items
	_squad_slots = squad_slots
	add_theme_constant_override("separation", 8)
	_build_ui()
	refresh()


# ── 给宿主用的校验/操作助手 ───────────────────────────────────────────────────

## 前排至少有一个人（世界树规则）
func has_front_row() -> bool:
	for cell in _squad_slots:
		if _squad_slots[cell] != null and cell.y == 0:
			return true
	return false

## 是否至少摆了一件装备
func any_item_placed() -> bool:
	for entry in _roster:
		if not entry["grid"].is_empty():
			return true
	return false

## 把所有已摆放的物品退回库存（"全部取回"按钮用）
func return_all_to_pool() -> void:
	for entry in _roster:
		var grid: Dictionary = entry["grid"]
		for cell in grid.keys():
			var id: String = grid[cell]
			_pool[id] = int(_pool.get(id, 0)) + 1
		grid.clear()
	_selected_item = ""
	refresh()


# ── UI 构建 ───────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	add_child(_section("物品池（点选 → 再点背包格子放入；点已放入的格子可取回）"))
	_pool_box = FlowContainer.new()
	_pool_box.custom_minimum_size = Vector2(700, 0)
	add_child(_pool_box)
	_build_pool()

	add_child(_section("队伍站位（点一个人 → 点另一格 移动/交换 · 前排挨打、后排被保护）"))
	add_child(_build_squad_board())

	add_child(_section("我方小队（每人 3×2 背包）"))
	var heroes_row: HBoxContainer = HBoxContainer.new()
	heroes_row.add_theme_constant_override("separation", 16)
	for i in range(_roster.size()):
		heroes_row.add_child(_build_hero_panel(i))
	add_child(heroes_row)


func _section(t: String) -> Label:
	var l: Label = Label.new()
	l.text = t
	l.modulate = Color(0.65, 0.7, 0.8)
	return l


# 物品池按钮一次性建好（一次编辑期内 key 集固定：库存 keys ∪ 已摆放 id）。
# 不在 refresh 里重建，避免"按下池按钮→refresh 释放该按钮"的自毁。
func _build_pool() -> void:
	var ids: Dictionary = {}
	for id in _pool:
		ids[id] = true
	for entry in _roster:
		for cell in entry["grid"]:
			ids[entry["grid"][cell]] = true
	var sorted_ids: Array = ids.keys()
	sorted_ids.sort()
	for item_id in sorted_ids:
		var btn: Button = Button.new()
		btn.pressed.connect(_on_pool_pressed.bind(item_id))
		_pool_buttons[item_id] = btn
		_pool_box.add_child(btn)


func _build_squad_board() -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	var grid: GridContainer = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for row in range(2):
		for col in range(3):
			var cell := Vector2i(col, row)
			var btn: Button = Button.new()
			btn.custom_minimum_size = Vector2(120, 40)
			btn.pressed.connect(_on_slot_pressed.bind(cell))
			_slot_buttons[cell] = btn
			grid.add_child(btn)
	box.add_child(grid)

	var legend: Label = Label.new()
	legend.modulate = Color(0.6, 0.6, 0.6)
	legend.text = "世界树式站位：后排受物理伤×0.7（更安全）、后排近战输出×0.5（远程/法术不受影响）；前排至少留1人，前排全灭后排自动顶上"
	box.add_child(legend)
	return box


func _build_hero_panel(index: int) -> Control:
	var entry: Dictionary = _roster[index]
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	var head: Label = Label.new()
	head.text = entry["hero"].entity_name   # 前/后排由站位板决定
	head.add_theme_font_size_override("font_size", 16)
	box.add_child(head)

	var grid: GridContainer = GridContainer.new()
	grid.columns = BAG_COLS
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	var cells: Dictionary = {}
	for row in range(BAG_ROWS):
		for col in range(BAG_COLS):
			var cell := Vector2i(col, row)
			var btn: Button = Button.new()
			btn.custom_minimum_size = Vector2(96, 44)
			btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			btn.pressed.connect(_on_cell_pressed.bind(index, cell))
			cells[cell] = btn
			grid.add_child(btn)
	_cell_buttons.append(cells)
	box.add_child(grid)

	var stat: Label = Label.new()
	stat.custom_minimum_size = Vector2(200, 0)
	stat.modulate = Color(0.8, 0.9, 0.8)
	_stat_labels.append(stat)
	box.add_child(stat)

	return box


# ── 交互 ──────────────────────────────────────────────────────────────────────

func _on_pool_pressed(item_id: String) -> void:
	if int(_pool.get(item_id, 0)) <= 0:
		return
	_selected_item = item_id
	refresh()


func _on_cell_pressed(hero_index: int, cell: Vector2i) -> void:
	var grid: Dictionary = _roster[hero_index]["grid"]
	if grid.has(cell):
		# 取回到库存
		var returned: String = grid[cell]
		grid.erase(cell)
		_pool[returned] = int(_pool.get(returned, 0)) + 1
	elif _selected_item != "":
		if int(_pool.get(_selected_item, 0)) <= 0:
			return
		grid[cell] = _selected_item
		_pool[_selected_item] = int(_pool[_selected_item]) - 1
		if int(_pool[_selected_item]) <= 0:
			_selected_item = ""
	refresh()


func _on_slot_pressed(cell: Vector2i) -> void:
	var occupant = _squad_slots.get(cell)
	if _selected_slot == null:
		if occupant != null:
			_selected_slot = cell
	elif _selected_slot == cell:
		_selected_slot = null
	else:
		var sel_hero = _squad_slots.get(_selected_slot)
		if occupant != null:
			_squad_slots[_selected_slot] = occupant   # 交换
		else:
			_squad_slots.erase(_selected_slot)         # 移动到空格
		_squad_slots[cell] = sel_hero
		_selected_slot = null
	_refresh_board()


# ── 刷新 ──────────────────────────────────────────────────────────────────────

func refresh() -> void:
	# 物品池按钮
	for item_id in _pool_buttons:
		var btn: Button = _pool_buttons[item_id]
		var n: int = int(_pool.get(item_id, 0))
		var sel: String = "▶ " if _selected_item == item_id else ""
		btn.text = "%s%s ×%d" % [sel, Backpack.item_desc(item_id), n]
		btn.disabled = n <= 0
		btn.modulate = Color(0.7, 0.9, 1.0) if _selected_item == item_id else Color(1, 1, 1)

	# 背包格子 + 属性
	for i in range(_roster.size()):
		var entry: Dictionary = _roster[i]
		var grid: Dictionary = entry["grid"]
		var cells: Dictionary = _cell_buttons[i]
		for cell in cells:
			var cb: Button = cells[cell]
			if grid.has(cell):
				cb.text = Backpack.item_name(grid[cell])
				cb.modulate = Color(0.75, 1.0, 0.75)
			else:
				cb.text = "·"
				cb.modulate = Color(1, 1, 1)
		_stat_labels[i].text = _stat_text(entry)

	_refresh_board()


func _stat_text(entry: Dictionary) -> String:
	var grid: Dictionary = entry["grid"]
	var base: Dictionary = entry["base"]
	var b: Dictionary = Backpack.compute(grid)
	var syn: String = ""
	if not b["synergies"].is_empty():
		syn = "  [协同:%s]" % ", ".join(b["synergies"])
	# 技能书 → 显示生效技能（职业不符标 ✗）
	var ck: String = Loadout.class_key(entry["hero"].hero_class)
	var skill_txt: Array = []
	for book in b["books"]:
		var sid: String = book["id"]
		var nm: String = SkillTable.get_display_name(sid)
		if SkillTable.get_skill(sid).get("hero_class", "") == ck:
			skill_txt.append(nm)
		else:
			skill_txt.append(nm + "✗职业不符")
	var skill_line: String = ""
	if not skill_txt.is_empty():
		skill_line = "\n技: " + ", ".join(skill_txt)
	# 暴击副属性
	var ex: Dictionary = b["extra"]
	var crit_txt: String = ""
	if float(ex.get("crit_chance", 0.0)) > 0.0:
		crit_txt = "  暴击%d%%" % int(float(ex["crit_chance"]) * 100)
		if float(ex.get("crit_dmg", 0.0)) > 0.0:
			crit_txt += "/暴伤+%d%%" % int(float(ex["crit_dmg"]) * 100)
	return "攻%d 防%d 血%d 魔%d%s%s%s" % [
		int(base["atk"]) + int(b["atk"]), int(base["def"]) + int(b["def"]),
		int(base["hp"]) + int(b["hp"]), int(base["magic"]) + int(b["magic"]),
		crit_txt, syn, skill_line]


func _refresh_board() -> void:
	for cell in _slot_buttons:
		var btn: Button = _slot_buttons[cell]
		var h = _squad_slots.get(cell)
		var picked: bool = _selected_slot == cell
		if h != null:
			btn.text = ("▶ " if picked else "") + h.entity_name
			btn.modulate = Color(0.7, 0.9, 1.0) if picked else Color(0.75, 1.0, 0.75)
		else:
			btn.text = "·"
			btn.modulate = Color(1, 1, 1)
