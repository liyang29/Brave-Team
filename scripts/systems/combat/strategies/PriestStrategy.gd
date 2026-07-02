class_name PriestStrategy extends CombatStrategy

# ─────────────────────────────────────────────────────────────────────────────
# PriestStrategy — 牧师战斗策略
#
# 定位：神圣法术输出 + 队伍治疗，依赖蓝量，高蓝量高回蓝
# 目标选择：攻击血量最少的敌人（优先补刀）
# 技能走连招模型（_hero_combo_turn 按背包读序遍历，should_cast 只判"条件"）：
#   治疗只在有人残血时放、净化只在有人中毒时放、祝福只在自身危急时放；
#   攻击技就绪即放。避免满血空放治疗；优先级由背包摆放顺序决定，不是策略硬编码。
# ─────────────────────────────────────────────────────────────────────────────

const HEAL_THRESHOLD: float  = 0.50  # 队友 HP 低于此值时优先治疗

func choose_target(self_bc: BattleCombatant, opponents: Array) -> BattleCombatant:
	return _target_lowest_hp(opponents)


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
