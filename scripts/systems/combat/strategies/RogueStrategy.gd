class_name RogueStrategy extends CombatStrategy

# ─────────────────────────────────────────────────────────────────────────────
# RogueStrategy — 盗贼战斗策略
#
# 定位：敏捷单体，速度快，专注补刀
# 目标选择：攻击血量最少的敌人（优先击杀濒死目标，减少敌方战斗力）
# 技能使用：确定性——蓝够、转好就放最强技（盗贼目前无技能书，实际多为普攻）
# ─────────────────────────────────────────────────────────────────────────────

func choose_target(self_bc: BattleCombatant, opponents: Array) -> BattleCombatant:
	return _target_lowest_hp(opponents)

func choose_skill(self_bc: BattleCombatant, hero_ref, allies: Array = [], opponents: Array = []) -> String:
	return _strongest_castable_damage(self_bc, hero_ref)
