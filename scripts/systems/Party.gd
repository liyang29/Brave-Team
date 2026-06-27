class_name Party extends RefCounted

# ─────────────────────────────────────────────────────────────────────────────
# Party — 临时队伍（运行时对象）
#
# 生命周期：从玩家确认派遣 → 任务结束队伍解散
# 继承 RefCounted：任务结束后没有任何引用，自动被 GC 回收，不占内存
#
# 注意：Party 不是 Resource，不需要存档。
#   如果游戏关闭时有进行中的任务，DataManager 存档时保存任务状态，
#   读档时由 QuestManager 重建 Party 对象。
# ─────────────────────────────────────────────────────────────────────────────


# ── 字段 ──────────────────────────────────────────────────────────────────────

# 参与任务的英雄列表（任务期间这些英雄状态为 ON_QUEST）
var heroes: Array = []  # Array[Hero]

# 关联的任务（不加类型避免与 Quest.gd 循环引用）
# 由 QuestManager.dispatch_party() 在创建 Party 时赋值
var quest = null  # Quest 实例

# 队伍共享的消耗品（玩家在派遣前分配给整个队伍，区别于英雄个人携带的）
# 例如：火把（探索专用）、解毒剂（整队可用）
# 格式：Array[Consumable]
var shared_consumables: Array = []  # Array[Consumable]

# 当前所在的地图格子坐标（六边形轴坐标，HeroAI 移动时持续更新）
var current_tile: Vector3i = Vector3i.ZERO

# 分成比例快照（派遣时从 GuildManager 读取，锁定为任务开始时的比例）
# 任务途中玩家调整分成不影响本次任务的结算
# 范围：0.0~1.0，表示英雄一方总共得到的比例（剩余归公会）
# 示例：0.4 表示英雄拿 40%，公会拿 60%
var hero_share_ratio: float = 0.4

# ── 站位编队（方案 B：小网格站位制）──────────────────────────────────────────
# formation       : { hero.instance_id: "front"/"back" } —— 仅排位（2 排兼容路径）
# formation_cell  : { hero.instance_id: Vector2i(col, row_index) } —— 网格格位
#                   row_index: 0=前排, 1=后排。优先于 formation。
# 玩家在编队界面分配；BattleSimulator 据此决定触及/掩护/AOE。
var formation: Dictionary = {}
var formation_cell: Dictionary = {}

# 站位模式：
#   "reach"    = 硬触及（近战打不到后排，PositionExperiment/GridExperiment 用，默认）
#   "soft_row" = 世界树式软调整（人人可达，后排物理减伤/后排近战减伤害，BackpackExperiment 用）
var positioning_mode: String = "reach"

# 职业默认排位：近战前排，远程/支援后排
const DEFAULT_ROW_BY_CLASS: Dictionary = {
	Hero.HeroClass.WARRIOR: "front",
	Hero.HeroClass.ROGUE:   "front",
	Hero.HeroClass.MAGE:    "back",
	Hero.HeroClass.ARCHER:  "back",
	Hero.HeroClass.PRIEST:  "back",
}

# 取某英雄的排位：优先网格格位 → formation → 职业默认 → front
func get_row(hero) -> String:
	if formation_cell.has(hero.instance_id):
		return "front" if formation_cell[hero.instance_id].y == 0 else "back"
	if formation.has(hero.instance_id):
		return formation[hero.instance_id]
	return DEFAULT_ROW_BY_CLASS.get(hero.hero_class, "front")

# 取某英雄的列：优先网格格位，兜底 0
func get_col(hero) -> int:
	if formation_cell.has(hero.instance_id):
		return formation_cell[hero.instance_id].x
	return 0

# 设置某英雄排位（2 排兼容路径）
func set_row(hero, p_row: String) -> void:
	formation[hero.instance_id] = p_row

# 设置某英雄网格格位（col 列，p_row "front"/"back"）
func set_cell(hero, col: int, p_row: String) -> void:
	formation_cell[hero.instance_id] = Vector2i(col, 0 if p_row == "front" else 1)


# ── 技能回合冷却配置（方案 B：技能书注入）────────────────────────────────────
# { hero.instance_id: { skill_id: cd_turns } }；空=无冷却。BattleSimulator 据此注入战斗单位。
var skill_cd_config: Dictionary = {}

func set_skill_cd(hero, config: Dictionary) -> void:
	skill_cd_config[hero.instance_id] = config

func get_skill_cd(hero) -> Dictionary:
	return skill_cd_config.get(hero.instance_id, {})


# ── 副属性注入（方案 B：暴击/吸血/法抗… 由背包给，经此带入战斗）──────────────
# { hero.instance_id: { crit_chance: , crit_dmg: , ... } }
var extra_stats_config: Dictionary = {}

func set_extra_stats(hero, stats: Dictionary) -> void:
	extra_stats_config[hero.instance_id] = stats

func get_extra_stats(hero) -> Dictionary:
	return extra_stats_config.get(hero.instance_id, {})


# ── 行进状态快照（供存档原位恢复，由 HeroAI 持续写入）──────────────────────────
# 存档时读取这些字段重建队伍位置；读档后 HeroAI.resume_from() 据此从原地继续。
var travel_path:   Array = []   # Array[Vector3i]，当前路径
var travel_index:  int   = 0    # 已走到 travel_path 的索引（当前所在格）
var move_progress: float = 0.0  # 当前格→下一格的小数进度（0~1），连续移动精确恢复用
var ai_state:      int   = 0    # 对应 HeroAI.State（TRAVELING / RETURNING…）
var ai_resume:     int   = 0    # 对应 HeroAI._Resume（战斗后意图）

# ── 旅途战斗收益累积（回城统一结算；中途全灭则随队伍一起损失）─────────────────
var pending_loot:      Array = []   # Array[Dictionary]，累积的战利品掉落条目
var pending_loot_gold: int   = 0    # 累积的掉落金币（回城并入总奖励分成）

# ── 旅途战报（运行时 UI 缓冲，不序列化）────────────────────────────────────────
# 每场战斗一条：{ "context": String, "enemy_names": Array[String],
#               "casualties": Array[String], "won": bool, "result": BattleResult }
# 回城结算时随 quest_settled 数据传给 SettlementUI 展示，点击可看完整日志。
var battle_reports: Array = []


# ── 构造函数 ──────────────────────────────────────────────────────────────────

# 工厂方法：创建一支队伍
# 参数：
#   p_heroes      : 英雄数组
#   p_quest       : 关联任务
#   p_share_ratio : 英雄分成比例（从 GuildManager 快照）
#   p_start_tile  : 出发格子（通常是公会所在地）
static func create(
	p_heroes:       Array,
	p_quest,
	p_share_ratio:  float,
	p_start_tile:   Vector3i = Vector3i.ZERO
) -> Party:
	var party                = Party.new()
	party.heroes             = p_heroes.duplicate()  # 浅拷贝，Hero 本身不复制
	party.quest              = p_quest
	party.hero_share_ratio   = clampf(p_share_ratio, 0.0, 1.0)
	party.current_tile       = p_start_tile
	return party


# ── 成员管理 ──────────────────────────────────────────────────────────────────

# 存活成员数量
func alive_count() -> int:
	var count = 0
	for hero in heroes:
		if hero.is_alive():
			count += 1
	return count

# 是否全员阵亡（任务自动失败触发条件）
func is_wiped_out() -> bool:
	return alive_count() == 0

# 获取所有存活英雄（供 BattleSimulator 使用）
func get_alive_heroes() -> Array:
	return heroes.filter(func(h): return h.is_alive())


# ── 消耗品管理 ────────────────────────────────────────────────────────────────

# 添加共享消耗品
func add_shared_consumable(item) -> void:  # item: Consumable
	shared_consumables.append(item)

# 取用共享消耗品（使用后从列表移除）
# 返回 null 表示没有该类型的消耗品
func take_shared_consumable(effect_type: String):  # → Consumable or null
	for i in range(shared_consumables.size()):
		if shared_consumables[i].effect_type == effect_type:
			return shared_consumables.pop_at(i)
	return null


# ── 经济结算 ──────────────────────────────────────────────────────────────────

# 计算任务奖励的分配结果
# total_gold：本次任务总金币奖励
# 返回：{ "guild": int, "per_hero": int }
# per_hero 是每个存活英雄各自拿到的金额（平均分）
func calculate_payout(total_gold: int) -> Dictionary:
	var hero_total = int(total_gold * hero_share_ratio)
	var guild_cut  = total_gold - hero_total

	var alive = alive_count()
	var per_hero = 0
	if alive > 0:
		per_hero = floori(float(hero_total) / float(alive))  # 用 floori 避免整数除法警告

	return {
		"guild":    guild_cut + (hero_total - per_hero * alive),  # 余数补进公会
		"per_hero": per_hero
	}

# 结算：把奖励分发到各英雄的私人钱包
# 通常在 QuestManager 收到 quest_completed 信号后调用
func distribute_payout(total_gold: int) -> Dictionary:
	var payout = calculate_payout(total_gold)
	for hero in get_alive_heroes():
		hero.receive_share(payout["per_hero"])
	return payout  # 返回给 GuildManager 知道公会拿多少


# ── 移动 ─────────────────────────────────────────────────────────────────────

# 更新队伍当前所在格子（HeroAI 移动时调用）
func move_to(tile: Vector3i) -> void:
	current_tile = tile


# ── 存读档 ────────────────────────────────────────────────────────────────────
# 旧公会项目的 to_dict/from_dict（依赖 HexUtils/HeroManager/Quest）已在迁移到
# Brave Team 时移除——roguelike 跑局的队伍持久化将由新的 RunManager 负责，
# 届时按需重写。这里保留空位说明。
