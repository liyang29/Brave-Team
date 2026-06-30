extends GutTest

# ─────────────────────────────────────────────────────────────────────────────
# test_battle_simulator.gd — BattleSimulator + BattleCombatant 完整测试
#
# 分三层覆盖：
#   1. BattleCombatant 单元测试（受击 / 治疗 / 状态效果 / 蓝量 / 护盾）
#   2. BattleSimulator._calc_damage（伤害公式：普通 / 无视防御 / 半甲）
#   3. BattleSimulator.simulate() 集成测试（胜负 / 死亡记录 / 结果结构）
# ─────────────────────────────────────────────────────────────────────────────

const BasicAttackStrategyScript = preload("res://scripts/systems/combat/strategies/BasicAttackStrategy.gd")


# ── 工具函数 ──────────────────────────────────────────────────────────────────

## 创建可直接操作的 BattleCombatant（无需 Hero / EnemyData）
func _bc(hp: int = 100, atk: int = 20, def_val: int = 10,
		 spd: int = 10, magic: int = 0, mp: int = 0) -> BattleCombatant:
	var bc          = BattleCombatant.new()
	bc.source_name  = "测试单位"
	bc.current_hp   = hp
	bc.max_hp       = hp
	bc.attack       = atk
	bc.defense      = def_val
	bc.speed        = spd
	bc.magic        = magic
	bc.current_mp   = mp
	bc.max_mp       = mp
	bc.mp_regen     = 0
	bc.combat_strategy = BasicAttackStrategyScript.new()
	return bc

## 创建属性可控的 EnemyData
func _enemy(hp: int = 50, atk: int = 10, def_val: int = 0,
			spd: int = 5) -> EnemyData:
	var e           = EnemyData.new()
	e.entity_name   = "测试敌人"
	e.base_max_hp   = hp
	e.base_attack   = atk
	e.base_defense  = def_val
	e.base_speed    = spd
	e.base_magic    = 0
	e.ai_type       = EnemyData.AI_BASIC_ATTACK
	return e

## 创建单英雄队伍（可手动覆盖基础属性）
func _party(hp: int = 200, atk: int = 50, def_val: int = 10) -> Party:
	var hero            = HeroFactory.create(Hero.HeroClass.WARRIOR)
	# 清空 HeroFactory 注入的随机技能：对齐真实跑局（技能只来自背包书），
	# 否则随机抽到 shield_bash 在确定性选技下会把敌人眩晕锁死，使结果测试随机不稳定。
	var sk = hero.get("skills")
	if sk != null:
		sk.clear()
	hero.base_max_hp    = hp
	hero.current_hp     = hp
	hero.base_attack    = atk
	hero.base_defense   = def_val
	return Party.create([hero], null, 0.4)


# ════════════════════════════════════════════════════════════════════════════
# 一、BattleCombatant — 受击与治疗
# ════════════════════════════════════════════════════════════════════════════

func test_take_damage_formula() -> void:
	# 公式：max(1, attack - defense / 2)
	# attack=20, defense=10 → 20 - 5 = 15
	var bc = _bc(100, 0, 10)
	var dmg = bc.take_damage(20)
	assert_eq(dmg, 15, "普攻伤害 = attack - defense/2")
	assert_eq(bc.current_hp, 85, "受击后 HP 应减少实际伤害量")


func test_take_damage_minimum_one() -> void:
	# 防御远超攻击时，保底 1 点伤害
	var bc = _bc(100, 0, 200)
	var dmg = bc.take_damage(5)
	assert_eq(dmg, 1, "伤害保底 1 点")


func test_take_damage_hp_floor_zero() -> void:
	# HP 不会降为负数
	var bc = _bc(10, 0, 0)
	bc.take_damage(999)
	assert_eq(bc.current_hp, 0, "HP 最低为 0，不会变为负数")
	assert_false(bc.is_alive(), "HP = 0 时单位应视为死亡")


func test_take_damage_raw_no_shield() -> void:
	# 无护盾时 take_damage_raw 直接扣血
	var bc = _bc(100, 0, 0)
	var actual = bc.take_damage_raw(30)
	assert_eq(actual, 30, "无护盾时 take_damage_raw 返回原始伤害")
	assert_eq(bc.current_hp, 70, "HP 正确扣减")


func test_take_damage_raw_shield_absorbs_all() -> void:
	# 护盾完全吸收伤害，HP 不变
	var bc = _bc(100, 0, 0)
	bc.apply_shield(50)
	var actual = bc.take_damage_raw(30)
	assert_eq(actual, 0, "护盾完全吸收时实际伤害为 0")
	assert_eq(bc.current_hp, 100, "HP 不应减少")


func test_take_damage_raw_shield_partial() -> void:
	# 护盾不足，剩余伤害穿透到 HP
	var bc = _bc(100, 0, 0)
	bc.apply_shield(10)
	var actual = bc.take_damage_raw(30)
	assert_eq(actual, 20, "护盾吸收 10，剩余 20 穿透")
	assert_eq(bc.current_hp, 80, "HP 扣减穿透部分")


func test_heal_restores_hp() -> void:
	var bc = _bc(100, 0, 0)
	bc.current_hp = 60
	var healed = bc.heal(20)
	assert_eq(healed, 20, "回血量正确")
	assert_eq(bc.current_hp, 80, "HP 正确恢复")


func test_heal_capped_at_max_hp() -> void:
	var bc = _bc(100, 0, 0)
	bc.current_hp = 90
	var healed = bc.heal(50)
	assert_eq(healed, 10, "回血不超过 max_hp，实际只回 10")
	assert_eq(bc.current_hp, 100, "HP 不超过上限")


# ════════════════════════════════════════════════════════════════════════════
# 二、BattleCombatant — 状态效果
# ════════════════════════════════════════════════════════════════════════════

# ── 眩晕 ──────────────────────────────────────────────────────────────────────

func test_apply_stun_makes_unit_stunned() -> void:
	var bc = _bc()
	bc.apply_stun(2)
	assert_true(bc.is_stunned(), "施加眩晕后单位应处于眩晕状态")


func test_stun_expires_after_tick() -> void:
	var bc = _bc()
	bc.apply_stun(1)
	bc.tick_effects()   # 递减一次 → turns 变为 0 → 移除
	assert_false(bc.is_stunned(), "tick_effects 后眩晕应解除")


func test_stun_not_stacked_takes_max() -> void:
	var bc = _bc()
	bc.apply_stun(3)
	bc.apply_stun(1)   # 再次施加较短的眩晕，应保留较大值
	var stun_eff = bc.active_effects.filter(func(e): return e.get("type") == "stun")
	assert_eq(stun_eff.size(), 1, "眩晕不叠加，只保留一条")
	assert_eq(stun_eff[0]["turns"], 3, "保留较长的眩晕时间")


# ── 减速 ──────────────────────────────────────────────────────────────────────

func test_apply_slow_reduces_speed() -> void:
	var bc = _bc(100, 20, 10, 20)  # speed=20
	bc.apply_slow(5, 2)
	assert_eq(bc.speed, 15, "减速 5 后速度应为 15")


func test_slow_expires_and_speed_restored() -> void:
	var bc = _bc(100, 20, 10, 20)
	bc.apply_slow(5, 2)
	bc.tick_effects()   # turns: 2→1
	assert_eq(bc.speed, 15, "减速尚未结束，速度仍为 15")
	bc.tick_effects()   # turns: 1→0 → 恢复
	assert_eq(bc.speed, 20, "减速结束后速度应完全恢复")


func test_slow_speed_minimum_one() -> void:
	# 减速量超过当前速度，速度不低于 1
	var bc = _bc(100, 20, 10, 3)   # speed=3
	bc.apply_slow(10, 2)
	assert_gte(bc.speed, 1, "减速后速度最低为 1")


# ── DoT（持续伤害）────────────────────────────────────────────────────────────

func test_apply_dot_tick_deals_damage() -> void:
	# DoT 伤害公式：max(1, dot_damage - defense/4)
	# defense=0 时实际伤害 = dot_damage
	var bc = _bc(100, 0, 0)
	bc.apply_dot(10, 3)
	var dealt = bc.tick_status()
	assert_gt(dealt, 0, "tick_status 应结算 DoT 伤害")
	assert_lt(bc.current_hp, 100, "DoT 应扣减 HP")


func test_dot_reduces_with_defense() -> void:
	# defense=40 → DoT 减免 defense/4 = 10
	# dot_damage=15, actual = max(1, 15 - 10) = 5
	var bc = _bc(100, 0, 40)
	bc.apply_dot(15, 1)
	var dealt = bc.tick_status()
	assert_eq(dealt, 5, "DoT 受防御 /4 减免")


func test_dot_expires_after_turns() -> void:
	var bc = _bc(100, 0, 0)
	bc.apply_dot(5, 2)
	bc.tick_status()   # turn 1
	bc.tick_status()   # turn 2 → DoT 结束
	var dealt = bc.tick_status()  # turn 3 → 应无 DoT
	assert_eq(dealt, 0, "DoT 应在指定回合后结束")
	assert_eq(bc.current_hp, 90, "DoT 共扣 5+5=10，剩余 90")


func test_dot_not_stacked_takes_max_damage() -> void:
	var bc = _bc(100, 0, 0)
	bc.apply_dot(5, 3)
	bc.apply_dot(10, 2)  # 更强的 DoT 覆盖
	var dot_effs = bc.active_effects.filter(func(e): return e.get("type") == "dot")
	assert_eq(dot_effs.size(), 1, "DoT 不叠加，只保留一条")
	assert_eq(dot_effs[0]["damage"], 10, "保留伤害更高的 DoT")


# ── Buff ──────────────────────────────────────────────────────────────────────

func test_apply_buff_increases_attack() -> void:
	var bc = _bc(100, 20, 0)
	bc.apply_buff("attack", 10, -1)
	assert_eq(bc.attack, 30, "Buff 应立即提升攻击力")


func test_permanent_buff_does_not_expire() -> void:
	var bc = _bc(100, 20, 0)
	bc.apply_buff("attack", 10, -1)  # turns=-1 = 永久
	bc.tick_effects()
	bc.tick_effects()
	assert_eq(bc.attack, 30, "永久 Buff（turns=-1）不过期")


func test_timed_buff_expires_and_restores() -> void:
	var bc = _bc(100, 20, 0)
	bc.apply_buff("attack", 10, 2)
	bc.tick_effects()   # turns: 2→1
	assert_eq(bc.attack, 30, "Buff 未过期，攻击仍为 30")
	bc.tick_effects()   # turns: 1→0 → 还原
	assert_eq(bc.attack, 20, "Buff 过期后攻击恢复原值")


func test_buff_defense_expires_and_restores() -> void:
	var bc = _bc(100, 0, 10)
	bc.apply_buff("defense", 5, 1)
	assert_eq(bc.defense, 15, "防御 Buff 生效")
	bc.tick_effects()
	assert_eq(bc.defense, 10, "防御 Buff 过期后还原")


# ════════════════════════════════════════════════════════════════════════════
# 三、BattleCombatant — 蓝量
# ════════════════════════════════════════════════════════════════════════════

func test_spend_mp_success() -> void:
	var bc = _bc(100, 0, 0, 10, 0, 50)  # mp=50
	var spent = bc.spend_mp(20)
	assert_eq(spent, 20, "消耗蓝量应返回实际消耗量")
	assert_eq(bc.current_mp, 30, "蓝量正确减少")


func test_spend_mp_insufficient_returns_minus1() -> void:
	var bc = _bc(100, 0, 0, 10, 0, 10)
	var result = bc.spend_mp(20)
	assert_eq(result, -1, "蓝量不足时应返回 -1")
	assert_eq(bc.current_mp, 10, "蓝量不足时不扣除")


func test_regen_mp_restores_correctly() -> void:
	var bc = _bc(100, 0, 0, 10, 0, 50)
	bc.current_mp = 30
	bc.regen_mp(15)
	assert_eq(bc.current_mp, 45, "回蓝正确")


func test_regen_mp_capped_at_max() -> void:
	var bc = _bc(100, 0, 0, 10, 0, 50)
	bc.current_mp = 45
	bc.regen_mp(100)
	assert_eq(bc.current_mp, 50, "回蓝不超过 max_mp")


func test_tick_status_regens_mp() -> void:
	var bc = _bc(100, 0, 0, 10, 0, 60)
	bc.current_mp = 0
	bc.mp_regen   = 10
	bc.tick_status()
	assert_eq(bc.current_mp, 10, "tick_status 应触发 MP 回蓝")


# ════════════════════════════════════════════════════════════════════════════
# 四、BattleSimulator._calc_damage — 伤害公式
# ════════════════════════════════════════════════════════════════════════════

func test_calc_damage_normal() -> void:
	# max(1, 20 - 10/2) = max(1, 15) = 15
	var target = _bc(100, 0, 10)
	var dmg = BattleSimulator._calc_damage(20, target, false, false)
	assert_eq(dmg, 15, "普通伤害公式：raw - defense/2")


func test_calc_damage_ignore_def() -> void:
	# 无视防御：max(1, 20 - 0) = 20
	var target = _bc(100, 0, 100)
	var dmg = BattleSimulator._calc_damage(20, target, true, false)
	assert_eq(dmg, 20, "ignore_def 时防御视为 0")


func test_calc_damage_half_def() -> void:
	# 半甲：defense=20 → eff_def=10 → max(1, 20 - 10/2) = max(1, 15) = 15
	var target = _bc(100, 0, 20)
	var dmg = BattleSimulator._calc_damage(20, target, false, true)
	assert_eq(dmg, 15, "half_def 时防御减半计算")


func test_calc_damage_minimum_one() -> void:
	# 超高防御时保底 1
	var target = _bc(100, 0, 10000)
	var dmg = BattleSimulator._calc_damage(1, target, false, false)
	assert_eq(dmg, 1, "伤害保底 1 点")


# ════════════════════════════════════════════════════════════════════════════
# 五、BattleSimulator.simulate() — 集成测试
# ════════════════════════════════════════════════════════════════════════════

func test_simulate_hero_wins_against_weak_enemy() -> void:
	# 极强英雄 vs 极弱敌人 → 胜利
	var party = _party(500, 999, 50)          # attack=999
	var enemies = [_enemy(1, 1, 0)]           # hp=1
	var result = BattleSimulator.simulate(party, enemies)
	assert_true(result.party_won, "碾压局应以胜利结束")


func test_simulate_heroes_lose_against_strong_enemy() -> void:
	# 极弱英雄 vs 极强敌人 → 失败
	var party = _party(1, 1, 0)              # hp=1
	var enemies = [_enemy(9999, 999, 0)]     # attack=999
	var result = BattleSimulator.simulate(party, enemies)
	assert_false(result.party_won, "劣势局应以失败结束")


func test_simulate_result_has_turn_logs() -> void:
	var party   = _party(500, 999, 50)
	var enemies = [_enemy(1, 1, 0)]
	var result  = BattleSimulator.simulate(party, enemies)
	assert_gt(result.turn_logs.size(), 0, "战斗结果应包含行动日志")


func test_simulate_victory_total_turns_positive() -> void:
	var party   = _party(500, 999, 50)
	var enemies = [_enemy(1, 1, 0)]
	var result  = BattleSimulator.simulate(party, enemies)
	assert_gt(result.total_turns, 0, "战斗应经过至少 1 回合")


func test_simulate_victory_surviving_hp_not_empty() -> void:
	# 胜利时应有存活英雄的 HP 快照
	var party   = _party(500, 999, 50)
	var enemies = [_enemy(1, 1, 0)]
	var result  = BattleSimulator.simulate(party, enemies)
	assert_gt(result.surviving_hp.size(), 0, "胜利时应有存活英雄 HP 快照")


func test_simulate_defeat_surviving_hp_empty() -> void:
	# 全灭时 surviving_hp 为空
	var party   = _party(1, 1, 0)
	var enemies = [_enemy(9999, 999, 0)]
	var result  = BattleSimulator.simulate(party, enemies)
	assert_eq(result.surviving_hp.size(), 0, "全灭时 surviving_hp 应为空")


func test_simulate_dead_hero_in_dead_heroes() -> void:
	# 阵亡英雄应出现在 dead_heroes 列表
	var party   = _party(1, 1, 0)
	var enemies = [_enemy(9999, 999, 0)]
	var result  = BattleSimulator.simulate(party, enemies)
	assert_eq(result.dead_heroes.size(), 1, "阵亡英雄应出现在 dead_heroes")


func test_simulate_victory_no_dead_heroes_when_no_casualties() -> void:
	# 无伤通关时 dead_heroes 应为空
	var party   = _party(9999, 999, 999)
	var enemies = [_enemy(1, 1, 0)]
	var result  = BattleSimulator.simulate(party, enemies)
	assert_eq(result.dead_heroes.size(), 0, "无伤胜利时 dead_heroes 应为空")


func test_simulate_has_casualties_when_hero_dies() -> void:
	var party   = _party(1, 1, 0)
	var enemies = [_enemy(9999, 999, 0)]
	var result  = BattleSimulator.simulate(party, enemies)
	assert_true(result.has_casualties(), "有英雄阵亡时 has_casualties 应为 true")


func test_simulate_no_casualties_when_all_survive() -> void:
	var party   = _party(9999, 999, 999)
	var enemies = [_enemy(1, 1, 0)]
	var result  = BattleSimulator.simulate(party, enemies)
	assert_false(result.has_casualties(), "无英雄阵亡时 has_casualties 应为 false")


func test_simulate_enemies_killed_count_on_victory() -> void:
	var party   = _party(500, 999, 50)
	var enemies = [_enemy(1, 1, 0), _enemy(1, 1, 0)]  # 2 个敌人
	var result  = BattleSimulator.simulate(party, enemies)
	assert_eq(result.enemies_killed, 2, "胜利时应记录全部敌人击杀数")


func test_simulate_multiple_heroes_vs_multiple_enemies() -> void:
	# 3 英雄 vs 3 敌人，验证多对多战斗不崩溃且返回合法结果
	var hero1 = HeroFactory.create(Hero.HeroClass.WARRIOR)
	var hero2 = HeroFactory.create(Hero.HeroClass.MAGE)
	var hero3 = HeroFactory.create(Hero.HeroClass.PRIEST)
	for h in [hero1, hero2, hero3]:
		h.base_max_hp  = 500
		h.current_hp   = 500
		h.base_attack  = 100
		h.base_defense = 20
	var party   = Party.create([hero1, hero2, hero3], null, 0.4)
	var enemies = [_enemy(30, 10, 0), _enemy(30, 10, 0), _enemy(30, 10, 0)]
	var result  = BattleSimulator.simulate(party, enemies)
	assert_not_null(result, "多对多战斗应返回非空结果")
	assert_true(result.party_won, "强英雄队应击败弱敌")
