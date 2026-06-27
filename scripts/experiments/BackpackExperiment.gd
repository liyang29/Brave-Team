extends Control

# ─────────────────────────────────────────────────────────────────────────────
# BackpackExperiment — 背包构筑脏实验（方案 B 新方向首验）
#
# 验证核心假设：「搭一套背包（网格空间有限 + 邻接协同）→ 看它打一场 →
#   '我搭出一套组合'那一下，爽不爽？」
#
# 3 人小队，每人一个 3×2 小背包；从共享物品池把物品摆进格子：
#   - 物品给属性（攻/防/血/魔），战斗力全来自背包（不练级）
#   - 相邻同类触发协同（剑+磨刀石=开刃、盾+甲=重装、法器+法器=共鸣、生命+生命=生机）
#   - 把对的物品放对的人（法杖给法师、剑给战士）
# 战斗复用现有 BattleSimulator 自动结算（Megaloot 模式：深度全在搭背包）。
#
# 先不做：负重、骆驼公共背包、roguelike 地图、地形、金币、CD、装备/消耗双用。
# 运行：以本场景为主场景启动，或编辑器 F6 运行 BackpackExperiment.tscn。
# ─────────────────────────────────────────────────────────────────────────────

const Backpack = preload("res://scripts/experiments/BackpackModel.gd")

const BAG_COLS := 3
const BAG_ROWS := 2

# 共享物品池（item_id -> 数量）
const POOL_DEF: Dictionary = {
	"iron_sword": 1, "longsword": 1, "whetstone": 1,
	"shield": 1, "chainmail": 1, "leather": 1,
	"staff": 1, "tome": 1, "holy_symbol": 1,
	"amulet": 1, "charm": 1,
	# 技能书（占格、和装备抢空间；认职业）
	"book_slash": 1, "book_cleave": 1,
	"book_fireball": 1, "book_icelance": 1,
	"book_heal": 1, "book_purify": 1,
	# 副属性物品（暴击）
	"crit_gem": 1, "keen_edge": 1, "berserk_ring": 1,
}

var _heroes: Array = []        # [{ hero, base:{}, grid:{}, row, name, cls, cells:{cell:Button}, stat_label }]
var _pool: Dictionary = {}     # item_id -> remaining
var _selected_item: String = ""
var _pool_buttons: Dictionary = {}  # item_id -> Button

# 队伍站位板：Vector2i(col,row) -> hero。row 0=前排 / 1=后排。
# 选项 A（轻）：只有"前排/后排"影响战斗（前排挨打、后排被保护），列只是摆放槽位、不计入战斗。
var _squad_slots: Dictionary = {}
var _slot_buttons: Dictionary = {}
var _selected_slot = null

var _result_label: RichTextLabel
var _log_label: RichTextLabel


func _ready() -> void:
	_build_heroes()
	_place_default_formation()
	_pool = POOL_DEF.duplicate()
	_build_ui()
	_refresh()


# 默认站位：战士前排，法师/牧师后排（玩家可自行调整）
func _place_default_formation() -> void:
	_squad_slots = {
		Vector2i(0, 0): _heroes[0]["hero"],  # 战士 → 前排
		Vector2i(0, 1): _heroes[1]["hero"],  # 法师 → 后排
		Vector2i(1, 1): _heroes[2]["hero"],  # 牧师 → 后排
	}


# ── 英雄/敌人构建 ─────────────────────────────────────────────────────────────

func _make_hero(cls: int, nm: String) -> Hero:
	var hero: Hero = HeroFactory.create(cls)
	var sk = hero.get("skills")
	if sk != null:
		sk.clear()   # 技能改由背包技能书在开战时注入
	hero.entity_name = nm
	return hero


# Hero.HeroClass → SkillTable.hero_class 字符串（技能书职业匹配用）
func _class_key(cls: int) -> String:
	match cls:
		Hero.HeroClass.WARRIOR: return "warrior"
		Hero.HeroClass.MAGE:    return "mage"
		Hero.HeroClass.PRIEST:  return "priest"
		Hero.HeroClass.ROGUE:   return "rogue"
		Hero.HeroClass.ARCHER:  return "archer"
	return ""


func _build_heroes() -> void:
	_heroes.clear()
	# 基础属性故意压低 —— 战斗力主要来自背包
	var defs: Array = [
		{ "cls": Hero.HeroClass.WARRIOR, "name": "战士", "row": "front",
		  "base": { "hp": 90, "atk": 6, "def": 8, "magic": 0, "spd": 9, "mp": 40 } },
		{ "cls": Hero.HeroClass.MAGE, "name": "法师", "row": "back",
		  "base": { "hp": 55, "atk": 3, "def": 3, "magic": 5, "spd": 12, "mp": 70 } },
		{ "cls": Hero.HeroClass.PRIEST, "name": "牧师", "row": "back",
		  "base": { "hp": 65, "atk": 3, "def": 4, "magic": 5, "spd": 9, "mp": 70 } },
	]
	for d in defs:
		var hero: Hero = _make_hero(d["cls"], d["name"])
		_heroes.append({
			"hero": hero, "base": d["base"], "grid": {}, "row": d["row"],
			"name": d["name"], "cls": d["cls"], "cells": {}, "stat_label": null,
		})


func _build_enemies() -> Array:
	# 一队需要"配装到位"才打得过的敌人（前排蛮兵 + 后排巫师）
	return [
		_enemy("蛮兵·甲", 90, 15, 6, 8, "front", false, EnemyData.AI_AGGRESSIVE),
		_enemy("蛮兵·乙", 90, 15, 6, 8, "front", false, EnemyData.AI_AGGRESSIVE),
		_enemy("黑巫师", 60, 17, 3, 11, "back", true, EnemyData.AI_SPELLCASTER),
	]


func _enemy(nm: String, hp: int, atk: int, def_v: int, spd: int, prow: String,
			ranged: bool, ai: String) -> EnemyData:
	var e: EnemyData = EnemyData.new()
	e.entity_name = nm
	e.base_max_hp = hp
	e.base_attack = atk
	e.base_defense = def_v
	e.base_speed = spd
	e.base_magic = atk
	e.ai_type = ai
	e.preferred_row = prow
	e.is_ranged = ranged
	return e


# ── UI 构建 ───────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)

	var root: VBoxContainer = VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.custom_minimum_size = Vector2(720, 0)
	root.add_theme_constant_override("separation", 8)
	scroll.add_child(root)

	var title: Label = Label.new()
	title.text = "方案 B 新方向 · 背包构筑脏实验"
	title.add_theme_font_size_override("font_size", 22)
	root.add_child(title)

	var intro: RichTextLabel = RichTextLabel.new()
	intro.bbcode_enabled = true
	intro.fit_content = true
	intro.custom_minimum_size = Vector2(700, 0)
	intro.text = "[color=gray]从物品池把装备摆进 3 人背包。战斗力全来自背包。\n" \
		+ "[b]相邻同类触发协同[/b]：剑+磨刀石=开刃 / 盾+甲=重装 / 法器+法器=共鸣 / 生命+生命=生机。\n" \
		+ "把对的物品放对的人（法杖给法师、剑给战士），相邻摆放凑协同。[/color]"
	root.add_child(intro)

	# 物品池
	root.add_child(_section("物品池（点选 → 再点背包格子放入；点已放入的格子可取回）"))
	var pool_box: FlowContainer = FlowContainer.new()
	pool_box.custom_minimum_size = Vector2(700, 0)
	for item_id in POOL_DEF:
		var btn: Button = Button.new()
		btn.pressed.connect(_on_pool_pressed.bind(item_id))
		_pool_buttons[item_id] = btn
		pool_box.add_child(btn)
	root.add_child(pool_box)

	# 队伍站位板（点一个人 → 点另一格 移动/交换；前排挨打、后排被保护，列只是槽位）
	root.add_child(_section("队伍站位（点一个人 → 点另一格 移动/交换 · 前排挨打、后排被保护）"))
	root.add_child(_build_squad_board())

	# 3 个英雄背包
	root.add_child(_section("我方小队（每人 3×2 背包）"))
	var heroes_row: HBoxContainer = HBoxContainer.new()
	heroes_row.add_theme_constant_override("separation", 16)
	for i in range(_heroes.size()):
		heroes_row.add_child(_build_hero_panel(i))
	root.add_child(heroes_row)

	root.add_child(HSeparator.new())

	var btns: HBoxContainer = HBoxContainer.new()
	btns.add_theme_constant_override("separation", 12)
	var fight_btn: Button = Button.new()
	fight_btn.text = "⚔ 开战"
	fight_btn.custom_minimum_size = Vector2(120, 36)
	fight_btn.pressed.connect(_on_fight)
	btns.add_child(fight_btn)
	var clear_btn: Button = Button.new()
	clear_btn.text = "全部取回"
	clear_btn.pressed.connect(_on_clear)
	btns.add_child(clear_btn)
	root.add_child(btns)

	var hint: Label = Label.new()
	hint.modulate = Color(0.7, 0.7, 0.7)
	hint.text = "对比着玩：① 物品乱塞、不管相邻 vs ② 凑齐相邻协同 + 法杖给法师/剑给战士。看结果差多少。"
	root.add_child(hint)

	_result_label = RichTextLabel.new()
	_result_label.bbcode_enabled = true
	_result_label.fit_content = true
	_result_label.custom_minimum_size = Vector2(700, 0)
	root.add_child(_result_label)

	root.add_child(_section("战斗日志（展开查看）"))
	_log_label = RichTextLabel.new()
	_log_label.bbcode_enabled = true
	_log_label.fit_content = true
	_log_label.custom_minimum_size = Vector2(700, 0)
	root.add_child(_log_label)


func _section(t: String) -> Label:
	var l: Label = Label.new()
	l.text = t
	l.modulate = Color(0.65, 0.7, 0.8)
	return l


func _build_squad_board() -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	var grid: GridContainer = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	# row 0 = 前排（先放3格），row 1 = 后排
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


func _on_slot_pressed(cell: Vector2i) -> void:
	var occupant = _squad_slots.get(cell)
	if _selected_slot == null:
		# 拿起：只有占用的格子能选
		if occupant != null:
			_selected_slot = cell
	elif _selected_slot == cell:
		_selected_slot = null   # 再点一次取消
	else:
		# 移动 / 交换
		var sel_hero = _squad_slots.get(_selected_slot)
		if occupant != null:
			_squad_slots[_selected_slot] = occupant   # 交换
		else:
			_squad_slots.erase(_selected_slot)          # 移动到空格
		_squad_slots[cell] = sel_hero
		_selected_slot = null
	_refresh_board()


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


func _build_hero_panel(index: int) -> Control:
	var entry: Dictionary = _heroes[index]
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	var head: Label = Label.new()
	head.text = entry["name"]   # 前/后排由上方站位板决定
	head.add_theme_font_size_override("font_size", 16)
	box.add_child(head)

	var grid: GridContainer = GridContainer.new()
	grid.columns = BAG_COLS
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	for row in range(BAG_ROWS):
		for col in range(BAG_COLS):
			var cell := Vector2i(col, row)
			var btn: Button = Button.new()
			btn.custom_minimum_size = Vector2(96, 44)
			btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			btn.pressed.connect(_on_cell_pressed.bind(index, cell))
			entry["cells"][cell] = btn
			grid.add_child(btn)
	box.add_child(grid)

	var stat: Label = Label.new()
	stat.custom_minimum_size = Vector2(200, 0)
	stat.modulate = Color(0.8, 0.9, 0.8)
	entry["stat_label"] = stat
	box.add_child(stat)

	return box


# ── 交互 ──────────────────────────────────────────────────────────────────────

func _on_pool_pressed(item_id: String) -> void:
	if int(_pool.get(item_id, 0)) <= 0:
		return
	_selected_item = item_id
	_refresh()


func _on_cell_pressed(hero_index: int, cell: Vector2i) -> void:
	var grid: Dictionary = _heroes[hero_index]["grid"]
	if grid.has(cell):
		# 取回到池
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
	_refresh()


func _on_clear() -> void:
	for entry in _heroes:
		entry["grid"].clear()
	_pool = POOL_DEF.duplicate()
	_selected_item = ""
	_refresh()


func _refresh() -> void:
	# 物品池按钮
	for item_id in _pool_buttons:
		var btn: Button = _pool_buttons[item_id]
		var n: int = int(_pool.get(item_id, 0))
		var sel: String = "▶ " if _selected_item == item_id else ""
		btn.text = "%s%s ×%d" % [sel, Backpack.item_desc(item_id), n]
		btn.disabled = n <= 0
		btn.modulate = Color(0.7, 0.9, 1.0) if _selected_item == item_id else Color(1, 1, 1)

	# 背包格子 + 属性
	for entry in _heroes:
		var grid: Dictionary = entry["grid"]
		for cell in entry["cells"]:
			var cb: Button = entry["cells"][cell]
			if grid.has(cell):
				cb.text = Backpack.item_name(grid[cell])
				cb.modulate = Color(0.75, 1.0, 0.75)
			else:
				cb.text = "·"
				cb.modulate = Color(1, 1, 1)
		var b: Dictionary = Backpack.compute(grid)
		var base: Dictionary = entry["base"]
		var syn: String = ""
		if not b["synergies"].is_empty():
			syn = "  [协同:%s]" % ", ".join(b["synergies"])
		# 技能书 → 显示生效技能（职业不符标 ✗）
		var ck: String = _class_key(entry["cls"])
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
		entry["stat_label"].text = "攻%d 防%d 血%d 魔%d%s%s%s" % [
			int(base["atk"]) + b["atk"], int(base["def"]) + b["def"],
			int(base["hp"]) + b["hp"], int(base["magic"]) + b["magic"], crit_txt, syn, skill_line]

	_refresh_board()


# ── 开战 ──────────────────────────────────────────────────────────────────────

func _on_fight() -> void:
	var any_item := false
	for entry in _heroes:
		if not entry["grid"].is_empty():
			any_item = true
	if not any_item:
		_result_label.text = "[color=red]先给队伍摆点装备再开战。[/color]"
		return

	# 世界树规则：前排至少留 1 人
	var has_front := false
	for cell in _squad_slots:
		if _squad_slots[cell] != null and cell.y == 0:
			has_front = true
	if not has_front:
		_result_label.text = "[color=red]前排至少留 1 人（不能全员躲后排）。[/color]"
		return

	var heroes: Array = []
	var cd_map: Dictionary = {}      # hero -> { skill_id: cd_turns }
	var extra_map: Dictionary = {}   # hero -> { crit_chance: , crit_dmg: , ... }
	for entry in _heroes:
		var b: Dictionary = Backpack.compute(entry["grid"])
		var base: Dictionary = entry["base"]
		var hero = entry["hero"]
		hero.set("base_max_hp", int(base["hp"]) + b["hp"])
		hero.set("base_attack", int(base["atk"]) + b["atk"])
		hero.set("base_defense", int(base["def"]) + b["def"])
		hero.set("base_magic", int(base["magic"]) + b["magic"])
		hero.set("base_speed", int(base["spd"]))
		hero.set("base_mp", int(base["mp"]))
		hero.stat_block.rebuild()
		hero.current_hp = hero.get_max_hp()
		# 技能来自背包技能书（按职业过滤）；冷却配置随技能书带入
		var sk = hero.get("skills")
		if sk != null:
			sk.clear()
		var cfg: Dictionary = {}
		var ck: String = _class_key(hero.hero_class)
		for book in b["books"]:
			var sid: String = book["id"]
			if SkillTable.get_skill(sid).get("hero_class", "") == ck:
				if sk != null and not (sid in sk):
					sk.append(sid)
				if int(book["cd"]) > 0:
					cfg[sid] = int(book["cd"])
		cd_map[hero] = cfg
		extra_map[hero] = b["extra"]
		heroes.append(hero)

	var party: Party = Party.create(heroes, null, 0.4)
	party.positioning_mode = "soft_row"   # 世界树式软站位
	# 站位来自玩家在站位板上的摆放（只认前/后排，列不计入战斗）
	for cell in _squad_slots:
		var ph = _squad_slots[cell]
		if ph != null:
			party.set_row(ph, "front" if cell.y == 0 else "back")
	# 技能书冷却注入
	for hero in cd_map:
		party.set_skill_cd(hero, cd_map[hero])
	# 副属性注入（暴击等）
	for hero in extra_map:
		party.set_extra_stats(hero, extra_map[hero])

	var result: BattleResult = BattleSimulator.simulate(party, _build_enemies())
	_render_result(result)


func _render_result(result: BattleResult) -> void:
	# 汇总各人协同
	var fired: Array = []
	for entry in _heroes:
		var b: Dictionary = Backpack.compute(entry["grid"])
		for s in b["synergies"]:
			fired.append("%s·%s" % [entry["name"], s])

	var dead_names: Array = []
	for h in result.dead_heroes:
		dead_names.append(h.entity_name)

	var head: String
	var reason: String
	if result.party_won:
		head = "[color=lime][b]✅ 胜利[/b][/color]（%d 回合）" % result.total_turns
		if fired.is_empty():
			reason = "[color=lightgreen]险胜——但你一条协同都没凑，试试相邻摆放，会更稳更强。[/color]"
		else:
			reason = "[color=lightgreen]触发协同：%s → 配装到位，打赢了。[/color]" % ", ".join(fired)
	else:
		head = "[color=red][b]❌ 失败[/b][/color]（%d 回合）" % result.total_turns
		if fired.is_empty():
			reason = "[color=salmon]没有任何协同 + 可能物品放错人。\n→ 把剑+磨刀石、法器+法器等[b]相邻[/b]摆放，法杖给法师、剑给战士。[/color]"
		else:
			reason = "[color=salmon]凑了协同（%s）但还不够 —— 再优化分配/相邻关系。[/color]" % ", ".join(fired)

	var casualty: String = ""
	if not dead_names.is_empty():
		casualty = "\n[color=gray]阵亡：%s[/color]" % ", ".join(dead_names)

	_result_label.text = "%s\n%s%s" % [head, reason, casualty]
	_render_log(result)


func _render_log(result: BattleResult) -> void:
	var lines: Array = []
	for log in result.turn_logs:
		lines.append(_format_log_line(log))
	_log_label.text = "\n".join(lines)


func _format_log_line(log: TurnLog) -> String:
	if log.skill_id == "dot_tick":
		return "[color=#9b6dff]☠ %s 毒伤 %d[/color]" % [log.target_name, log.damage]
	if log.skill_id == "purify":
		return "[color=lightgreen]✦ %s 净化[/color]" % log.actor_name
	var action: String = "普攻" if log.skill_id.is_empty() else SkillTable.get_display_name(log.skill_id)
	var kill: String = "（击杀）" if log.is_kill else ""
	var crit: String = " [color=gold]暴击![/color]" if log.is_crit else ""
	if log.damage > 0 or not log.skill_id.is_empty():
		return "%s 【%s】→ %s  %d%s%s" % [log.actor_name, action, log.target_name, log.damage, crit, kill]
	return "%s 【%s】" % [log.actor_name, action]
