class_name BattleResult extends RefCounted

# ─────────────────────────────────────────────────────────────────────────────
# BattleResult — 一场战斗的完整结果记录
#
# BattleSimulator.simulate() 的返回值。
# 包含了后处理所需的全部信息：
#   - QuestManager 读取 party_won 判断任务成功/失败
#   - BattleUI 读取 turn_logs 顺序播放动画
#   - HeroManager 读取 dead_heroes 处理永久死亡
#   - InventoryManager 读取 loot 入库
#   - Hero 对象 current_hp 在战斗过程中已实时写回（via BattleCombatant）
#     surviving_hp 是冗余快照，供 UI 在结算界面显示
# ─────────────────────────────────────────────────────────────────────────────


# ── 字段 ──────────────────────────────────────────────────────────────────────

# 英雄队伍是否获胜
var party_won: bool = false

# 回合行动日志（按时间顺序排列，BattleUI 按序播放）
var turn_logs: Array = []  # Array[TurnLog]

# 本次战斗中阵亡的英雄列表（永久死亡，需要 HeroManager 处理）
var dead_heroes: Array = []  # Array[Hero]

# 战斗结束时存活英雄的剩余 HP 快照
# 注意：Hero 对象的 current_hp 在战斗过程中已实时写回，此字段为结算 UI 使用
# 格式：{ hero_instance_id: String → remaining_hp: int }
var surviving_hp: Dictionary = {}

# 战利品列表（已实例化的 Item 对象，准备入库）
var loot: Array = []  # Array[Item]

# 战斗持续回合数（统计用，可在结算界面显示）
var total_turns: int = 0

# 本次战斗击杀的敌人数量（胜利时 = 全部敌人，失败时 = 已击杀的敌人）
var enemies_killed: int = 0

# 本次战斗的经验奖励（按击败的敌人 exp_reward 累加；由存活英雄各自即时获得）
var exp_reward: int = 0

# 本次战斗掉落的金币（已 roll 定值；累积到队伍，回城并入总奖励分成）
var loot_gold: int = 0


# ── 工厂方法 ──────────────────────────────────────────────────────────────────

# 创建一个胜利结果
static func victory(
	p_logs:         Array,
	p_dead:         Array,
	p_surviving_hp: Dictionary,
	p_loot:         Array,
	p_turns:        int
) -> BattleResult:
	var result             = BattleResult.new()
	result.party_won       = true
	result.turn_logs       = p_logs
	result.dead_heroes     = p_dead
	result.surviving_hp    = p_surviving_hp
	result.loot            = p_loot
	result.total_turns     = p_turns
	return result

# 创建一个失败结果（全灭，无战利品）
static func defeat(
	p_logs:     Array,
	p_dead:     Array,
	p_turns:    int
) -> BattleResult:
	var result             = BattleResult.new()
	result.party_won       = false
	result.turn_logs       = p_logs
	result.dead_heroes     = p_dead
	result.surviving_hp    = {}   # 全灭，无存活
	result.loot            = []   # 失败无战利品（可按设计调整）
	result.total_turns     = p_turns
	return result


# ── 查询 ──────────────────────────────────────────────────────────────────────

# 是否有英雄阵亡（胜利也可能有伤亡）
func has_casualties() -> bool:
	return not dead_heroes.is_empty()

# 获取存活英雄数量（从 surviving_hp 推断）
func surviving_count() -> int:
	return surviving_hp.size()
