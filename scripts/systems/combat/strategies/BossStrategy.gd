class_name BossStrategy extends CombatStrategy

# ─────────────────────────────────────────────────────────────────────────────
# BossStrategy — 中程/终点 Boss 的战斗策略
#
# 跟其它敌人策略的唯一区别：选技不是"固定几选一的硬编码优先级"，而是从
# self_bc.available_skills（会随阶段转换动态变大，见 BattleSimulator._check_boss_phase）
# 里挑一个当前可放（不在冷却）的技能。敌人侧保持"不可预测"传统（不像英雄连招那样
# 确定性），可放技能里随机挑一个；一个都不可放就普攻。
#
# 由 BattleSimulator._apply_boss_config 在战斗开局时强制赋给 Boss 单位（覆盖
# EnemyAIFactory 按 ai_type 给的默认策略），不走 EnemyAIFactory.create() 注册。
# ─────────────────────────────────────────────────────────────────────────────

func choose_target(self_bc: BattleCombatant, opponents: Array) -> BattleCombatant:
	return _target_lowest_hp(opponents)   # 集火最脆的，制造真实压力

func choose_skill(self_bc: BattleCombatant, hero_ref, allies: Array = [], opponents: Array = []) -> String:
	var castable: Array = self_bc.available_skills.filter(
		func(sid): return not self_bc.is_skill_on_cooldown(sid))
	if castable.is_empty():
		return ""
	return castable[randi() % castable.size()]
