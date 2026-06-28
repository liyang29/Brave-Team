extends GutTest

# ─────────────────────────────────────────────────────────────────────────────
# test_backpack_experiment — 背包脏实验：协同计算 + "巧搭 vs 乱搭"验证
#
# 命题：同一批物品，[摆出邻接协同 + 放对人] 明显强于 [无协同 + 放错人]。
# 同时锁定 BackpackModel.compute 的邻接协同计算。
# ─────────────────────────────────────────────────────────────────────────────

const Backpack = preload("res://scripts/experiments/BackpackModel.gd")
const TRIALS := 20

# ── 协同计算单测（确定性，无 RNG）─────────────────────────────────────────────

func test_item_tooltip_equipment() -> void:
	var tip := Backpack.item_tooltip("shield")
	assert_true(tip.contains("圆盾"), "含名字")
	assert_true(tip.contains("防 +5"), "含属性")
	assert_true(tip.contains("重装"), "含协同提示")

func test_item_tooltip_skillbook() -> void:
	var tip := Backpack.item_tooltip("book_heal")
	assert_true(tip.contains("技能书"), "标明技能书")
	assert_true(tip.contains("牧师"), "含认职业")
	assert_true(tip.contains("治疗"), "含技能效果说明")


func test_item_stats_sum() -> void:
	var grid := { Vector2i(0,0): "iron_sword", Vector2i(2,0): "whetstone" }  # 不相邻
	var b := Backpack.compute(grid)
	assert_eq(b["atk"], 8, "铁剑6+磨刀石2，不相邻无协同 = 8")
	assert_true(b["synergies"].is_empty(), "不相邻不触发协同")

func test_blade_sharpen_adjacent() -> void:
	var grid := { Vector2i(0,0): "iron_sword", Vector2i(1,0): "whetstone" }  # 相邻
	var b := Backpack.compute(grid)
	assert_eq(b["atk"], 14, "铁剑6+磨刀石2+开刃6 = 14")
	assert_true("开刃" in b["synergies"], "相邻 blade+sharpen 触发开刃")

func test_arcane_resonance() -> void:
	var grid := { Vector2i(0,0): "staff", Vector2i(1,0): "tome" }
	var b := Backpack.compute(grid)
	assert_eq(b["magic"], 16, "法杖6+魔典4+共鸣6 = 16")
	assert_true("共鸣" in b["synergies"], "相邻 arcane+arcane 触发共鸣")

func test_skillbook_in_compute() -> void:
	var grid := { Vector2i(0,0): "book_fireball", Vector2i(1,0): "iron_sword" }
	var b := Backpack.compute(grid)
	assert_eq(b["atk"], 6, "技能书不给属性，只有剑给攻+6")
	assert_eq(b["books"].size(), 1, "收集到 1 本技能书")
	assert_eq(b["books"][0]["id"], "fireball", "技能书 skill_id 正确")
	assert_eq(int(b["books"][0]["cd"]), 2, "技能书 cd 正确")


func test_skill_cooldown_basic() -> void:
	var bc := BattleCombatant.new()
	bc.skill_cd_config = { "fireball": 2 }
	assert_false(bc.is_skill_on_cooldown("fireball"), "初始不在冷却")
	bc.trigger_skill_cooldown("fireball")
	assert_true(bc.is_skill_on_cooldown("fireball"), "触发后在冷却")
	bc.tick_cooldowns()   # 2 → 1
	assert_true(bc.is_skill_on_cooldown("fireball"), "过 1 回合仍在冷却")
	bc.tick_cooldowns()   # 1 → 0 移除
	assert_false(bc.is_skill_on_cooldown("fireball"), "过 2 回合冷却结束")


func test_skill_cooldown_no_config_means_no_cd() -> void:
	var bc := BattleCombatant.new()
	bc.trigger_skill_cooldown("fireball")   # 未配置冷却
	assert_false(bc.is_skill_on_cooldown("fireball"), "无配置的技能不进冷却（向后兼容旧战斗）")


func test_crit_extra_in_compute() -> void:
	var grid := { Vector2i(0,0): "crit_gem", Vector2i(1,0): "berserk_ring" }
	var b := Backpack.compute(grid)
	assert_almost_eq(float(b["extra"].get("crit_chance", 0.0)), 0.15, 0.001, "暴击宝石给 15% 暴击率")
	assert_almost_eq(float(b["extra"].get("crit_dmg", 0.0)), 0.5, 0.001, "狂战戒给 +50% 暴伤")


func test_roll_crit_guaranteed() -> void:
	var bc := BattleCombatant.new()
	bc.extra_stats = { "crit_chance": 1.0, "crit_dmg": 0.5 }
	var m := BattleSimulator._roll_crit(bc)
	assert_almost_eq(m, 2.0, 0.001, "暴击率 100% → 倍率 = 1.5 + 0.5 = 2.0")


func test_roll_crit_none_is_backward_compatible() -> void:
	var bc := BattleCombatant.new()   # 无副属性
	assert_eq(BattleSimulator._roll_crit(bc), 1.0, "无暴击属性 → 倍率 1.0（旧战斗不变）")


# ── 世界树式软站位 ────────────────────────────────────────────────────────────

func _row_bc(row: String) -> BattleCombatant:
	var bc := BattleCombatant.new()
	bc.row = row
	bc.current_hp = 10
	bc.max_hp = 10
	return bc

func test_soft_row_damage_mult() -> void:
	var af := _row_bc("front")
	var ab := _row_bc("back")
	var df := _row_bc("front")
	var db := _row_bc("back")
	# soft_row + 物理
	assert_almost_eq(BattleSimulator._row_damage_mult(af, df, true, "soft_row"), 1.0, 0.001, "前打前×1.0")
	assert_almost_eq(BattleSimulator._row_damage_mult(ab, df, true, "soft_row"), 0.5, 0.001, "后排近战输出×0.5")
	assert_almost_eq(BattleSimulator._row_damage_mult(af, db, true, "soft_row"), 0.7, 0.001, "打后排物理×0.7")
	assert_almost_eq(BattleSimulator._row_damage_mult(ab, db, true, "soft_row"), 0.35, 0.001, "后排打后排×0.35")
	# 魔法不受站位影响
	assert_almost_eq(BattleSimulator._row_damage_mult(ab, db, false, "soft_row"), 1.0, 0.001, "魔法不受站位影响")
	# reach 模式恒 1.0（向后兼容，其他实验不变）
	assert_almost_eq(BattleSimulator._row_damage_mult(ab, db, true, "reach"), 1.0, 0.001, "reach 模式不改伤害")


func test_basic_attack_applies_soft_row() -> void:
	# 回归：普攻（含敌方占位技能回退的那条路）必须应用站位修正，不能打满伤
	var atk := BattleCombatant.new()
	atk.attack = 20
	atk.row = "back"
	atk.current_hp = 10
	atk.max_hp = 10
	var tgt := BattleCombatant.new()
	tgt.row = "back"
	tgt.defense = 0
	tgt.current_hp = 100
	tgt.max_hp = 100
	var logs: Array = BattleSimulator._basic_attack(atk, tgt, "soft_row")
	assert_eq(logs[0].damage, 7, "后排普攻打后排：20×0.5×0.7=7（含站位修正）")
	tgt.current_hp = 100
	var logs2: Array = BattleSimulator._basic_attack(atk, tgt, "reach")
	assert_eq(logs2[0].damage, 20, "reach 模式普攻不受站位影响")


func test_unknown_skill_falls_back_to_basic_with_row_mult() -> void:
	# 回归 bug：敌方 spellcaster 的占位 "enemy_spell" 是未知技能，
	# 走回退分支时也必须应用站位修正（旧版漏算导致忽高忽低）
	var atk := BattleCombatant.new()
	atk.attack = 20
	atk.row = "back"
	atk.current_hp = 10
	atk.max_hp = 10
	var tgt := BattleCombatant.new()
	tgt.row = "back"
	tgt.defense = 0
	tgt.current_hp = 100
	tgt.max_hp = 100
	var logs: Array = BattleSimulator._execute_action(atk, "enemy_spell", tgt, [tgt], [], [tgt], "soft_row")
	assert_eq(logs[0].damage, 7, "未知技能回退普攻同样吃站位修正（不再打满 20）")


func test_promote_if_front_empty() -> void:
	var dead_front := _row_bc("front")
	dead_front.current_hp = 0
	var back := _row_bc("back")
	BattleSimulator._promote_if_front_empty([dead_front, back])
	assert_eq(back.row, "front", "前排全灭 → 后排顶上前排")

	var alive_front := _row_bc("front")
	var back2 := _row_bc("back")
	BattleSimulator._promote_if_front_empty([alive_front, back2])
	assert_eq(back2.row, "back", "前排还有活人 → 后排不动")


func test_guard_armor_and_vital() -> void:
	var grid := {
		Vector2i(0,0): "shield", Vector2i(0,1): "chainmail",  # guard+armor 相邻(下)
		Vector2i(2,0): "amulet", Vector2i(2,1): "charm",      # vital+vital 相邻(下)
	}
	var b := Backpack.compute(grid)
	assert_true("重装" in b["synergies"], "盾+甲触发重装")
	assert_true("生机" in b["synergies"], "护符+红宝石触发生机")


# ── 战斗验证：巧搭 vs 乱搭 ────────────────────────────────────────────────────

func _hero(cls: int, skills: Array) -> Hero:
	var hero: Hero = HeroFactory.create(cls)
	var sk = hero.get("skills")
	if sk != null:
		sk.clear()
	for s in skills:
		hero.learn_skill(s)
	return hero

func _bases() -> Array:
	return [
		{ "cls": Hero.HeroClass.WARRIOR, "row": "front", "skills": ["slash"],
		  "base": { "hp": 90, "atk": 6, "def": 8, "magic": 0, "spd": 9, "mp": 40 } },
		{ "cls": Hero.HeroClass.MAGE, "row": "back", "skills": ["fireball"],
		  "base": { "hp": 55, "atk": 3, "def": 3, "magic": 5, "spd": 12, "mp": 70 } },
		{ "cls": Hero.HeroClass.PRIEST, "row": "back", "skills": ["holy_heal", "purify"],
		  "base": { "hp": 65, "atk": 3, "def": 4, "magic": 5, "spd": 9, "mp": 70 } },
	]

func _enemies() -> Array:
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

# grids: 3 个 Dictionary(cell->item_id)，对应 战/法/牧
func _run(grids: Array) -> int:
	var bases := _bases()
	var heroes: Array = []
	for cfg in bases:
		heroes.append(_hero(cfg["cls"], cfg["skills"]))
	var wins := 0
	for t in TRIALS:
		for i in range(heroes.size()):
			var base: Dictionary = bases[i]["base"]
			var b: Dictionary = Backpack.compute(grids[i])
			var h = heroes[i]
			h.set("base_max_hp", int(base["hp"]) + b["hp"])
			h.set("base_attack", int(base["atk"]) + b["atk"])
			h.set("base_defense", int(base["def"]) + b["def"])
			h.set("base_magic", int(base["magic"]) + b["magic"])
			h.set("base_speed", int(base["spd"]))
			h.set("base_mp", int(base["mp"]))
			h.stat_block.rebuild()
			h.current_hp = h.get_max_hp()
		var party: Party = Party.create(heroes, null, 0.4)
		for i in range(heroes.size()):
			party.set_row(heroes[i], bases[i]["row"])
		var result: BattleResult = BattleSimulator.simulate(party, _enemies())
		if result.party_won:
			wins += 1
	return wins

func test_smart_pack_beats_lazy_pack() -> void:
	# 巧搭：协同相邻 + 放对人（剑系给战士、法器给法师、生命/圣物给牧师）
	var good := [
		{ Vector2i(0,0): "iron_sword", Vector2i(1,0): "whetstone", Vector2i(2,0): "longsword",
		  Vector2i(0,1): "shield", Vector2i(1,1): "chainmail" },
		{ Vector2i(0,0): "staff", Vector2i(1,0): "tome" },
		{ Vector2i(0,0): "holy_symbol", Vector2i(0,1): "amulet", Vector2i(1,1): "charm" },
	]
	# 乱搭：同样的物品，但无相邻协同 + 放错人（法器丢给战士、剑丢给法师）
	var bad := [
		{ Vector2i(0,0): "staff", Vector2i(2,0): "tome", Vector2i(0,1): "holy_symbol" },
		{ Vector2i(0,0): "iron_sword", Vector2i(2,0): "longsword" },
		{ Vector2i(0,0): "shield", Vector2i(2,0): "chainmail", Vector2i(0,1): "amulet", Vector2i(2,1): "charm" },
	]
	var good_wins := _run(good)
	var bad_wins := _run(bad)
	gut.p("巧搭胜率 %d/%d  ←→  乱搭胜率 %d/%d" % [good_wins, TRIALS, bad_wins, TRIALS])
	assert_gt(good_wins, bad_wins, "巧搭（协同+放对人）应明显强于乱搭")
