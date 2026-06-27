class_name RogueStrategy extends CombatStrategy

# ─────────────────────────────────────────────────────────────────────────────
# RogueStrategy — 盗贼战斗策略
#
# 定位：敏捷单体，速度快，专注补刀
# 目标选择：攻击血量最少的敌人（优先击杀濒死目标，减少敌方战斗力）
# 技能使用：50% 概率使用技能（若目标血量低于 30% 则提升至 80% 以确保击杀）
# ─────────────────────────────────────────────────────────────────────────────

const SKILL_CHANCE_NORMAL:  float = 0.50
const SKILL_CHANCE_FINISHER: float = 0.80  # 目标濒死时大幅提升技能触发率

func choose_target(self_bc: BattleCombatant, opponents: Array) -> BattleCombatant:
	return _target_lowest_hp(opponents)

func choose_skill(self_bc: BattleCombatant, hero_ref, allies: Array = []) -> String:
	# 检查目标是否濒死（通过 choose_target 找到目标后判断）
	# 这里简化处理：直接检查自身上一次行动的目标不可得，
	# 改为统一按概率选技能，盗贼有两档概率
	# 实际"是否濒死"判断由 BattleSimulator 在调用前注入 context（待扩展）
	return _pick_skill_by_chance(hero_ref, SKILL_CHANCE_NORMAL)

# 补刀专用版本：BattleSimulator 检测到目标 HP < 30% 时调用此方法
func choose_skill_finisher(hero_ref) -> String:
	return _pick_skill_by_chance(hero_ref, SKILL_CHANCE_FINISHER)
