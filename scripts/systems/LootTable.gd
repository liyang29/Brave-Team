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


## 物品稀有度（未知当 common）
static func rarity_of(item_id: String) -> String:
	return Backpack.item_def(item_id).get("rarity", "common")

## 物品售价（按 rarity；色阶不影响售价——两条轴独立）
static func price(item_id: String) -> int:
	return int(RARITY_PRICES.get(rarity_of(item_id), RARITY_PRICES["common"]))


## 按 rarity 权重抽 count 件不重复物品，返回 item_id 数组（池不够时尽量多给）。
## 掉落色阶两条路：mergeable 物品恒掉白（走合成链变强）；fixed_tier 机制类物品
## 直接固定色阶掉落（不参与合成）。
## layer：深度门控——min_layer > layer 的物品本次不进候选池（早期摸不到后期特殊物品）；
##   缺省 999（近乎不限）保持旧调用/旧测试不指定层数时行为不变。池被门槛过滤空时兜底放开门槛。
static func draw_draft(count: int, layer: int = 999) -> Array:
	var pool: Array = Backpack.ITEMS.keys().filter(func(id): return Backpack.min_layer_of(id) <= layer)
	if pool.is_empty():
		pool = Backpack.ITEMS.keys()   # 兜底：门槛把池过滤空了 → 放开门槛，不卡死掉落/商店
	var result: Array = []
	var n: int = min(count, pool.size())
	for i in range(n):
		var pick: String = _weighted_pick(pool)
		if pick == "":
			break
		result.append(_drop_id(pick))
		pool.erase(pick)   # 不重复（按基础 id 去重，同基础物品同次不重复出现）
	return result

## 某基础物品的掉落实例 id：fixed_tier 物品固定色阶；其余（含 mergeable）恒掉白（tier0）。
static func _drop_id(base_item_id: String) -> String:
	var t: int = Backpack.fixed_tier_of(base_item_id)
	return Backpack.tiered_id(base_item_id, t) if t >= 0 else base_item_id


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
