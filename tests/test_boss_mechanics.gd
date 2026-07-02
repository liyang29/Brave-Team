extends GutTest

# ─────────────────────────────────────────────────────────────────────────────
# test_boss_mechanics.gd — Boss 通用机制测试
#
# 覆盖：
#   1. _apply_boss_config：开局注入（技能池/冷却/阶段表/召唤表 + 换 BossStrategy）
#   2. _check_boss_phase：阶段转换（阈值跃迁/连续跨阶/不满足不跃迁）
#   3. _check_boss_summons：召唤援军（按回合间隔/封顶/死亡跳过/非整除不召）
#   4. BossStrategy：选技（可放技能池随机、无可放退化空）/ 选目标（集火最脆）
#   5. EncounterData：3 个 Boss 档案数据完整性 + simulate() 端到端不崩
# ─────────────────────────────────────────────────────────────────────────────

const EncounterDataScript = preload("res://scripts/systems/combat/EncounterData.gd")


func _bc(hp: int = 100, atk: int = 20, def_val: int = 10, spd: int = 10, magic: int = 0) -> BattleCombatant:
	var bc = BattleCombatant.new()
	bc.source_name = "测试Boss"
	bc.current_hp  = hp
	bc.max_hp      = hp
	bc.attack      = atk
	bc.defense     = def_val
	bc.speed       = spd
	bc.magic       = magic
	return bc

func _enemy(hp: int = 200, atk: int = 20, def_val: int = 5, spd: int = 8) -> EnemyData:
	var e = EnemyData.new()
	e.entity_name  = "测试Boss"
	e.base_max_hp  = hp
	e.base_attack  = atk
	e.base_defense = def_val
	e.base_speed   = spd
	e.base_magic   = atk
	e.ai_type      = EnemyData.AI_BASIC_ATTACK
	return e

func _party(hp: int = 300, atk: int = 30, def_val: int = 10) -> Party:
	var hero = HeroFactory.create(Hero.HeroClass.WARRIOR)
	var sk = hero.get("skills")
	if sk != null:
		sk.clear()
	hero.base_max_hp  = hp
	hero.current_hp   = hp
	hero.base_attack  = atk
	hero.base_defense = def_val
	return Party.create([hero])


# ════════════════════════════════════════════════════════════════════════════
# 一、_apply_boss_config
# ════════════════════════════════════════════════════════════════════════════

func test_apply_boss_config_injects_fields_and_strategy() -> void:
	var enemy_bcs: Array = BattleSimulator._create_enemy_combatants([_enemy()])
	var config := {
		"boss_index": 0,
		"base_skills": ["boss_smash"],
		"skill_cds": { "boss_smash": 3 },
		"phases": [{ "hp_pct": 0.5, "atk_mult": 1.3, "extra_skills": [] }],
		"summons": [{ "every": 4, "group": ["venom_bug"], "max_total": 6 }],
	}
	BattleSimulator._apply_boss_config(enemy_bcs, config)
	var boss: BattleCombatant = enemy_bcs[0]
	assert_eq(boss.available_skills, ["boss_smash"], "开局技能池注入")
	assert_eq(boss.skill_cd_config, { "boss_smash": 3 }, "技能冷却配置注入")
	assert_eq(boss.boss_phases.size(), 1, "阶段表注入")
	assert_eq(boss.boss_summons.size(), 1, "召唤表注入")
	assert_true(boss.combat_strategy is BossStrategy, "策略被强制换为 BossStrategy")


func test_apply_boss_config_empty_is_noop() -> void:
	var enemy_bcs: Array = BattleSimulator._create_enemy_combatants([_enemy()])
	var original_strategy = enemy_bcs[0].combat_strategy
	BattleSimulator._apply_boss_config(enemy_bcs, {})
	assert_eq(enemy_bcs[0].available_skills.size(), 0, "空 boss_config 不注入技能池")
	assert_eq(enemy_bcs[0].combat_strategy, original_strategy, "空 boss_config 不改动策略（普通遭遇零影响）")


func test_apply_boss_config_out_of_range_index_warns_and_skips() -> void:
	var enemy_bcs: Array = BattleSimulator._create_enemy_combatants([_enemy()])
	BattleSimulator._apply_boss_config(enemy_bcs, { "boss_index": 5, "base_skills": ["x"] })
	assert_eq(enemy_bcs[0].available_skills.size(), 0, "越界 boss_index 不影响任何单位")


# ════════════════════════════════════════════════════════════════════════════
# 二、_check_boss_phase
# ════════════════════════════════════════════════════════════════════════════

func test_check_boss_phase_triggers_at_threshold() -> void:
	var boss = _bc(100, 20, 10)
	boss.current_hp = 40   # 40% ≤ 50% 阈值
	boss.boss_phases = [{ "hp_pct": 0.5, "atk_mult": 2.0, "extra_skills": ["new_skill"] }]
	var logs: Array = []
	BattleSimulator._check_boss_phase(boss, logs)
	assert_eq(boss.attack, 40, "atk_mult 生效：20×2.0=40")
	assert_true(boss.available_skills.has("new_skill"), "阶段解锁的新技能加入技能池")
	assert_eq(boss.boss_phase_index, 1, "跃迁到第 1 阶段")
	assert_eq(logs.size(), 1, "记录一条 boss_phase 日志")
	assert_eq(logs[0].skill_id, "boss_phase", "日志标记为 boss_phase")


func test_check_boss_phase_not_triggered_above_threshold() -> void:
	var boss = _bc(100, 20, 10)
	boss.current_hp = 80   # 80% > 50% 阈值，未跌破
	boss.boss_phases = [{ "hp_pct": 0.5, "atk_mult": 2.0, "extra_skills": [] }]
	var logs: Array = []
	BattleSimulator._check_boss_phase(boss, logs)
	assert_eq(boss.attack, 20, "未跌破阈值，属性不变")
	assert_eq(boss.boss_phase_index, 0, "未跃迁")
	assert_eq(logs.size(), 0, "无日志")


func test_check_boss_phase_cascades_multiple_thresholds() -> void:
	# 一次重创直接把血砸穿两个阈值 → 应连续跃迁，而不是一次只跳一阶
	var boss = _bc(100, 10, 0)
	boss.current_hp = 10   # 10%，穿透 60%/30% 两个阈值
	boss.boss_phases = [
		{ "hp_pct": 0.6, "atk_mult": 1.2, "extra_skills": ["a"] },
		{ "hp_pct": 0.3, "atk_mult": 1.3, "extra_skills": ["b"] },
	]
	var logs: Array = []
	BattleSimulator._check_boss_phase(boss, logs)
	assert_eq(boss.boss_phase_index, 2, "一次结算跨越两个阶段")
	assert_eq(boss.attack, 16, "两次倍率连续相乘：10×1.2=12(round)→12×1.3=15.6→round=16")
	assert_true(boss.available_skills.has("a") and boss.available_skills.has("b"), "两阶段技能都解锁")
	assert_eq(logs.size(), 2, "两条阶段转换日志")


func test_check_boss_phase_noop_on_unit_without_phases() -> void:
	var boss = _bc(100, 20, 10)
	boss.current_hp = 1
	var logs: Array = []
	BattleSimulator._check_boss_phase(boss, logs)
	assert_eq(logs.size(), 0, "boss_phases 为空 → 完全不触发（普通敌人零影响）")


# ════════════════════════════════════════════════════════════════════════════
# 三、_check_boss_summons
# ════════════════════════════════════════════════════════════════════════════

func test_check_boss_summons_spawns_on_interval() -> void:
	var boss = _bc()
	boss.boss_summons = [{ "every": 3, "group": ["wolf"], "max_total": 6 }]
	var logs: Array = []
	assert_eq(BattleSimulator._check_boss_summons([boss], 1, logs).size(), 0, "非整除回合不召唤")
	assert_eq(BattleSimulator._check_boss_summons([boss], 3, logs).size(), 1, "第 3 回合召唤 1 只")
	assert_eq(logs.size(), 1, "记录 boss_summon 日志")
	assert_eq(logs[0].skill_id, "boss_summon", "日志标记为 boss_summon")


func test_check_boss_summons_stops_at_max_total() -> void:
	var boss = _bc()
	boss.boss_summons = [{ "every": 2, "group": ["wolf"], "max_total": 2 }]
	var logs: Array = []
	assert_eq(BattleSimulator._check_boss_summons([boss], 2, logs).size(), 1, "第一波召 1")
	assert_eq(BattleSimulator._check_boss_summons([boss], 4, logs).size(), 1, "第二波召 1，累计达 2 上限")
	assert_eq(BattleSimulator._check_boss_summons([boss], 6, logs).size(), 0, "已达 max_total，第三波不再召唤")


func test_check_boss_summons_partial_wave_when_near_cap() -> void:
	# group 有 2 只，但只剩 1 个名额 → 只召一半，精确卡在 max_total
	var boss = _bc()
	boss.boss_summons = [{ "every": 2, "group": ["bandit", "ranger"], "max_total": 3 }]
	var logs: Array = []
	assert_eq(BattleSimulator._check_boss_summons([boss], 2, logs).size(), 2, "第一波召满 2 只")
	assert_eq(BattleSimulator._check_boss_summons([boss], 4, logs).size(), 1, "第二波名额只剩 1，部分召唤")
	assert_eq(BattleSimulator._check_boss_summons([boss], 6, logs).size(), 0, "已满，不再召唤")


func test_check_boss_summons_skips_dead_unit() -> void:
	var boss = _bc()
	boss.current_hp = 0   # 死亡
	boss.boss_summons = [{ "every": 1, "group": ["wolf"], "max_total": 6 }]
	var logs: Array = []
	assert_eq(BattleSimulator._check_boss_summons([boss], 1, logs).size(), 0, "死亡单位不召唤援军")


func test_check_boss_summons_noop_on_unit_without_summons() -> void:
	var boss = _bc()
	var logs: Array = []
	assert_eq(BattleSimulator._check_boss_summons([boss], 1, logs).size(), 0, "boss_summons 为空 → 完全不触发")


# ════════════════════════════════════════════════════════════════════════════
# 四、BossStrategy
# ════════════════════════════════════════════════════════════════════════════

func test_boss_strategy_choose_skill_picks_from_available_and_not_on_cooldown() -> void:
	var boss = _bc()
	boss.available_skills = ["boss_smash"]
	var strategy := BossStrategy.new()
	var chosen := strategy.choose_skill(boss, null)
	assert_eq(chosen, "boss_smash", "唯一可放技能被选中")


func test_boss_strategy_choose_skill_empty_when_all_on_cooldown() -> void:
	var boss = _bc()
	boss.available_skills = ["boss_smash"]
	boss.skill_cooldowns = { "boss_smash": 2 }
	var strategy := BossStrategy.new()
	assert_eq(strategy.choose_skill(boss, null), "", "全在冷却 → 退化为空（外层走普攻）")


func test_boss_strategy_choose_target_picks_lowest_hp() -> void:
	var low  = _bc(10, 20, 10)
	var high = _bc(90, 20, 10)
	var strategy := BossStrategy.new()
	var target := strategy.choose_target(_bc(), [high, low])
	assert_eq(target, low, "集火血量最低的目标")


# ════════════════════════════════════════════════════════════════════════════
# 五、EncounterData 数据 + simulate() 端到端
# ════════════════════════════════════════════════════════════════════════════

func test_encounter_data_has_three_mid_boss_layers() -> void:
	assert_true(EncounterDataScript.is_mid_boss_layer(20), "20 层是中程 Boss")
	assert_true(EncounterDataScript.is_mid_boss_layer(30), "30 层是中程 Boss")
	assert_true(EncounterDataScript.is_mid_boss_layer(40), "40 层是中程 Boss")
	assert_false(EncounterDataScript.is_mid_boss_layer(21), "非配置层不是中程 Boss")


func test_encounter_data_profiles_have_required_fields() -> void:
	for layer in [20, 30, 40]:
		var profile: Dictionary = EncounterDataScript.profile_for_layer(layer)
		assert_true(profile.has("name"), "layer %d 有 name" % layer)
		assert_true(profile.has("group") and not (profile["group"] as Array).is_empty(), "layer %d 有非空 group" % layer)
		var bc: Dictionary = profile.get("boss_config", {})
		assert_true(bc.has("base_skills") and not (bc["base_skills"] as Array).is_empty(), "layer %d boss_config 有 base_skills" % layer)


func test_simulate_with_boss_config_does_not_crash_and_uses_boss_strategy() -> void:
	var profile: Dictionary = EncounterDataScript.profile_for_layer(20)
	var enemies: Array = MonsterFactory.create_group(profile["group"])
	var party := _party(9999, 500, 50)   # 碾压向，保证战斗能在有限回合内结束
	var result: BattleResult = BattleSimulator.simulate(party, enemies, profile["boss_config"])
	assert_true(result is BattleResult, "带 boss_config 的战斗照常返回 BattleResult")
	assert_gt(result.turn_logs.size(), 0, "有行动日志")


func test_simulate_without_boss_config_is_backward_compatible() -> void:
	# 缺省第三参数：跟加 Boss 机制前的调用完全一致
	var party := _party()
	var enemies := [_enemy()]
	var result: BattleResult = BattleSimulator.simulate(party, enemies)
	assert_true(result is BattleResult, "省略 boss_config 参数仍正常工作")
