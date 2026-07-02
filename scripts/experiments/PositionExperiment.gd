extends Control

# ─────────────────────────────────────────────────────────────────────────────
# PositionExperiment — 方案 B「编队解谜自走棋」脏实验（一次性验证场景）
#
# 目的：用最小代价验证乐趣假设——
#   「针对遭遇配队/布阵 → 看它自动验证 → 是否产生'我真聪明'的火花」
#
# 遭遇谜题：敌方【前排 2 个重甲墙】挡着，【后排 1 个剧毒术士】不停放毒。
#   - 只带近战（战士）→ 够不到后排术士 → 被毒蚀团灭
#   - 带远程/突袭（法师/弓手/盗贼）→ 点掉术士 → 切断毒源 → 获胜
#   - 带牧师（净化）→ 不断解毒撑过消耗 → 获胜
#
# 这是 docs/COMBAT_REVAMP_AUTOBATTLER.md §8 的脏实验。验证完即可整体回退。
# 运行：直接以本场景为主场景启动，或在编辑器里 F6 运行 PositionExperiment.tscn。
# ─────────────────────────────────────────────────────────────────────────────

const CASTER_NAME: String = "剧毒术士"

var _roster: Array = []          # [{ hero, check, row_btn }]
var _result_label: RichTextLabel
var _log_label: RichTextLabel


func _ready() -> void:
	_build_roster_heroes()
	_build_ui()


# ── 角色构建 ──────────────────────────────────────────────────────────────────

# 造一个属性/技能固定的英雄（确定性，便于复现实验）
func _make_hero(cls: int, hp: int, atk: int, def_v: int, spd: int,
				magic: int, mp: int, skills: Array) -> Hero:
	var hero: Hero = HeroFactory.create(cls)
	hero.set("base_max_hp", hp)
	hero.set("base_attack", atk)
	hero.set("base_defense", def_v)
	hero.set("base_speed",  spd)
	hero.set("base_magic",  magic)
	hero.set("base_mp",     mp)
	# 覆盖随机技能为固定技能
	var sk = hero.get("skills")
	if sk != null:
		sk.clear()
	for s in skills:
		hero.learn_skill(s)
	hero.stat_block.rebuild()
	hero.current_hp = hero.get_max_hp()
	return hero


func _build_roster_heroes() -> void:
	_roster.clear()
	# 两个战士（凑"纯近战错误队"用），各一法/弓/盗/牧
	var defs: Array = [
		{ "cls": Hero.HeroClass.WARRIOR, "name": "战士·甲", "hp": 130, "atk": 16, "def": 12, "spd": 8,  "magic": 0,  "mp": 60, "skills": ["slash", "shield_bash"] },
		{ "cls": Hero.HeroClass.WARRIOR, "name": "战士·乙", "hp": 130, "atk": 16, "def": 12, "spd": 8,  "magic": 0,  "mp": 60, "skills": ["slash", "shield_bash"] },
		{ "cls": Hero.HeroClass.MAGE,    "name": "法师",    "hp": 70,  "atk": 8,  "def": 4,  "spd": 13, "magic": 18, "mp": 80, "skills": ["fireball"] },
		{ "cls": Hero.HeroClass.ARCHER,  "name": "弓手",    "hp": 100, "atk": 13, "def": 7,  "spd": 12, "magic": 0,  "mp": 50, "skills": ["precise_shot"] },
		{ "cls": Hero.HeroClass.ROGUE,   "name": "盗贼",    "hp": 90,  "atk": 14, "def": 6,  "spd": 16, "magic": 0,  "mp": 50, "skills": ["backstab"] },
		{ "cls": Hero.HeroClass.PRIEST,  "name": "牧师",    "hp": 85,  "atk": 6,  "def": 7,  "spd": 9,  "magic": 16, "mp": 80, "skills": ["purify", "holy_heal"] },
	]
	for d in defs:
		var hero: Hero = _make_hero(
			d["cls"], d["hp"], d["atk"], d["def"], d["spd"], d["magic"], d["mp"], d["skills"]
		)
		hero.entity_name = d["name"]
		_roster.append({ "hero": hero, "check": null, "row_btn": null })


# 每次开战重建遭遇（敌人模板不被战斗修改，重建仅为确定性与可读）
func _build_encounter() -> Array:
	var tank_a: EnemyData = _make_enemy("重甲墙·甲", 170, 10, 16, 6, "front", false, "armored", [])
	var tank_b: EnemyData = _make_enemy("重甲墙·乙", 170, 10, 16, 6, "front", false, "armored", [])
	var caster: EnemyData = _make_enemy(
		CASTER_NAME, 45, 18, 2, 11, "back", true, "caster", ["poison"]
	)
	caster.ai_type = EnemyData.AI_POISON_CASTER
	return [tank_a, tank_b, caster]


func _make_enemy(nm: String, hp: int, atk: int, def_v: int, spd: int,
				 prow: String, ranged: bool, role: String, threats: Array) -> EnemyData:
	var e: EnemyData = EnemyData.new()
	e.entity_name   = nm
	e.base_max_hp   = hp
	e.base_attack   = atk
	e.base_defense  = def_v
	e.base_speed    = spd
	e.base_magic    = 0
	e.ai_type       = EnemyData.AI_BASIC_ATTACK
	e.preferred_row = prow
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
	root.custom_minimum_size = Vector2(620, 0)
	root.add_theme_constant_override("separation", 8)
	scroll.add_child(root)

	var title: Label = Label.new()
	title.text = "方案 B 脏实验 · 编队解谜自走棋"
	title.add_theme_font_size_override("font_size", 22)
	root.add_child(title)

	var threat: RichTextLabel = RichTextLabel.new()
	threat.bbcode_enabled = true
	threat.fit_content = true
	threat.custom_minimum_size = Vector2(600, 0)
	threat.text = "[color=orange]⚠️ 遭遇：剧毒巢穴[/color]\n" \
		+ "敌方布阵：[b]前排 2 个重甲墙[/b] 挡路，[b]后排 1 个剧毒术士[/b] 持续放毒。\n" \
		+ "[color=gray]提示：纯近战够不到后排术士；带远程/突袭点掉它，或带牧师净化解毒。[/color]"
	root.add_child(threat)

	root.add_child(HSeparator.new())

	var hint: Label = Label.new()
	hint.text = "勾选出战英雄（最多 4 人），点按钮切换前/后排："
	root.add_child(hint)

	# 英雄编队行
	for entry in _roster:
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)

		var hero: Hero = entry["hero"]
		var check: CheckBox = CheckBox.new()
		check.text = "%s   HP %d / 攻 %d / 防 %d / 速 %d%s" % [
			hero.entity_name, hero.get_max_hp(), hero.get_attack(),
			hero.get_defense(), hero.get_speed(),
			("  魔 %d" % hero.get_magic()) if hero.get_magic() > 0 else ""
		]
		check.custom_minimum_size = Vector2(420, 0)
		row.add_child(check)
		entry["check"] = check

		var reach: bool = hero.hero_class in [Hero.HeroClass.MAGE, Hero.HeroClass.ARCHER, Hero.HeroClass.ROGUE]
		var row_btn: Button = Button.new()
		# 默认排位：近战前排，其余后排
		var default_row: String = "front" if hero.hero_class in [Hero.HeroClass.WARRIOR, Hero.HeroClass.ROGUE] else "back"
		row_btn.text = "前排" if default_row == "front" else "后排"
		row_btn.custom_minimum_size = Vector2(80, 0)
		row_btn.pressed.connect(_on_toggle_row.bind(row_btn))
		row.add_child(row_btn)
		entry["row_btn"] = row_btn

		var tag: Label = Label.new()
		tag.text = "（远程·可够后排）" if reach else "（近战·只能打前排）"
		tag.modulate = Color(0.5, 0.8, 1.0) if reach else Color(0.9, 0.6, 0.5)
		row.add_child(tag)

		root.add_child(row)

	root.add_child(HSeparator.new())

	var btns: HBoxContainer = HBoxContainer.new()
	btns.add_theme_constant_override("separation", 12)
	var fight_btn: Button = Button.new()
	fight_btn.text = "⚔ 开战"
	fight_btn.custom_minimum_size = Vector2(120, 36)
	fight_btn.pressed.connect(_on_fight)
	btns.add_child(fight_btn)

	var presets: Label = Label.new()
	presets.text = "试试：① 只选两个战士  ② 选两个战士 + 法师/弓手  ③ 两个战士 + 牧师"
	presets.modulate = Color(0.7, 0.7, 0.7)
	btns.add_child(presets)
	root.add_child(btns)

	_result_label = RichTextLabel.new()
	_result_label.bbcode_enabled = true
	_result_label.fit_content = true
	_result_label.custom_minimum_size = Vector2(600, 0)
	root.add_child(_result_label)

	root.add_child(HSeparator.new())

	var log_title: Label = Label.new()
	log_title.text = "战斗日志（展开查看）"
	log_title.modulate = Color(0.6, 0.6, 0.6)
	root.add_child(log_title)

	_log_label = RichTextLabel.new()
	_log_label.bbcode_enabled = true
	_log_label.fit_content = true
	_log_label.custom_minimum_size = Vector2(600, 0)
	root.add_child(_log_label)


func _on_toggle_row(btn: Button) -> void:
	btn.text = "后排" if btn.text == "前排" else "前排"


# ── 开战 ──────────────────────────────────────────────────────────────────────

func _on_fight() -> void:
	var selected: Array = []
	for entry in _roster:
		if entry["check"].button_pressed:
			selected.append(entry)

	if selected.is_empty():
		_result_label.text = "[color=red]请至少勾选 1 个英雄。[/color]"
		return
	if selected.size() > 4:
		_result_label.text = "[color=red]最多 4 人出战。[/color]"
		return

	# 重置 HP，组队，写入站位
	var heroes: Array = []
	for entry in selected:
		var h: Hero = entry["hero"]
		h.current_hp = h.get_max_hp()
		heroes.append(h)

	var party: Party = Party.create(heroes)
	for entry in selected:
		var r: String = "back" if entry["row_btn"].text == "后排" else "front"
		party.set_row(entry["hero"], r)

	var enemies: Array = _build_encounter()
	var result: BattleResult = BattleSimulator.simulate(party, enemies)

	_render_result(result, selected)


func _render_result(result: BattleResult, selected: Array) -> void:
	# 归因分析
	var caster_killed: bool = false
	var purify_used: bool   = false
	for log in result.turn_logs:
		if log.skill_id == "purify":
			purify_used = true
		if log.target_name == CASTER_NAME and log.is_kill:
			caster_killed = true

	# 远程/突袭职业无论前后排都能够到后排术士
	var has_reacher: bool = false
	for entry in selected:
		var h: Hero = entry["hero"]
		if h.hero_class in [Hero.HeroClass.MAGE, Hero.HeroClass.ARCHER, Hero.HeroClass.ROGUE]:
			has_reacher = true

	var head: String
	var reason: String
	if result.party_won:
		head = "[color=lime][b]✅ 胜利[/b][/color]（%d 回合）" % result.total_turns
		if caster_killed:
			reason = "[color=lightgreen]你的远程/突袭点掉了后排剧毒术士 → 毒源被切断 → 队伍稳住获胜。[/color]"
		elif purify_used:
			reason = "[color=lightgreen]牧师不断净化毒素 → 队伍撑过消耗 → 磨穿了前排墙获胜。[/color]"
		else:
			reason = "[color=lightgreen]队伍扛住了威胁并清场。[/color]"
	else:
		head = "[color=red][b]❌ 团灭[/b][/color]（%d 回合）" % result.total_turns
		if not caster_killed and not has_reacher:
			reason = "[color=salmon]没有任何单位能够到后排的剧毒术士 → 毒源源源不断 → 全队被毒蚀致死。\n" \
				+ "→ 试试带上 [b]法师/弓手/盗贼[/b] 点掉术士，或带 [b]牧师[/b] 净化解毒。[/color]"
		elif not caster_killed:
			reason = "[color=salmon]带了远程但没能及时点掉术士（或被前排拖住）→ 毒蚀压垮队伍。[/color]"
		else:
			reason = "[color=salmon]虽然切了毒源，但前排火力不足被耗死。[/color]"

	var dead_names: Array = []
	for h in result.dead_heroes:
		dead_names.append(h.entity_name)
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
	# 特殊标记
	if log.skill_id == "dot_tick":
		return "[color=#9b6dff]☠ %s 受到毒伤 %d%s[/color]" % [
			log.target_name, log.damage, "（倒下）" if log.is_kill else ""]
	if log.skill_id == "stun_skip":
		return "[color=gray]✶ %s 被眩晕，跳过行动[/color]" % log.actor_name
	if log.skill_id == "purify":
		return "[color=lightgreen]✦ %s 施放【净化】，清除队伍毒素[/color]" % log.actor_name
	if log.skill_id == "thorns":
		return "[color=#c0a060]✦ 荆棘反伤 %s %d[/color]" % [log.target_name, log.damage]
	if log.skill_id == "lifesteal":
		return "[color=lightgreen]✦ %s 吸血回复 %d[/color]" % [log.actor_name, log.damage]

	var action: String
	if log.skill_id.is_empty():
		action = "普攻"
	else:
		action = SkillTable.get_display_name(log.skill_id)

	var kill: String = "（击杀）" if log.is_kill else ""
	if log.damage > 0 or not log.skill_id.is_empty():
		return "%s 【%s】→ %s  %d 伤害%s" % [
			log.actor_name, action, log.target_name, log.damage, kill]
	return "%s 【%s】" % [log.actor_name, action]
