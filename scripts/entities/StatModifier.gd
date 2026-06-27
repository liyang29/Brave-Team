class_name StatModifier extends RefCounted

# ─────────────────────────────────────────────────────────────────────────────
# StatModifier — 装饰器单元（属性修正条目）
#
# 这是装饰器模式中的"装饰器"本体，每一件装备或每一个 Buff 都会生成
# 若干个 StatModifier，交给 StatBlock 统一叠加计算。
#
# 设计要点：
#   - FLAT   加法修正：攻击力 +10（装备常用）
#   - PERCENT 百分比修正：攻击力 +15%（饰品/Buff 常用）
#   - remaining_turns = -1 表示永久生效（装备），> 0 表示临时（Buff 倒计时）
#   - source_id 用于精准移除，例如卸下某件装备时只移除那件装备的修正
# ─────────────────────────────────────────────────────────────────────────────


# ── 修正类型 ──────────────────────────────────────────────────────────────────

enum Type {
	FLAT,    # 加法：base + value
	PERCENT  # 百分比：最终值 × (1 + value/100)
}


# ── 字段 ──────────────────────────────────────────────────────────────────────

# 修正哪个属性（使用 StatBlock.Stat 枚举）
var stat: int           # StatBlock.Stat 枚举值，避免循环引用故用 int

# 修正类型：加法 or 百分比
var mod_type: Type

# 修正数值
# FLAT：正整数表示加成，负整数表示减益（例如诅咒装备）
# PERCENT：正数表示加成百分比（15 表示 +15%）
var value: float

# 剩余回合数
# -1：永久生效（装备加成），每次 tick_turn 时不减少
# >0：临时 Buff，每回合 -1，归零时由 StatBlock 自动移除
var remaining_turns: int

# 来源 ID：标识这条修正由谁产生，用于精准移除
# 例如："iron_sword_instance_123" 或 "warrior_rage_buff"
var source_id: String


# ── 构造函数 ──────────────────────────────────────────────────────────────────

# 参数说明：
#   p_stat   : StatBlock.Stat 枚举值（int）
#   p_type   : Type.FLAT 或 Type.PERCENT
#   p_value  : 修正数值
#   p_turns  : 剩余回合，默认 -1（永久）
#   p_source : 来源 ID，默认空字符串
func _init(
	p_stat:   int,
	p_type:   Type,
	p_value:  float,
	p_turns:  int    = -1,
	p_source: String = ""
) -> void:
	stat            = p_stat
	mod_type        = p_type
	value           = p_value
	remaining_turns = p_turns
	source_id       = p_source


# ── 查询 ──────────────────────────────────────────────────────────────────────

# 是否永久生效（装备类修正）
func is_permanent() -> bool:
	return remaining_turns == -1

# 是否已过期（Buff 倒计时到 0）
func is_expired() -> bool:
	return remaining_turns == 0
