class_name PriestStrategy extends CombatStrategy

# ─────────────────────────────────────────────────────────────────────────────
# PriestStrategy — 牧师战斗策略
#
# 定位：神圣法术输出 + 队伍治疗，依赖蓝量，高蓝量高回蓝
# 目标选择：攻击血量最少的敌人（优先补刀）
# 技能优先级（确定性，蓝够、转好就放；条件优先 → 否则攻击）：
#   1. 友军中毒 → 净化
#   2. 队友 HP < 50% → 圣愈术
#   3. 自身 HP < 35% → 神圣祝福（立防求生）
#   4. 否则放可放的最强攻击技；都不可放 → 普攻
# ─────────────────────────────────────────────────────────────────────────────

const HEAL_THRESHOLD: float  = 0.50  # 队友 HP 低于此值时优先治疗

func choose_target(self_bc: BattleCombatant, opponents: Array) -> BattleCombatant:
	return _target_lowest_hp(opponents)

func choose_skill(self_bc: BattleCombatant, hero_ref, allies: Array = [], opponents: Array = []) -> String:
	if hero_ref == null:
		return ""
	var skills: Array = hero_ref.get("skills") if hero_ref.get("skills") else []
	if skills.is_empty():
		return ""

	# 优先级 0（方案 B）：友军中毒（身上有 DoT）且我会净化 → 立即净化（需可放）
	if "purify" in skills and _is_castable(self_bc, "purify"):
		for ally in allies:
			if not ally.is_alive():
				continue
			for eff in ally.active_effects:
				if eff.get("type") == "dot":
					return "purify"

	# 优先级 1：有队友血量低于阈值时施放圣愈术（需可放；冷却/缺蓝则跳过，不空放）
	if "holy_heal" in skills and _is_castable(self_bc, "holy_heal"):
		for ally in allies:
			if ally.is_alive() and ally.get_hp_percent() < HEAL_THRESHOLD:
				return "holy_heal"

	# 优先级 2：自身危险时先用祝福提升防御
	if "blessing" in skills and _is_castable(self_bc, "blessing") and self_bc.get_hp_percent() < 0.35:
		return "blessing"

	# 优先级 3：放可放的最强攻击技（确定性）；无 → 普攻
	return _strongest_castable_damage(self_bc, hero_ref)


# 连招条件门：治疗只在有人残血时放、净化只在有人中毒时放、祝福只在自身危急时放；
# 攻击技就绪即放。避免满血空放治疗等。
func should_cast(skill_id: String, self_bc: BattleCombatant, _hero_ref, allies: Array, _opponents: Array) -> bool:
	match skill_id:
		"holy_heal":
			for ally in allies:
				if ally.is_alive() and ally.get_hp_percent() < HEAL_THRESHOLD:
					return true
			return false
		"purify":
			for ally in allies:
				if not ally.is_alive():
					continue
				for eff in ally.active_effects:
					if eff.get("type") == "dot":
						return true
			return false
		"blessing":
			return self_bc.get_hp_percent() < 0.35
	return true
