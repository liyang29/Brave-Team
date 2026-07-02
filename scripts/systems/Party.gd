class_name Party extends RefCounted

# ─────────────────────────────────────────────────────────────────────────────
# Party — 战斗队伍（运行时对象）
#
# 生命周期：遭遇开战前由 BackpackLoadout.build_party 创建 → 战斗结束引用消失
# 继承 RefCounted：没有引用后自动被 GC 回收，不占内存
#
# 注意：Party 不是 Resource，不需要存档。roguelike 跑局的持久状态（队伍/金币/
#   地图进度）由 RunManager(autoload) 负责；Party 只是"这场战斗怎么打"的临时载体。
# ─────────────────────────────────────────────────────────────────────────────


# ── 字段 ──────────────────────────────────────────────────────────────────────

# 参与本场战斗的英雄列表
var heroes: Array = []  # Array[Hero]


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


# ── 构造函数 ──────────────────────────────────────────────────────────────────

# 工厂方法：创建一支队伍
static func create(p_heroes: Array) -> Party:
	var party  = Party.new()
	party.heroes = p_heroes.duplicate()  # 浅拷贝，Hero 本身不复制
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
