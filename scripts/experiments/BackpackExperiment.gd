extends Control

# ─────────────────────────────────────────────────────────────────────────────
# BackpackExperiment — 背包构筑脏实验（方案 B 新方向首验）
#
# 验证核心假设：「搭一套背包（网格空间有限 + 邻接协同）→ 看它打一场 →
#   '我搭出一套组合'那一下，爽不爽？」
#
# 编辑界面（物品池/站位板/背包格子）抽到共享组件 BackpackPrepPanel，与跑局
# 遭遇 prep 共用。本场景只保留：敌人 + 开战(满血) + 结果点评。
#
# 运行：以本场景为主场景启动，或编辑器 F6 运行 BackpackExperiment.tscn。
# ─────────────────────────────────────────────────────────────────────────────

const Backpack = preload("res://scripts/experiments/BackpackModel.gd")
const Loadout = preload("res://scripts/systems/BackpackLoadout.gd")
const Prep = preload("res://scripts/ui/BackpackPrepPanel.gd")

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

var _heroes: Array = []        # [{ hero, base:{}, grid:{}, name }]
var _pool: Dictionary = {}     # item_id -> remaining
var _squad_slots: Dictionary = {}

var _prep                      # BackpackPrepPanel
var _result_label: RichTextLabel
var _log_label: RichTextLabel


func _ready() -> void:
	_build_heroes()
	_place_default_formation()
	_pool = POOL_DEF.duplicate()
	_build_ui()


# 默认站位：战士前排，法师/牧师后排（玩家可自行调整）
func _place_default_formation() -> void:
	_squad_slots = {
		Vector2i(0, 0): _heroes[0]["hero"],
		Vector2i(0, 1): _heroes[1]["hero"],
		Vector2i(1, 1): _heroes[2]["hero"],
	}


# ── 英雄/敌人构建 ─────────────────────────────────────────────────────────────

func _make_hero(cls: int, nm: String) -> Hero:
	var hero: Hero = HeroFactory.create(cls)
	var sk = hero.get("skills")
	if sk != null:
		sk.clear()   # 技能改由背包技能书在开战时注入
	hero.entity_name = nm
	return hero


func _build_heroes() -> void:
	_heroes.clear()
	# 基础属性故意压低 —— 战斗力主要来自背包
	var defs: Array = [
		{ "cls": Hero.HeroClass.WARRIOR, "name": "战士",
		  "base": { "hp": 90, "atk": 6, "def": 8, "magic": 0, "spd": 9, "mp": 40 } },
		{ "cls": Hero.HeroClass.MAGE, "name": "法师",
		  "base": { "hp": 55, "atk": 3, "def": 3, "magic": 5, "spd": 12, "mp": 70 } },
		{ "cls": Hero.HeroClass.PRIEST, "name": "牧师",
		  "base": { "hp": 65, "atk": 3, "def": 4, "magic": 5, "spd": 9, "mp": 70 } },
	]
	for d in defs:
		var hero: Hero = _make_hero(d["cls"], d["name"])
		_heroes.append({ "hero": hero, "base": d["base"], "grid": {}, "name": d["name"] })


func _build_enemies() -> Array:
	# 一队需要"配装到位"才打得过的敌人（前排蛮兵 + 后排巫师），数值见 MonsterFactory
	return [
		MonsterFactory.create("brute", "蛮兵·甲"),
		MonsterFactory.create("brute", "蛮兵·乙"),
		MonsterFactory.create("dark_mage"),
	]


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

	# 共享编辑组件
	_prep = Prep.new()
	root.add_child(_prep)
	_prep.setup(_heroes, _pool, _squad_slots)

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
	clear_btn.pressed.connect(func(): _prep.return_all_to_pool())
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


# ── 开战 ──────────────────────────────────────────────────────────────────────

func _on_fight() -> void:
	if not _prep.any_item_placed():
		_result_label.text = "[color=red]先给队伍摆点装备再开战。[/color]"
		return
	if not _prep.has_front_row():
		_result_label.text = "[color=red]前排至少留 1 人（不能全员躲后排）。[/color]"
		return

	# 实验是单场，开战满血（full_heal=true）；跑局走钳血消耗战（false）。
	var party: Party = Loadout.build_party(_heroes, _squad_slots, true)
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
	if log.skill_id == "dodge":
		return "[color=#7fd0ff]✦ %s 闪避[/color]" % log.target_name
	if log.skill_id == "purify":
		return "[color=lightgreen]✦ %s 净化[/color]" % log.actor_name
	var action: String = "普攻" if log.skill_id.is_empty() else SkillTable.get_display_name(log.skill_id)
	var kill: String = "（击杀）" if log.is_kill else ""
	var crit: String = " [color=gold]暴击![/color]" if log.is_crit else ""
	if log.damage > 0 or not log.skill_id.is_empty():
		return "%s 【%s】→ %s  %d%s%s" % [log.actor_name, action, log.target_name, log.damage, crit, kill]
	return "%s 【%s】" % [log.actor_name, action]
