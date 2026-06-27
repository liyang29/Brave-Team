class_name PriestStrategy extends CombatStrategy

# ─────────────────────────────────────────────────────────────────────────────
# PriestStrategy — 牧师战斗策略
#
# 定位：神圣法术输出 + 队伍治疗，依赖蓝量，高蓝量高回蓝
# 目标选择：攻击血量最少的敌人（优先补刀）
# 技能优先级：
#   1. 队伍有人 HP < 50% → 圣愈术（heal_ally，需有蓝量）
#   2. 自身 HP < 35% → 神圣祝福（提升防御求生）
#   3. 75% 概率释放攻击技能
#      攻击技能选择：divine_wrath 60% / holy_smite 40%（蓝量不足时降级）
#      若两者都没有则用 radiance（AOE）
# ─────────────────────────────────────────────────────────────────────────────

const SKILL_CHANCE: float    = 0.75
const HEAL_THRESHOLD: float  = 0.50  # 队友 HP 低于此值时优先治疗
const WRATH_BIAS: float      = 0.60  # 攻击时 60% 选神圣之怒，40% 选圣光击

func choose_target(self_bc: BattleCombatant, opponents: Array) -> BattleCombatant:
	return _target_lowest_hp(opponents)

func choose_skill(self_bc: BattleCombatant, hero_ref, allies: Array = []) -> String:
	if hero_ref == null:
		return ""
	var skills: Array = hero_ref.get("skills") if hero_ref.get("skills") else []
	if skills.is_empty():
		return ""

	# 优先级 0（方案 B）：友军中毒（身上有 DoT）且我会净化 → 立即净化
	if "purify" in skills:
		for ally in allies:
			if not ally.is_alive():
				continue
			for eff in ally.active_effects:
				if eff.get("type") == "dot":
					return "purify"

	# 优先级 1：有队友血量低于阈值时施放圣愈术
	if "holy_heal" in skills:
		for ally in allies:
			if ally.is_alive() and ally.get_hp_percent() < HEAL_THRESHOLD:
				return "holy_heal"

	# 优先级 2：自身危险时先用祝福提升防御
	if "blessing" in skills and self_bc.get_hp_percent() < 0.35:
		return "blessing"

	# 优先级 3：概率触发攻击技能
	if randf() > SKILL_CHANCE:
		return ""  # 普攻

	# 攻击技能：divine_wrath 与 holy_smite 随机轮换，避免永远只用高费技能
	var has_wrath:  bool = "divine_wrath" in skills
	var has_smite:  bool = "holy_smite"   in skills
	if has_wrath and has_smite:
		return "divine_wrath" if randf() < WRATH_BIAS else "holy_smite"
	if has_wrath:
		return "divine_wrath"
	if has_smite:
		return "holy_smite"
	if "radiance" in skills:
		return "radiance"

	return ""
