class_name ColumnPiercerStrategy extends CombatStrategy

# ─────────────────────────────────────────────────────────────────────────────
# ColumnPiercerStrategy — 敌人AI：列穿刺手（方案 B 网格实验）
#
# 对应 EnemyData.AI_COLUMN_PIERCER
# 定位：后排远程，放「电浆穿刺」(plasma_pierce) 命中目标整列（前+后排，无视掩护）。
# 行为：专挑玩家**人数最多的那一列**下手 → 惩罚把单位堆在同一列。
# 解法：玩家需把队伍**分散到不同列**，别给穿刺手一锅端的机会。
# ─────────────────────────────────────────────────────────────────────────────

const PIERCE_CHANCE: float = 0.9

func choose_target(self_bc: BattleCombatant, opponents: Array) -> BattleCombatant:
	# 统计每列存活人数，选人数最多的列里的一个单位
	var by_col: Dictionary = {}
	for bc in opponents:
		by_col[bc.col] = by_col.get(bc.col, 0) + 1
	var best_col: int = opponents[0].col
	var best_n: int = -1
	for c in by_col:
		if by_col[c] > best_n:
			best_n = by_col[c]
			best_col = c
	for bc in opponents:
		if bc.col == best_col:
			return bc
	return opponents[0]

func choose_skill(self_bc: BattleCombatant, hero_ref, allies: Array = [], opponents: Array = []) -> String:
	if randf() < PIERCE_CHANCE:
		return "plasma_pierce"
	return ""
