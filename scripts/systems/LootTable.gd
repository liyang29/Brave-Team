extends RefCounted

# ─────────────────────────────────────────────────────────────────────────────
# LootTable — 战利品掉落（纯函数，便于测试）
#
# 按 rarity 权重从 BackpackModel.ITEMS 加权随机抽 N 件（同一次抽不重复）。
# 胜利后由 RunManager 调 draw_draft(3)，Draft 界面让玩家三选二。
#
# 故意不带 class_name（preload 引入），同 BackpackModel/BackpackLoadout 路子。
# ─────────────────────────────────────────────────────────────────────────────

const Backpack = preload("res://scripts/systems/backpack/BackpackModel.gd")

# 各稀有度的抽取权重（越大越常见）。普通 65 / 稀有 27 / 史诗 8。
const RARITY_WEIGHTS: Dictionary = {
	"common": 65,
	"rare": 27,
	"epic": 8,
}

# 商店售价（按 rarity）。
const RARITY_PRICES: Dictionary = {
	"common": 50,
	"rare": 120,
	"epic": 250,
}

# ── 深度掉落色阶曲线 ──────────────────────────────────────────────────────────
# mergeable 物品掉落时按"当前层数"掷一个色阶（越深越可能直接掉出预合成好的绿/蓝），
# 减少纯粹拼手速合成的枯燥感；天然掉落【封顶紫色(3)】——橙/红永远只能靠玩家自己
# 合成 16/32 把同款摸到，保住"凑齐红装"的成就感，不被运气抹平。
# 按层分档取第一个 max_layer≥当前层的档；键=色阶索引，值=权重。
const TIER_WEIGHTS_BY_LAYER: Array = [
	{ "max_layer": 4,   "weights": { 0: 100 } },
	{ "max_layer": 10,  "weights": { 0: 82, 1: 16, 2: 2 } },
	{ "max_layer": 999, "weights": { 0: 60, 1: 25, 2: 12, 3: 3 } },
]


## 物品稀有度（未知当 common）
static func rarity_of(item_id: String) -> String:
	return Backpack.item_def(item_id).get("rarity", "common")

## 物品售价（按 rarity；色阶不影响售价——两条轴独立）
static func price(item_id: String) -> int:
	return int(RARITY_PRICES.get(rarity_of(item_id), RARITY_PRICES["common"]))


## 按 rarity 权重抽 count 件不重复物品，返回 item_id 数组（池不够时尽量多给）。
## 掉落色阶三条路：fixed_tier 机制类物品固定色阶（不参与合成）；mergeable 物品按层数
## 掷色阶（深度掉落曲线，见 TIER_WEIGHTS_BY_LAYER）；其余（如技能书）恒白。
## layer：调用方所在层数。**不传(-1)="未指定"**——门槛全放开 + 色阶恒白 + 不查局外解锁，
##   保持旧调用/旧测试不传层数时的行为（向后兼容）。真实层数请传 RunManager.current_layer()。
##   （局内深度门槛 min_layer 和局外解锁 MetaProgress 绑同一个开关：不知道"在哪一局的第几层"，
##    也就没有真实玩家档可查解锁状态，两道门槛一起放开。）
##   门槛过滤把池掏空时兜底放开门槛，不卡死掉落/商店。
static func draw_draft(count: int, layer: int = -1) -> Array:
	var pool: Array = Backpack.ITEMS.keys()
	if layer >= 0:
		pool = pool.filter(func(id): return MetaProgress.is_unlocked(id))
		var gated: Array = pool.filter(func(id): return Backpack.min_layer_of(id) <= layer)
		if not gated.is_empty():
			pool = gated
	var result: Array = []
	var n: int = min(count, pool.size())
	for i in range(n):
		var pick: String = _weighted_pick(pool)
		if pick == "":
			break
		result.append(_drop_id(pick, layer))
		pool.erase(pick)   # 不重复（按基础 id 去重，同基础物品同次不重复出现）
	return result

## 某基础物品的掉落实例 id：
##   fixed_tier 机制类物品：固定色阶。
##   mergeable 物品：layer<0(未指定)恒白；否则按 TIER_WEIGHTS_BY_LAYER 掷色阶。
##   其余（如技能书）：恒白。
static func _drop_id(base_item_id: String, layer: int) -> String:
	var ft: int = Backpack.fixed_tier_of(base_item_id)
	if ft >= 0:
		return Backpack.tiered_id(base_item_id, ft)
	if layer >= 0 and Backpack.is_mergeable(base_item_id):
		return Backpack.tiered_id(base_item_id, _roll_drop_tier(layer))
	return base_item_id


## 按层数从 TIER_WEIGHTS_BY_LAYER 掷一个色阶。
static func _roll_drop_tier(layer: int) -> int:
	var weights: Dictionary = _weights_for_layer(layer)
	var keys: Array = weights.keys()
	var total: int = 0
	for t in keys:
		total += int(weights[t])
	if total <= 0:
		return 0
	var roll: int = randi() % total
	for t in keys:
		roll -= int(weights[t])
		if roll < 0:
			return int(t)
	return int(keys[keys.size() - 1])   # 兜底（理论不达）

## 某层对应的色阶权重表（取第一个 max_layer≥层 的档）。
static func _weights_for_layer(layer: int) -> Dictionary:
	for cfg in TIER_WEIGHTS_BY_LAYER:
		if layer <= int(cfg.get("max_layer", 999)):
			return cfg.get("weights", { 0: 100 })
	return { 0: 100 }


## 从候选 id 列表里按 rarity 权重随机取一个
static func _weighted_pick(candidates: Array) -> String:
	var total: int = 0
	for id in candidates:
		total += _weight_of(id)
	if total <= 0:
		return ""
	var roll: int = randi() % total
	for id in candidates:
		roll -= _weight_of(id)
		if roll < 0:
			return id
	return candidates[candidates.size() - 1]   # 兜底（理论不达）


## 单件物品的抽取权重（按 rarity；未知 rarity 当 common）
static func _weight_of(item_id: String) -> int:
	var rarity: String = Backpack.ITEMS.get(item_id, {}).get("rarity", "common")
	return int(RARITY_WEIGHTS.get(rarity, RARITY_WEIGHTS["common"]))
