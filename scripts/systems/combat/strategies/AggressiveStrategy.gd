class_name AggressiveStrategy extends CombatStrategy

# ─────────────────────────────────────────────────────────────────────────────
# AggressiveStrategy — 敌人AI：凶猛型
#
# 对应 EnemyData.AI_AGGRESSIVE
# 行为：专门攻击血量最少的英雄，一个一个击杀，快速减少敌方人数
# 适用：狼群、刺客类敌人，让玩家感受到被集火的压力
# ─────────────────────────────────────────────────────────────────────────────

const SKILL_CHANCE: float = 0.25  # 偶尔使用技能增加变数

func choose_target(self_bc: BattleCombatant, opponents: Array) -> BattleCombatant:
	return _target_lowest_hp(opponents)

func choose_skill(self_bc: BattleCombatant, hero_ref, allies: Array = [], opponents: Array = []) -> String:
	# 敌人没有 hero_ref（传 null），_pick_skill_by_chance 会返回空字符串
	# 这里留着接口，将来敌人技能系统完善后可扩展
	return ""
