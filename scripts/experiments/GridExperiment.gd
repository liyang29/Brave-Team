extends Control

# ─────────────────────────────────────────────────────────────────────────────
# GridExperiment — 方案 B「网格摆位解谜」脏实验（B2，验证"摆哪格"也成决策）
#
# 比 2 排脏实验多了「列维度」，引入两条新机制：
#   ① 逐列掩护：近战只能打前排 + "所在列没有前排掩护"的暴露后排。
#      → 脆皮后排必须和肉盾摆在同一列才挡得住；摆错列会被近战点穿。
#   ② 列穿刺：敌方穿刺手命中"人数最多的一列"整列（前+后排）。
#      → 把人堆在一列会被一锅端，逼你分散。
#
# 谜题：同一支队伍，摆位不同 → 输赢不同（2 排时只有"带谁"重要，现在"摆哪格"也重要）。
# 运行：以本场景为主场景启动，或编辑器 F6 运行 GridExperiment.tscn。
# ─────────────────────────────────────────────────────────────────────────────

const COLS := 3                       # 列：0 左 / 1 中 / 2 右
const ROWS := ["front", "back"]       # 行：前排 / 后排

var _roster: Array = []               # [{ hero, btn }]
var _placement: Dictionary = {}       # Vector2i(col,row_idx) -> hero
var _cell_buttons: Dictionary = {}    # Vector2i(col,row_idx) -> Button
var _selected_hero = null

var _result_label: RichTextLabel
var _log_label: RichTextLabel
var _count_label: Label


func _ready() -> void:
	_build_roster_heroes()
	_build_ui()
	_refresh()


# ── 英雄/敌人构建 ─────────────────────────────────────────────────────────────

func _make_hero(cls: int, nm: String, hp: int, atk: int, def_v: int, spd: int,
				magic: int, mp: int, skills: Array) -> Hero:
	var hero: Hero = HeroFactory.create(cls)
	hero.set("base_max_hp", hp)
	hero.set("base_attack", atk)
	hero.set("base_defense", def_v)
	hero.set("base_speed",  spd)
	hero.set("base_magic",  magic)
	hero.set("base_mp",     mp)
	var sk = hero.get("skills")
	if sk != null:
		sk.clear()
	for s in skills:
		hero.learn_skill(s)
	hero.stat_block.rebuild()
	hero.entity_name = nm
	hero.current_hp = hero.get_max_hp()
	return hero


func _build_roster_heroes() -> void:
	_roster.clear()
	var defs: Array = [
		{ "cls": Hero.HeroClass.WARRIOR, "name": "战士·甲", "hp": 140, "atk": 16, "def": 13, "spd": 8,  "magic": 0,  "mp": 60, "skills": ["slash", "shield_bash"] },
		{ "cls": Hero.HeroClass.WARRIOR, "name": "战士·乙", "hp": 140, "atk": 16, "def": 13, "spd": 8,  "magic": 0,  "mp": 60, "skills": ["slash", "shield_bash"] },
		{ "cls": Hero.HeroClass.PRIEST,  "name": "牧师",    "hp": 85,  "atk": 6,  "def": 7,  "spd": 9,  "magic": 17, "mp": 80, "skills": ["holy_heal", "purify"] },
		{ "cls": Hero.HeroClass.MAGE,    "name": "法师",    "hp": 70,  "atk": 8,  "def": 4,  "spd": 13, "magic": 19, "mp": 80, "skills": ["fireball"] },
		{ "cls": Hero.HeroClass.ARCHER,  "name": "弓手",    "hp": 100, "atk": 13, "def": 7,  "spd": 12, "magic": 0,  "mp": 50, "skills": ["precise_shot"] },
	]
	for d in defs:
		var hero: Hero = _make_hero(
			d["cls"], d["name"], d["hp"], d["atk"], d["def"], d["spd"], d["magic"], d["mp"], d["skills"]
		)
		_roster.append({ "hero": hero, "btn": null })


# 敌方布阵（2 行 × 3 列）：前排两堵重甲墙(凶猛·扑脆皮)，后排剧毒术士 + 列穿刺手
func _build_encounter() -> Array:
	return [
		_enemy("重甲墙·甲", 165, 21, 13, 7, "front", 0, false, EnemyData.AI_AGGRESSIVE, "armored", []),
		_enemy("重甲墙·乙", 165, 21, 13, 7, "front", 2, false, EnemyData.AI_AGGRESSIVE, "armored", []),
		_enemy("剧毒术士", 45, 18, 2, 11, "back", 1, true, EnemyData.AI_POISON_CASTER, "caster", ["poison"]),
		_enemy("列穿刺手", 55, 16, 3, 10, "back", 0, true, EnemyData.AI_COLUMN_PIERCER, "piercer", ["pierce"]),
	]


func _enemy(nm: String, hp: int, atk: int, def_v: int, spd: int, prow: String, pcol: int,
			ranged: bool, ai: String, role: String, threats: Array) -> EnemyData:
	var e: EnemyData = EnemyData.new()
	e.entity_name   = nm
	e.base_max_hp   = hp
	e.base_attack   = atk
	e.base_defense  = def_v
	e.base_speed    = spd
	e.base_magic    = 0
	e.ai_type       = ai
	e.preferred_row = prow
	e.preferred_col = pcol
	e.is_ranged     = ranged
	e.role          = role
	e.threats       = threats
	return e


# ── UI 构建 ───────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)

	var root: VBoxContainer = VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.custom_minimum_size = Vector2(640, 0)
	root.add_theme_constant_override("separation", 8)
	scroll.add_child(root)

	var title: Label = Label.new()
	title.text = "方案 B · B2 网格摆位解谜实验"
	title.add_theme_font_size_override("font_size", 22)
	root.add_child(title)

	var threat: RichTextLabel = RichTextLabel.new()
	threat.bbcode_enabled = true
	threat.fit_content = true
	threat.custom_minimum_size = Vector2(620, 0)
	threat.text = "[color=orange]⚠️ 遭遇威胁：剧毒 · 列穿刺[/color]\n" \
		+ "[color=gray]新机制：① 脆皮后排要和肉盾摆在[b]同一列[/b]才挡得住近战；" \
		+ "② 把人堆在一列会被[b]列穿刺[/b]一锅端 → 要分散。[/color]"
	root.add_child(threat)

	# 敌方网格（只读）
	root.add_child(_make_section_label("敌方布阵（前排挡刀 / 后排威胁）"))
	root.add_child(_build_enemy_grid())

	root.add_child(HSeparator.new())

	# 我方网格（可摆位）
	root.add_child(_make_section_label("我方布阵：点英雄选中 → 点格子放置（点已占格子可移除，最多 4 人）"))
	root.add_child(_build_player_grid())

	_count_label = Label.new()
	root.add_child(_count_label)

	# 英雄清单
	root.add_child(_make_section_label("英雄清单"))
	var roster_box: HBoxContainer = HBoxContainer.new()
	roster_box.add_theme_constant_override("separation", 8)
	for entry in _roster:
		var hero: Hero = entry["hero"]
		var btn: Button = Button.new()
		btn.toggle_mode = false
		btn.pressed.connect(_on_roster_pressed.bind(hero))
		entry["btn"] = btn
		roster_box.add_child(btn)
	root.add_child(roster_box)

	root.add_child(HSeparator.new())

	var btns: HBoxContainer = HBoxContainer.new()
	btns.add_theme_constant_override("separation", 12)
	var fight_btn: Button = Button.new()
	fight_btn.text = "⚔ 开战"
	fight_btn.custom_minimum_size = Vector2(120, 36)
	fight_btn.pressed.connect(_on_fight)
	btns.add_child(fight_btn)
	var clear_btn: Button = Button.new()
	clear_btn.text = "清空布阵"
	clear_btn.pressed.connect(_on_clear)
	btns.add_child(clear_btn)
	root.add_child(btns)

	var hint: Label = Label.new()
	hint.modulate = Color(0.7, 0.7, 0.7)
	hint.text = "试：① 牧师摆在重甲墙背后的同列(护住) vs 摆在没人的中列(被点穿)　② 全员堆左列(被穿刺一锅端)"
	root.add_child(hint)

	_result_label = RichTextLabel.new()
	_result_label.bbcode_enabled = true
	_result_label.fit_content = true
	_result_label.custom_minimum_size = Vector2(620, 0)
	root.add_child(_result_label)

	root.add_child(_make_section_label("战斗日志（展开查看）"))
	_log_label = RichTextLabel.new()
	_log_label.bbcode_enabled = true
	_log_label.fit_content = true
	_log_label.custom_minimum_size = Vector2(620, 0)
	root.add_child(_log_label)


func _make_section_label(t: String) -> Label:
	var l: Label = Label.new()
	l.text = t
	l.modulate = Color(0.65, 0.7, 0.8)
	return l


func _build_enemy_grid() -> Control:
	var enemies: Array = _build_encounter()
	# 建 col×row 索引
	var by_cell: Dictionary = {}
	for e in enemies:
		var ri: int = 0 if e.preferred_row == "front" else 1
		by_cell[Vector2i(e.preferred_col, ri)] = e

	var grid: GridContainer = GridContainer.new()
	grid.columns = COLS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for ri in range(ROWS.size()):
		for col in range(COLS):
			var panel: PanelContainer = PanelContainer.new()
			panel.custom_minimum_size = Vector2(190, 46)
			var lbl: Label = Label.new()
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			var e = by_cell.get(Vector2i(col, ri))
			if e != null:
				var tag: String = ""
				if not e.threats.is_empty():
					tag = "  ⚠"
				lbl.text = "%s%s" % [e.entity_name, tag]
				lbl.modulate = Color(1.0, 0.7, 0.6) if not e.threats.is_empty() else Color(0.85, 0.85, 0.85)
			else:
				lbl.text = "—"
				lbl.modulate = Color(0.4, 0.4, 0.4)
			panel.add_child(lbl)
			grid.add_child(panel)
	return grid


func _build_player_grid() -> Control:
	var grid: GridContainer = GridContainer.new()
	grid.columns = COLS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for ri in range(ROWS.size()):
		for col in range(COLS):
			var cell := Vector2i(col, ri)
			var btn: Button = Button.new()
			btn.custom_minimum_size = Vector2(190, 46)
			btn.pressed.connect(_on_cell_pressed.bind(cell))
			_cell_buttons[cell] = btn
			grid.add_child(btn)
	return grid


# ── 交互 ──────────────────────────────────────────────────────────────────────

func _on_roster_pressed(hero) -> void:
	_selected_hero = hero
	_refresh()


func _on_cell_pressed(cell: Vector2i) -> void:
	if _placement.has(cell):
		# 点已占格子 → 移除占用者
		_placement.erase(cell)
	elif _selected_hero != null:
		var already_placed: bool = _hero_cell(_selected_hero) != null
		if not already_placed and _placement.size() >= 4:
			_result_label.text = "[color=red]最多 4 人上场。[/color]"
			return
		var old = _hero_cell(_selected_hero)
		if old != null:
			_placement.erase(old)
		_placement[cell] = _selected_hero
		_selected_hero = null
	_refresh()


func _on_clear() -> void:
	_placement.clear()
	_selected_hero = null
	_refresh()


func _hero_cell(hero):  # -> Vector2i or null
	for cell in _placement:
		if _placement[cell] == hero:
			return cell
	return null


func _refresh() -> void:
	# 格子文字
	for cell in _cell_buttons:
		var btn: Button = _cell_buttons[cell]
		if _placement.has(cell):
			btn.text = _placement[cell].entity_name
			btn.modulate = Color(0.7, 1.0, 0.7)
		else:
			btn.text = "＋ 空"
			btn.modulate = Color(1, 1, 1)
	# 英雄清单按钮
	for entry in _roster:
		var hero: Hero = entry["hero"]
		var btn: Button = entry["btn"]
		var placed: bool = _hero_cell(hero) != null
		var sel: String = "▶ " if _selected_hero == hero else ""
		var done: String = "（已上场）" if placed else ""
		btn.text = "%s%s %s%s" % [sel, hero.entity_name, _class_short(hero), done]
		btn.modulate = Color(0.6, 0.6, 0.6) if placed else (Color(0.7, 0.9, 1.0) if _selected_hero == hero else Color(1, 1, 1))
	_count_label.text = "已上场 %d / 4" % _placement.size()


func _class_short(hero: Hero) -> String:
	match hero.hero_class:
		Hero.HeroClass.WARRIOR: return "[战·近战]"
		Hero.HeroClass.PRIEST:  return "[牧·后排净化]"
		Hero.HeroClass.MAGE:    return "[法·远程]"
		Hero.HeroClass.ARCHER:  return "[弓·远程]"
		Hero.HeroClass.ROGUE:   return "[盗·突袭]"
	return ""


# ── 开战 ──────────────────────────────────────────────────────────────────────

func _on_fight() -> void:
	if _placement.is_empty():
		_result_label.text = "[color=red]请先把英雄摆到格子上。[/color]"
		return

	var heroes: Array = []
	for cell in _placement:
		var h: Hero = _placement[cell]
		h.current_hp = h.get_max_hp()
		heroes.append(h)

	var party: Party = Party.create(heroes, null, 0.4)
	for cell in _placement:
		var h: Hero = _placement[cell]
		var row_str: String = ROWS[cell.y]
		party.set_cell(h, cell.x, row_str)

	var result: BattleResult = BattleSimulator.simulate(party, _build_encounter())
	_render_result(result)


func _render_result(result: BattleResult) -> void:
	var dead_names: Array = []
	for h in result.dead_heroes:
		dead_names.append(h.entity_name)
	var healer_died: bool = false
	for h in result.dead_heroes:
		if h.hero_class == Hero.HeroClass.PRIEST:
			healer_died = true

	var head: String
	var reason: String
	if result.party_won:
		head = "[color=lime][b]✅ 胜利[/b][/color]（%d 回合）" % result.total_turns
		reason = "[color=lightgreen]布阵到位：脆皮有掩护、没被穿刺一锅端，扛住威胁清场。[/color]"
	else:
		head = "[color=red][b]❌ 团灭[/b][/color]（%d 回合）" % result.total_turns
		if healer_died:
			reason = "[color=salmon]牧师过早阵亡 → 大概率是摆在了[b]没有前排掩护的列[/b]，被近战点穿。\n" \
				+ "→ 把牧师摆到重甲墙背后的同一列试试。[/color]"
		else:
			reason = "[color=salmon]可能把人堆在了同一列被列穿刺一锅端，或后排威胁没及时清掉。\n" \
				+ "→ 把队伍[b]分散到不同列[/b]、带远程点掉后排。[/color]"

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
		return "[color=#9b6dff]☠ %s 受到毒伤 %d%s[/color]" % [
			log.target_name, log.damage, "（倒下）" if log.is_kill else ""]
	if log.skill_id == "stun_skip":
		return "[color=gray]✶ %s 被眩晕，跳过行动[/color]" % log.actor_name
	if log.skill_id == "purify":
		return "[color=lightgreen]✦ %s 施放【净化】，清除队伍毒素[/color]" % log.actor_name
	if log.skill_id == "plasma_pierce":
		return "[color=#ff7a3d]✦ %s 电浆穿刺 → %s  %d 伤害%s[/color]" % [
			log.actor_name, log.target_name, log.damage, "（击杀）" if log.is_kill else ""]

	var action: String = "普攻" if log.skill_id.is_empty() else SkillTable.get_display_name(log.skill_id)
	var kill: String = "（击杀）" if log.is_kill else ""
	if log.damage > 0 or not log.skill_id.is_empty():
		return "%s 【%s】→ %s  %d 伤害%s" % [log.actor_name, action, log.target_name, log.damage, kill]
	return "%s 【%s】" % [log.actor_name, action]
