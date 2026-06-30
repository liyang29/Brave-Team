extends GutTest

# ─────────────────────────────────────────────────────────────────────────────
# test_backpack_experiment — 背包脏实验：协同计算 + "巧搭 vs 乱搭"验证
#
# 命题：同一批物品，[摆出邻接协同 + 放对人] 明显强于 [无协同 + 放错人]。
# 同时锁定 BackpackModel.compute 的邻接协同计算。
# ─────────────────────────────────────────────────────────────────────────────

const Backpack = preload("res://scripts/systems/backpack/BackpackModel.gd")
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


# ── 小队第二档：闪避 / 嘲讽（"闪避T"套件）─────────────────────────────────────

func test_dodge_taunt_extra_in_compute() -> void:
	# 对着数据表算期望值，验证 compute 累加逻辑（不锁死具体数值，便于后续平衡微调）
	var grid := { Vector2i(0,0): "shadow_mantle", Vector2i(1,0): "provoke_charm" }
	var b := Backpack.compute(grid)
	var exp_dodge := float(Backpack.ITEMS["shadow_mantle"].get("dodge_chance", 0.0))
	var exp_def := int(Backpack.ITEMS["shadow_mantle"].get("def", 0)) + int(Backpack.ITEMS["provoke_charm"].get("def", 0))
	assert_almost_eq(float(b["extra"].get("dodge_chance", 0.0)), exp_dodge, 0.001, "闪避累加 = 暗影披风的 dodge_chance")
	assert_eq(int(b["extra"].get("taunt", 0)), 1, "挑衅护符给嘲讽 taunt")
	assert_eq(b["def"], exp_def, "防御累加 = 两件 def 之和")


func test_dodge_chance_clamped() -> void:
	var bc := BattleCombatant.new()
	bc.extra_stats = { "dodge_chance": 1.0 }
	assert_almost_eq(BattleSimulator._dodge_chance(bc), BattleSimulator.DODGE_CAP, 0.001,
		"闪避率 clamp 到上限 %.2f" % BattleSimulator.DODGE_CAP)
	var none := BattleCombatant.new()
	assert_eq(BattleSimulator._dodge_chance(none), 0.0, "无闪避属性 → 0（旧战斗不变）")


func test_dodge_nullifies_damage() -> void:
	# 随机性：固定随机种子，统计 200 次普攻；闪避必 0 伤、未闪必正常掉血
	seed(20240629)
	var atk := BattleCombatant.new()
	atk.attack = 20
	var tgt := BattleCombatant.new()
	tgt.defense = 0
	tgt.extra_stats = { "dodge_chance": 0.6 }
	var dodges := 0
	var hits := 0
	for i in range(200):
		tgt.current_hp = 100
		tgt.max_hp = 100
		var logs: Array = BattleSimulator._basic_attack(atk, tgt, "reach")
		if logs[0].skill_id == "dodge":
			dodges += 1
			assert_eq(logs[0].damage, 0, "闪避日志伤害为 0")
			assert_eq(tgt.current_hp, 100, "闪避时不掉血")
		else:
			hits += 1
			assert_between(tgt.current_hp, 78, 82, "未闪避正常掉血≈20（含±10%浮动）")
	assert_gt(dodges, 0, "0.6 闪避率应触发若干次闪避")
	assert_gt(hits, 0, "也应有未闪避的命中")


func test_taunt_item_redirects_targeting() -> void:
	var taunter := BattleCombatant.new()
	taunter.source_name = "坦克"
	taunter.extra_stats = { "taunt": 1 }
	var squishy := BattleCombatant.new()
	squishy.source_name = "脆皮"
	# 顺序故意把脆皮放前面，验证嘲讽优先级而非数组顺序
	var picked = BattleSimulator._find_taunt_target([squishy, taunter])
	assert_eq(picked, taunter, "带嘲讽副属性的单位被优先锁定（吸火力保后排）")


func test_no_taunt_returns_null() -> void:
	var a := BattleCombatant.new()
	var b := BattleCombatant.new()
	assert_null(BattleSimulator._find_taunt_target([a, b]), "无嘲讽 → null（旧行为不变）")


func test_taunt_book_is_warrior_skill() -> void:
	assert_eq(SkillTable.get_skill("taunt_roar").get("hero_class", ""), "warrior", "挑衅怒吼认战士")
	assert_eq(Backpack.ITEMS["book_taunt"]["skill_id"], "taunt_roar", "挑衅书指向 taunt_roar")


func test_taunt_skill_applies_temp_taunt() -> void:
	var w := BattleCombatant.new()
	w.row = "front"
	w.max_mp = 50; w.current_mp = 50
	assert_false(w.has_taunt(), "施放前无嘲讽")
	var logs: Array = BattleSimulator._execute_action(w, "taunt_roar", w, [w], [w], [w], "soft_row")
	assert_true(w.has_taunt(), "挑衅怒吼后获得临时嘲讽")
	assert_eq(logs[0].skill_id, "taunt_roar", "记一条挑衅怒吼日志")
	# 前排施放 → 可被锁定
	assert_eq(BattleSimulator._find_taunt_target([w]), w, "施放后被敌人优先锁定")


func test_taunt_skill_expires_after_turns() -> void:
	var w := BattleCombatant.new()
	w.apply_taunt(2)
	assert_true(w.has_taunt(), "嘲讽生效中(2回合)")
	w.tick_effects()   # 2→1
	assert_true(w.has_taunt(), "过1回合仍在")
	w.tick_effects()   # 1→0 解除
	assert_false(w.has_taunt(), "2回合后嘲讽到期解除")


func test_taunt_only_works_in_front_row() -> void:
	# 嘲讽=「站出来挡」：后排嘲讽件失效，移到前排才重新生效
	var taunter := BattleCombatant.new()
	taunter.source_name = "坦克"
	taunter.extra_stats = { "taunt": 1 }
	var bystander := BattleCombatant.new()
	bystander.source_name = "前排"
	bystander.row = "front"

	taunter.row = "back"
	assert_null(BattleSimulator._find_taunt_target([taunter, bystander]),
		"后排嘲讽失效 → null（交回 AI 正常选目标，后排不再既减伤又吸火力）")

	taunter.row = "front"
	assert_eq(BattleSimulator._find_taunt_target([taunter, bystander]), taunter,
		"嘲讽位站前排 → 重新被优先锁定")


# ── 选技：确定性 + 只在可放池里挑（替掉纯随机，CD 不再浪费出技骰子）──────────

func test_castable_skills_excludes_cd_and_low_mp() -> void:
	var hero := _hero(Hero.HeroClass.WARRIOR, ["slash", "cleave"])   # slash 蓝10 / cleave 蓝30
	var strat := WarriorStrategy.new()
	var w := BattleCombatant.new()
	w.max_mp = 100; w.current_mp = 100
	var pool := strat._castable_skills(w, hero)
	assert_true("slash" in pool and "cleave" in pool, "满蓝无冷却 → 两个都可放")
	# 冷却中的被排除
	w.skill_cd_config = { "cleave": 2 }
	w.trigger_skill_cooldown("cleave")
	assert_false("cleave" in strat._castable_skills(w, hero), "冷却中的不在可放池")
	# 蓝量不足的被排除
	w.skill_cooldowns = {}
	w.current_mp = 12   # 够 slash(10) 不够 cleave(30)
	var pool2 := strat._castable_skills(w, hero)
	assert_true("slash" in pool2, "蓝够 → slash 可放")
	assert_false("cleave" in pool2, "蓝不够 → cleave 不可放")


func test_skill_never_returns_on_cooldown() -> void:
	# 核心修复：选技绝不返回冷却中的技能（旧版会抽中后浪费成普攻）
	var hero := _hero(Hero.HeroClass.MAGE, ["fireball", "ice_lance"])
	var strat := MageStrategy.new()
	var m := BattleCombatant.new()
	m.max_mp = 100; m.current_mp = 100
	m.skill_cd_config = { "fireball": 2, "ice_lance": 2 }
	m.trigger_skill_cooldown("fireball")
	m.trigger_skill_cooldown("ice_lance")
	for i in range(50):
		assert_eq(strat.choose_skill(m, hero, []), "", "技能全在冷却 → 只普攻，绝不返回冷却技能")


func test_warrior_prioritizes_taunt_when_front() -> void:
	var hero := _hero(Hero.HeroClass.WARRIOR, ["taunt_roar", "slash", "cleave"])
	var strat := WarriorStrategy.new()
	var w := BattleCombatant.new()
	w.row = "front"; w.max_mp = 50; w.current_mp = 50
	# 确定性：前排 + 未在嘲讽 + 挑衅可放 → 必出挑衅怒吼
	assert_eq(strat.choose_skill(w, hero, []), "taunt_roar", "前排战士确定性优先拉仇")
	# 已在嘲讽中 → 不重复拉仇（转去概率攻击或普攻，绝不再返回 taunt_roar）
	w.apply_taunt(2)
	for i in range(30):
		assert_ne(strat.choose_skill(w, hero, []), "taunt_roar", "已在嘲讽中不重复拉仇")


func test_hero_skill_is_deterministic_strongest() -> void:
	# 确定性：可放时必出最强伤害技（火球 2.0 > 冰枪 1.5），不再掷骰
	var hero := _hero(Hero.HeroClass.MAGE, ["fireball", "ice_lance"])
	var strat := MageStrategy.new()
	var m := BattleCombatant.new()
	m.max_mp = 100; m.current_mp = 100
	for i in range(20):
		assert_eq(strat.choose_skill(m, hero, [], []), "fireball", "可放时必出最强(火球)")
	# 火球进冷却 → 退而求其次放冰枪
	m.skill_cd_config = { "fireball": 2 }
	m.trigger_skill_cooldown("fireball")
	assert_eq(strat.choose_skill(m, hero, [], []), "ice_lance", "火球冷却 → 放冰枪")


func test_warrior_cleave_when_multiple_enemies() -> void:
	# 不带挑衅书 → 跳过拉仇，直接看攻击优先级：敌≥2 横扫 / 单体斩击
	var hero := _hero(Hero.HeroClass.WARRIOR, ["slash", "cleave"])
	var strat := WarriorStrategy.new()
	var w := BattleCombatant.new()
	w.row = "front"; w.max_mp = 100; w.current_mp = 100
	var e1 := BattleCombatant.new()
	var e2 := BattleCombatant.new()
	assert_eq(strat.choose_skill(w, hero, [], [e1, e2]), "cleave", "敌≥2 → 横扫")
	assert_eq(strat.choose_skill(w, hero, [], [e1]), "slash", "单敌 → 斩击")


func test_aura_scope_note_self_inclusion() -> void:
	# team/同排 必含自己；绝对前/后排 是"持有者站那排才含自己"（修 tooltip 误导）
	assert_true(Backpack.aura_scope_note("team").contains("含自己"), "team 必含自己")
	assert_true(Backpack.aura_scope_note("same_row").contains("含自己"), "同排必含自己")
	assert_true(Backpack.aura_scope_note("back_row").contains("才含自己"), "后排=条件含自己")
	assert_true(Backpack.aura_scope_note("front_row").contains("才含自己"), "前排=条件含自己")
	# 守护图腾(back_row) tooltip 应标清"给后排 + 条件含自己"，不再无条件"含自己"
	var tip := Backpack.item_tooltip("ward_totem")
	assert_true(tip.contains("后排") and tip.contains("才含自己"), "守护图腾 tooltip 不再误导")


func test_books_sorted_by_reading_order() -> void:
	# 技能书按"读序"(上→下，每行左→右)排列 → 决定连招释放顺序
	var grid := {
		Vector2i(1, 0): "book_cleave",   # 第0行 col1
		Vector2i(0, 0): "book_slash",    # 第0行 col0（读序最前）
		Vector2i(0, 1): "book_taunt",    # 第1行 col0（读序最后）
	}
	var b := Backpack.compute(grid)
	var ids: Array = b["books"].map(func(bk): return bk["id"])
	assert_eq(ids, ["slash", "cleave", "taunt_roar"], "读序：(0,0)→(1,0)→(0,1)")


func test_combo_fires_multiple_skills_in_one_turn() -> void:
	# 中间档：一个英雄回合内按摆放顺序连放所有就绪技能
	var hero := _hero(Hero.HeroClass.WARRIOR, ["slash", "shield_bash"])
	var w := BattleCombatant.from_hero(hero)
	w.row = "front"
	w.max_mp = 100; w.current_mp = 100
	w.skill_cd_config = {}   # 无书冷却 → 两技能都就绪
	var e := BattleCombatant.new()
	e.source_name = "敌"; e.current_hp = 500; e.max_hp = 500; e.row = "front"
	var logs: Array = []
	BattleSimulator._hero_combo_turn(w, hero, [w], [e], "soft_row", logs)
	var skill_logs: Array = logs.filter(func(l): return l.skill_id in ["slash", "shield_bash"])
	assert_eq(skill_logs.size(), 2, "一回合连放 slash + shield_bash 两个技能（连招）")


func test_combo_basic_attack_when_no_skill_ready() -> void:
	# 技能全在冷却 → 退化为一次普攻（技能替代普攻的反面）
	var hero := _hero(Hero.HeroClass.WARRIOR, ["slash"])
	var w := BattleCombatant.from_hero(hero)
	w.row = "front"; w.attack = 20; w.max_mp = 100; w.current_mp = 100
	w.skill_cd_config = { "slash": 2 }
	w.trigger_skill_cooldown("slash")   # slash 冷却中
	var e := BattleCombatant.new()
	e.source_name = "敌"; e.current_hp = 500; e.max_hp = 500; e.row = "front"; e.defense = 0
	var logs: Array = []
	BattleSimulator._hero_combo_turn(w, hero, [w], [e], "soft_row", logs)
	assert_eq(logs.size(), 1, "无就绪技能 → 只一次行动")
	assert_true(logs[0].skill_id.is_empty(), "且是普攻（skill_id 空）")


func test_warrior_back_row_never_taunts() -> void:
	var hero := _hero(Hero.HeroClass.WARRIOR, ["taunt_roar"])   # 只带挑衅书
	var strat := WarriorStrategy.new()
	var w := BattleCombatant.new()
	w.row = "back"; w.max_mp = 50; w.current_mp = 50
	# 后排拉仇无效 → 跳过；攻击池里也没伤害技 → 只会普攻，绝不空放挑衅
	for i in range(30):
		assert_eq(strat.choose_skill(w, hero, []), "", "后排战士不放挑衅怒吼（拉仇无效）")


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
	assert_between(logs[0].damage, 6, 8, "后排普攻打后排：20×0.5×0.7≈7（含站位修正±浮动）")
	tgt.current_hp = 100
	var logs2: Array = BattleSimulator._basic_attack(atk, tgt, "reach")
	assert_between(logs2[0].damage, 18, 22, "reach 模式普攻不受站位影响≈20（±浮动）")


func test_basic_attack_uses_higher_of_atk_magic() -> void:
	# 法师/牧师式单位：魔 > 攻 → 普攻用魔力，且按魔法不吃后排站位减伤
	var caster := BattleCombatant.new()
	caster.attack = 3; caster.magic = 12; caster.row = "back"
	var tgt := BattleCombatant.new()
	tgt.defense = 0; tgt.row = "front"; tgt.current_hp = 200; tgt.max_hp = 200
	var logs: Array = BattleSimulator._basic_attack(caster, tgt, "soft_row")
	# 用魔力12（非攻3），后排发起但按魔法不吃 ×0.5 → ≈12（±浮动）；攻3×0.5 才是旧的软普攻
	assert_between(logs[0].damage, 10, 14, "普攻取更高的魔力12，按魔法不吃后排减伤")


func test_basic_attack_physical_when_atk_higher() -> void:
	# 战士式：攻 > 魔 → 普攻按物理，后排发起吃 ×0.5
	var fighter := BattleCombatant.new()
	fighter.attack = 20; fighter.magic = 0; fighter.row = "back"
	var tgt := BattleCombatant.new()
	tgt.defense = 0; tgt.row = "front"; tgt.current_hp = 200; tgt.max_hp = 200
	var logs: Array = BattleSimulator._basic_attack(fighter, tgt, "soft_row")
	assert_between(logs[0].damage, 9, 11, "攻20后排物理普攻 ×0.5 ≈10（±浮动）")


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
	assert_between(logs[0].damage, 6, 8, "未知技能回退普攻同样吃站位修正≈7（不再打满 20，±浮动）")


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
