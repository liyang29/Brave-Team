class_name RogueStrategy extends CombatStrategy

# ─────────────────────────────────────────────────────────────────────────────
# RogueStrategy — 盗贼战斗策略
#
# 定位：敏捷单体，速度快，专注补刀
# 目标选择：攻击血量最少的敌人（优先击杀濒死目标，减少敌方战斗力）
# 技能走连招模型（继承基类 should_cast：纯伤害技就绪即放，无额外条件）。
# ─────────────────────────────────────────────────────────────────────────────

func choose_target(self_bc: BattleCombatant, opponents: Array) -> BattleCombatant:
	return _target_lowest_hp(opponents)
