class_name ArcherStrategy extends CombatStrategy

# ─────────────────────────────────────────────────────────────────────────────
# ArcherStrategy — 弓手战斗策略
#
# 定位：远程物理，均衡输出，压制高威胁目标
# 目标选择：攻击攻击力最高的敌人（优先压制输出最强的威胁，保护队友）
# 技能走连招模型（继承基类 should_cast：纯伤害技就绪即放，无额外条件）。
# ─────────────────────────────────────────────────────────────────────────────

func choose_target(self_bc: BattleCombatant, opponents: Array) -> BattleCombatant:
	return _target_highest_attack(opponents)
