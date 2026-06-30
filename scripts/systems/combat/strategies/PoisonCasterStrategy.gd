class_name PoisonCasterStrategy extends CombatStrategy

# ─────────────────────────────────────────────────────────────────────────────
# PoisonCasterStrategy — 敌人AI：剧毒术士（方案 B 编队解谜实验）
#
# 对应 EnemyData.AI_POISON_CASTER
# 定位：脆皮后排，靠「毒液弹」对玩家持续放毒（DoT），是这道遭遇谜题的核心威胁。
# 解法：玩家需带远程/突袭单位越过敌方前排点掉它，或带牧师净化撑过去。
#
# 行为：
#   - 选目标：防御最低的英雄（找软目标）
#   - 技能：高概率放 venom_bolt（带 DoT），否则普攻
# ─────────────────────────────────────────────────────────────────────────────

const VENOM_CHANCE: float = 0.85

func choose_target(self_bc: BattleCombatant, opponents: Array) -> BattleCombatant:
	return _target_lowest_defense(opponents)

func choose_skill(self_bc: BattleCombatant, hero_ref, allies: Array = [], opponents: Array = []) -> String:
	if randf() < VENOM_CHANCE:
		return "venom_bolt"
	return ""
