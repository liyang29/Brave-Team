class_name TankStrategy extends CombatStrategy

# ─────────────────────────────────────────────────────────────────────────────
# TankStrategy — 敌人AI：坦克型
#
# 对应 EnemyData.AI_TANK
# 行为：
#   1. 嘲讽（Taunt）：自身作为优先攻击目标（玩家的英雄会被这个怪吸引）
#      注意：嘲讽效果实现在 BattleSimulator 里——Simulator 检测到对方队伍里
#      有 TankStrategy 的单位时，choose_target 对英雄无效，强制攻击坦克。
#      此处 choose_target 是坦克自己攻击谁。
#   2. 攻击目标：血量最多的英雄（和战士一样正面硬刚）
#
# 适用：精英敌人的护卫、Boss 的坦克卫兵
# ─────────────────────────────────────────────────────────────────────────────

# 标记此策略具有嘲讽属性，BattleSimulator 检测此常量决定是否启用嘲讽逻辑
const HAS_TAUNT: bool = true

func choose_target(self_bc: BattleCombatant, opponents: Array) -> BattleCombatant:
	return _target_highest_hp(opponents)

func choose_skill(self_bc: BattleCombatant, hero_ref, allies: Array = []) -> String:
	return ""  # 坦克不使用技能，专注吸收伤害
