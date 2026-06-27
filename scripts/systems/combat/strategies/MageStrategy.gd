class_name MageStrategy extends CombatStrategy

# ─────────────────────────────────────────────────────────────────────────────
# MageStrategy — 法师战斗策略
#
# 定位：远程法术，高魔低防，消灭软目标
# 目标选择：攻击防御最低的敌人（找最容易穿透的目标）
# 技能使用：70% 概率释放魔法技能（法师的核心输出手段）
# ─────────────────────────────────────────────────────────────────────────────

const SKILL_CHANCE: float = 0.70

func choose_target(self_bc: BattleCombatant, opponents: Array) -> BattleCombatant:
	return _target_lowest_defense(opponents)

func choose_skill(self_bc: BattleCombatant, hero_ref, allies: Array = []) -> String:
	return _pick_skill_by_chance(hero_ref, SKILL_CHANCE)
