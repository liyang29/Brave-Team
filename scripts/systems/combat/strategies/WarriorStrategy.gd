class_name WarriorStrategy extends CombatStrategy

# ─────────────────────────────────────────────────────────────────────────────
# WarriorStrategy — 战士战斗策略
#
# 定位：近战坦克，高HP高防，吸引火力
# 目标选择：攻击血量最多的敌人（正面硬刚最硬的那个）
# 技能走连招模型（_hero_combo_turn 按背包读序遍历，should_cast 只判"条件"）：
#   嘲讽只在前排+未嘲讽时放；横扫只在敌≥2 时放；其余（如斩击）就绪即放。
#   优先级由玩家的背包摆放顺序决定，不是策略硬编码。
# ─────────────────────────────────────────────────────────────────────────────

func choose_target(self_bc: BattleCombatant, opponents: Array) -> BattleCombatant:
	return _target_highest_hp(opponents)


# 连招条件门：嘲讽只在前排+未嘲讽时放；横扫只在敌≥2 时放；其余就绪即放。
func should_cast(skill_id: String, self_bc: BattleCombatant, _hero_ref, _allies: Array, opponents: Array) -> bool:
	match skill_id:
		"taunt_roar":
			return self_bc.row == "front" and not self_bc.has_taunt()
		"cleave":
			return opponents.size() >= 2
	return true
