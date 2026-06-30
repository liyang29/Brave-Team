class_name WarriorStrategy extends CombatStrategy

# ─────────────────────────────────────────────────────────────────────────────
# WarriorStrategy — 战士战斗策略
#
# 定位：近战坦克，高HP高防，吸引火力
# 目标选择：攻击血量最多的敌人（正面硬刚最硬的那个）
# 技能优先级（确定性，蓝够、转好就放）：
#   1. 前排 + 当前未在嘲讽 + 挑衅怒吼可放 → 拉仇立防（招牌技，CD 一到即放，不掷骰）
#   2. 敌人 ≥2 且横扫可放 → 横扫（AOE 才划算）
#   3. 斩击可放 → 斩击
#   4. 其它可放伤害技 → 放最强的；都不可放 → 普攻
# ─────────────────────────────────────────────────────────────────────────────

func choose_target(self_bc: BattleCombatant, opponents: Array) -> BattleCombatant:
	return _target_highest_hp(opponents)

func choose_skill(self_bc: BattleCombatant, hero_ref, allies: Array = [], opponents: Array = []) -> String:
	if hero_ref == null:
		return ""
	var skills = hero_ref.get("skills")
	if skills == null or skills.is_empty():
		return ""
	# 1. 前排拉仇（确定性）
	if self_bc.row == "front" and not self_bc.has_taunt() \
			and "taunt_roar" in skills and _is_castable(self_bc, "taunt_roar"):
		return "taunt_roar"
	# 2. 多敌才放横扫（AOE 单体不划算）
	if opponents.size() >= 2 and "cleave" in skills and _is_castable(self_bc, "cleave"):
		return "cleave"
	# 3. 单体首选斩击
	if "slash" in skills and _is_castable(self_bc, "slash"):
		return "slash"
	# 4. 兜底：其它可放伤害技里最强的（未来加战士攻击技不漏）
	return _strongest_castable_damage(self_bc, hero_ref)


# 连招条件门：嘲讽只在前排+未嘲讽时放；横扫只在敌≥2 时放；其余就绪即放。
func should_cast(skill_id: String, self_bc: BattleCombatant, _hero_ref, _allies: Array, opponents: Array) -> bool:
	match skill_id:
		"taunt_roar":
			return self_bc.row == "front" and not self_bc.has_taunt()
		"cleave":
			return opponents.size() >= 2
	return true
