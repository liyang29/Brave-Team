class_name ArcherStrategy extends CombatStrategy

# ─────────────────────────────────────────────────────────────────────────────
# ArcherStrategy — 弓手战斗策略
#
# 定位：远程物理，均衡输出，压制高威胁目标
# 目标选择：攻击攻击力最高的敌人（优先压制输出最强的威胁，保护队友）
# 技能使用：40% 概率使用技能（区别于法师魔法，弓手使用物理远程技能）
# ─────────────────────────────────────────────────────────────────────────────

func choose_target(self_bc: BattleCombatant, opponents: Array) -> BattleCombatant:
	return _target_highest_attack(opponents)

# 确定性：蓝够、转好就放最强射击技；都不可放 → 普攻
func choose_skill(self_bc: BattleCombatant, hero_ref, allies: Array = [], opponents: Array = []) -> String:
	return _strongest_castable_damage(self_bc, hero_ref)
