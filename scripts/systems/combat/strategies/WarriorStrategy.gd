class_name WarriorStrategy extends CombatStrategy

# ─────────────────────────────────────────────────────────────────────────────
# WarriorStrategy — 战士战斗策略
#
# 定位：近战坦克，高HP高防，吸引火力
# 目标选择：攻击血量最多的敌人（正面硬刚最硬的那个）
# 技能使用：30% 概率使用技能（偏物理爆发）
# ─────────────────────────────────────────────────────────────────────────────

const SKILL_CHANCE: float = 0.30

func choose_target(self_bc: BattleCombatant, opponents: Array) -> BattleCombatant:
	return _target_highest_hp(opponents)

func choose_skill(self_bc: BattleCombatant, hero_ref, allies: Array = []) -> String:
	return _pick_skill_by_chance(hero_ref, SKILL_CHANCE)
