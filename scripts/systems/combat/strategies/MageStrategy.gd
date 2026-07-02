class_name MageStrategy extends CombatStrategy

# ─────────────────────────────────────────────────────────────────────────────
# MageStrategy — 法师战斗策略
#
# 定位：远程法术，高魔低防，消灭软目标
# 目标选择：攻击防御最低的敌人（找最容易穿透的目标）
# 技能走连招模型（继承基类 should_cast：纯伤害技就绪即放，无额外条件）。
# ─────────────────────────────────────────────────────────────────────────────

func choose_target(self_bc: BattleCombatant, opponents: Array) -> BattleCombatant:
	return _target_lowest_defense(opponents)
