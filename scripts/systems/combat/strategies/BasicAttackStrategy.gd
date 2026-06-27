class_name BasicAttackStrategy extends CombatStrategy

# ─────────────────────────────────────────────────────────────────────────────
# BasicAttackStrategy — 敌人AI：普通攻击型
#
# 对应 EnemyData.AI_BASIC_ATTACK
# 行为：只会普通攻击，目标是血量最多的英雄（正面碰撞）
# 适用：低级杂兵、野兽类敌人
# ─────────────────────────────────────────────────────────────────────────────

func choose_target(self_bc: BattleCombatant, opponents: Array) -> BattleCombatant:
	return _target_highest_hp(opponents)

# 不使用技能，永远普攻
func choose_skill(self_bc: BattleCombatant, hero_ref, allies: Array = []) -> String:
	return ""
