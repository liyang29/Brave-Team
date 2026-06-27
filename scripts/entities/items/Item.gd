class_name Item extends GameEntity

# ─────────────────────────────────────────────────────────────────────────────
# Item — 物品基类
#
# 继承关系：
#   Item → Equipment  （可装备物品，提供属性加成）
#   Item → Consumable （消耗品，使用后产生效果）
#
# 为什么继承 GameEntity 而不是 Combatant？
#   物品没有战斗属性，不参与战斗计算，和 Combatant 没有 is-a 关系。
#   GameEntity 提供了 ID、名字、描述和存档接口，正好够用。
# ─────────────────────────────────────────────────────────────────────────────


# ── 稀有度 ────────────────────────────────────────────────────────────────────

enum Rarity {
	COMMON,    # 常见：灰色，大量存在，低价值
	UNCOMMON,  # 精良：绿色，任务掉落较常见
	RARE,      # 稀有：蓝色，装备副本或商店精品
	EPIC       # 史诗：紫色，高价值，精英/Boss 专属
}

# 稀有度颜色（供 UI 直接使用，避免在 UI 代码里硬编码颜色映射）
const RARITY_COLORS: Dictionary = {
	Rarity.COMMON:   Color(0.8, 0.8, 0.8),   # 灰白
	Rarity.UNCOMMON: Color(0.3, 0.8, 0.3),   # 绿
	Rarity.RARE:     Color(0.3, 0.5, 1.0),   # 蓝
	Rarity.EPIC:     Color(0.7, 0.3, 1.0),   # 紫
}


# ── 字段 ──────────────────────────────────────────────────────────────────────

# 稀有度：决定 UI 颜色和掉落感知
@export var rarity: Rarity = Rarity.COMMON

# 基础售价（金币）：在市场/NPC 处出售时的参考价格
# 实际售价可能受公会等级、NPC 好感度影响（扩展期处理）
@export var sell_price: int = 0

# 是否为公会专属物品（来自仓库，英雄不能私自卖掉）
# true  = 公会财产，只有玩家可以分配/出售
# false = 英雄自己买的或分到的，英雄可以自行处置
@export var guild_owned: bool = true


# ── 工具方法 ──────────────────────────────────────────────────────────────────

# 获取稀有度颜色（供 UI 调用）
func get_rarity_color() -> Color:
	return RARITY_COLORS.get(rarity, Color.WHITE)

# 获取稀有度名称（供 UI 显示）
func get_rarity_name() -> String:
	match rarity:
		Rarity.COMMON:   return "常见"
		Rarity.UNCOMMON: return "精良"
		Rarity.RARE:     return "稀有"
		Rarity.EPIC:     return "史诗"
	return "未知"


# ── 存档 ──────────────────────────────────────────────────────────────────────

func to_dict() -> Dictionary:
	var data            = super.to_dict()
	data["rarity"]      = rarity
	data["sell_price"]  = sell_price
	data["guild_owned"] = guild_owned
	return data

func from_dict(data: Dictionary) -> void:
	super.from_dict(data)
	rarity      = data.get("rarity",      Rarity.COMMON)
	sell_price  = data.get("sell_price",  0)
	guild_owned = data.get("guild_owned", true)
