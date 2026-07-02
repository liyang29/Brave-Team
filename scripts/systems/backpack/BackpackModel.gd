extends RefCounted

# ─────────────────────────────────────────────────────────────────────────────
# BackpackModel — 背包数据 + 邻接协同计算（纯数据/纯函数，便于测试与复用）
#
# 方案 B 新方向（"商队远征版 Megaloot + 小队"）的核心：
#   背包 = 网格，物品占格子（空间有限 → 取舍），相邻同类触发协同（摆位 → 深度）。
#
# 故意不带 class_name（用 preload 引入），避免全局类缓存时序问题。
# 场景与测试都 preload 本文件，调静态函数。
# ─────────────────────────────────────────────────────────────────────────────

# ── 物品表 ────────────────────────────────────────────────────────────────────
# 每件：name + 属性(atk/def/hp/magic) + tag(用于协同) + rarity(战利品掉落权重档)
# rarity: "common"/"rare"/"epic"，权重见 LootTable.RARITY_WEIGHTS。
const ITEMS: Dictionary = {
	# mergeable:true = 参与色阶合成链（见下方"色阶"节）；纯数值装备，起手掉落恒为白。
	"iron_sword":  { "name": "铁剑",   "atk": 6,  "tag": "blade",   "shape": "1x2v", "rarity": "common", "mergeable": true },
	"longsword":   { "name": "长剑",   "atk": 8,  "tag": "blade",   "shape": "1x3v", "rarity": "rare",   "mergeable": true },
	"whetstone":   { "name": "磨刀石", "atk": 2,  "tag": "sharpen", "rarity": "common", "mergeable": true },
	"shield":      { "name": "圆盾",   "def": 5,  "tag": "guard",   "shape": "1x2v", "rarity": "common", "mergeable": true },
	"chainmail":   { "name": "锁甲",   "def": 6, "hp": 10, "tag": "armor", "shape": "2x2", "rarity": "rare", "mergeable": true },
	"leather":     { "name": "皮甲",   "def": 3, "hp": 15, "tag": "armor", "shape": "1x2v", "rarity": "common", "mergeable": true },
	"staff":       { "name": "法杖",   "magic": 6, "tag": "arcane", "shape": "1x3v", "rarity": "rare",   "mergeable": true },
	"tome":        { "name": "魔典",   "magic": 4, "tag": "arcane", "rarity": "common", "mergeable": true },
	"holy_symbol": { "name": "圣徽",   "magic": 5, "tag": "holy",   "rarity": "rare",   "mergeable": true },
	"amulet":      { "name": "护符",   "hp": 12, "def": 2, "tag": "vital", "rarity": "common", "mergeable": true },
	"charm":       { "name": "红宝石", "hp": 20, "tag": "vital",    "rarity": "rare",   "mergeable": true },
	"mana_charm":  { "name": "法力护符", "mp": 30, "magic": 2, "tag": "arcane", "rarity": "rare", "mergeable": true },

	# ── 后期基础装备（深度解锁：min_layer 门槛，数值高于早期同类；也走合成链）─────
	# 不只是"老装备数字更大"——是新内容：早期摸不到，走到对应层数才会开始遇见/能买到。
	# 2026-07：地图 9→45 层，门槛按比例重标定（约 ×5）。
	"steel_sword":  { "name": "精钢剑", "atk": 10, "tag": "blade", "shape": "1x2v", "rarity": "rare", "mergeable": true, "min_layer": 15 },
	"mithril_staff":{ "name": "秘银法杖", "magic": 10, "tag": "arcane", "shape": "1x3v", "rarity": "rare", "mergeable": true, "min_layer": 15 },
	"holy_hammer":  { "name": "圣光锤", "magic": 8, "def": 2, "tag": "holy", "shape": "1x2v", "rarity": "rare", "mergeable": true, "min_layer": 15 },
	"dragon_scale": { "name": "巨龙鳞甲", "def": 12, "hp": 20, "tag": "armor", "shape": "2x2", "rarity": "epic", "mergeable": true, "min_layer": 30 },

	# ── 小队光环装备（aura：跨英雄加成，按 scope 作用范围，在 build_party 注入）──
	# scope: "team"=全队(含自己) / "adjacent"=相邻站位(不含自己) / "same_row"=同排(不含自己)
	# fixed_tier = 机制类物品不参与合成，直接按固定色阶掉落（数字见下方 TIER_NAMES 索引）。
	# min_layer = 深度门控：早于该层不会掉落/不会在商店出现（缺省 0 = 起手就能遇到）。
	"war_banner":  { "name": "军旗",   "tag": "banner", "rarity": "rare", "fixed_tier": 2, "min_layer": 10, "aura": { "scope": "team",     "atk": 4 } },
	"speed_totem": { "name": "疾风图腾", "tag": "banner", "rarity": "rare", "fixed_tier": 2, "min_layer": 10, "aura": { "scope": "adjacent", "spd": 3 } },
	"iron_standard":{ "name": "铁壁旗", "tag": "banner", "rarity": "epic", "fixed_tier": 4, "min_layer": 25, "aura": { "scope": "same_row", "def": 4 } },
	"vanguard_horn":{ "name": "先锋号角", "tag": "banner", "rarity": "rare", "fixed_tier": 2, "min_layer": 10, "aura": { "scope": "front_row", "atk": 5 } },
	"ward_totem":  { "name": "守护图腾", "tag": "banner", "rarity": "rare", "fixed_tier": 2, "min_layer": 10, "aura": { "scope": "back_row",  "def": 3, "hp": 10 } },

	# ── 副属性物品（第一个副属性：暴击）──────────────────────────────────────
	"crit_gem":    { "name": "暴击宝石", "crit_chance": 0.15, "tag": "crit", "rarity": "epic", "fixed_tier": 3, "min_layer": 20 },
	"keen_edge":   { "name": "锋锐之刃", "atk": 4, "crit_chance": 0.10, "tag": "blade", "rarity": "rare", "fixed_tier": 1, "min_layer": 5 },
	"berserk_ring":{ "name": "狂战戒",   "crit_dmg": 0.5, "tag": "crit",  "rarity": "epic", "fixed_tier": 3, "min_layer": 20 },

	# ── 闪避 / 嘲讽副属性（小队第二档·"闪避T"套件）────────────────────────────
	# dodge_chance：被攻击时几率完全免伤（战斗里 clamp 到 DODGE_CAP）。
	# taunt：>0 = 优先被敌人攻击（吸火力保后排）。两者均走 extra 通路，同暴击。
	# 设计：纯闪避/纯嘲讽件无属性 → 占格机会成本明显；坦克件嘲讽+防。
	"evasion_cloak":{ "name": "疾风斗篷", "dodge_chance": 0.18, "tag": "evasion", "rarity": "rare", "fixed_tier": 2, "min_layer": 10 },
	"shadow_mantle":{ "name": "暗影披风", "def": 2, "dodge_chance": 0.10, "tag": "evasion", "rarity": "epic", "fixed_tier": 3, "min_layer": 20 },
	"provoke_charm":{ "name": "挑衅护符", "taunt": 1, "def": 4, "tag": "taunt", "rarity": "rare", "fixed_tier": 2, "min_layer": 10 },
	# 诱敌面具：无裸属性、但改变职业规则（嘲讽）→ 至少橙色档 + 深度门控（决策：不看数值看机制影响力）。
	"decoy_mask":   { "name": "诱敌面具", "taunt": 1, "tag": "taunt", "rarity": "common", "fixed_tier": 4, "min_layer": 25 },

	# ── 技能书（占格、不给属性；认职业；带回合冷却）──────────────────────────
	# 技能书 = 把"技能"也做成背包物品：占格 → 和装备抢空间（带书=少带甲）。
	# 职业由对应技能的 SkillTable.hero_class 决定（实验里按持有者职业过滤）。技能书不参与色阶系统。
	"book_slash":    { "name": "斩击书", "tag": "skillbook", "skill_id": "slash",     "cd": 1, "rarity": "common" },
	"book_cleave":   { "name": "横扫书", "tag": "skillbook", "skill_id": "cleave",    "cd": 2, "rarity": "rare" },
	"book_taunt":    { "name": "挑衅书", "tag": "skillbook", "skill_id": "taunt_roar", "cd": 2, "rarity": "common" },
	"book_fireball": { "name": "火球书", "tag": "skillbook", "skill_id": "fireball",  "cd": 2, "rarity": "rare" },
	"book_icelance": { "name": "冰枪书", "tag": "skillbook", "skill_id": "ice_lance", "cd": 1, "rarity": "rare" },
	"book_heal":     { "name": "治疗书", "tag": "skillbook", "skill_id": "holy_heal", "cd": 1, "rarity": "common" },
	"book_purify":   { "name": "净化书", "tag": "skillbook", "skill_id": "purify",    "cd": 2, "rarity": "common" },
}

# ── 色阶（合成系统）───────────────────────────────────────────────────────────
# 色阶 = 物品实例的"合成等级"，与 rarity(掉落权重/售价) 是两条独立轴：
#   rarity 决定"这件物品类型好不好找"；tier 决定"这一件被合成了几次"。
# 只对 ITEMS 标 "mergeable":true 的物品生效（纯数值装备，起手恒白）；机制类物品
# （技能书除外的光环/副属性件）不参与合成，按各自 "fixed_tier" 直接固定色阶掉落。
#
# 物品实例 id 编码：tier=0(白) 时就是原始 item_id（完全向后兼容，旧数据/旧测试不用改）；
# tier>0 时追加 "@N" 后缀（如 "iron_sword@2" = 蓝铁剑）。查 ITEMS/形状/tag 前一律
# 先经 base_id() 剥掉后缀 —— 已在 item_def() 里统一处理，其余函数都改走 item_def()。
const TIER_NAMES: Array = ["白", "绿", "蓝", "紫", "橙", "红"]
const TIER_MAX := 5   # 红 = 最高色阶（索引 5）；2 件同色阶合成 1 件高一阶，红=32把白的合成
const TIER_COLORS: Array = [
	Color(0.72, 0.72, 0.75),   # 白
	Color(0.35, 0.75, 0.35),   # 绿
	Color(0.30, 0.55, 0.95),   # 蓝
	Color(0.62, 0.35, 0.85),   # 紫
	Color(0.95, 0.60, 0.15),   # 橙
	Color(0.90, 0.20, 0.20),   # 红
]
# 只有这几项数值随色阶翻倍；副属性(EXTRA_KEYS，如暴击/闪避百分比)与光环不吃色阶缩放
# ——避免百分比类属性被合成指数级放大到离谱（钳制/上限逻辑另在战斗层）。
const SCALABLE_KEYS: Array = ["atk", "def", "hp", "magic", "mp"]

## 物品实例 id 的基础物品 id（剥掉 "@N" 色阶后缀）。
static func base_id(item_id: String) -> String:
	var i := item_id.find("@")
	return item_id if i < 0 else item_id.substr(0, i)

## 物品实例的色阶（0=白，缺省 0）。
static func item_tier(item_id: String) -> int:
	var i := item_id.find("@")
	return 0 if i < 0 else int(item_id.substr(i + 1))

## 按基础 id + 色阶构造实例 id（tier<=0 就是原始 id，完全向后兼容）。
static func tiered_id(base: String, tier: int) -> String:
	return base if tier <= 0 else "%s@%d" % [base, tier]

## 物品实例对应的数据定义（自动剥色阶后缀查 ITEMS；全项目查物品定义的唯一入口）。
static func item_def(item_id: String) -> Dictionary:
	return ITEMS.get(base_id(item_id), {})

## 该基础物品是否参与合成链。
static func is_mergeable(item_id: String) -> bool:
	return bool(item_def(item_id).get("mergeable", false))

## 机制类物品的固定掉落色阶（未标注返回 -1 = 走合成链常规白色起步）。
static func fixed_tier_of(item_id: String) -> int:
	var v = item_def(item_id).get("fixed_tier", -1)
	return int(v)

## 该物品最早出现的层（深度门控；缺省 0 = 起手就能遇到）。
static func min_layer_of(item_id: String) -> int:
	return int(item_def(item_id).get("min_layer", 0))

## 色阶数值倍率（白×1 ... 红×32）。
static func tier_multiplier(tier: int) -> float:
	return pow(2.0, clampi(tier, 0, TIER_MAX))

## 色阶中文名。
static func tier_name(tier: int) -> String:
	return TIER_NAMES[clampi(tier, 0, TIER_MAX)]

## 色阶背景色（UI 用）。
static func tier_color(tier: int) -> Color:
	return TIER_COLORS[clampi(tier, 0, TIER_MAX)]

## 物品实例某数值属性经色阶缩放后的值（四舍五入）。只对 SCALABLE_KEYS 生效；
## 副属性/光环不吃缩放，直接读原始数值（EXTRA_KEYS 用 item_def(id).get(key) 即可）。
static func item_stat(item_id: String, key: String) -> int:
	var base: float = float(item_def(item_id).get(key, 0))
	if key in SCALABLE_KEYS:
		base *= tier_multiplier(item_tier(item_id))
	return int(round(base))

## 合成结果：两件同基础同色阶的 item_id 合成后得到的实例 id。
## 不可合成(非 mergeable) 或已到顶(红) 时返回 ""。
static func merge_result(item_id: String) -> String:
	if not is_mergeable(item_id):
		return ""
	var t: int = item_tier(item_id)
	if t >= TIER_MAX:
		return ""
	return tiered_id(base_id(item_id), t + 1)

# ── 网格 & 物品形状（空间填装）─────────────────────────────────────────────────
# 背包 = GRID_W×GRID_H 网格。物品占多格（形状）→ "塞得下"本身是取舍。
# grid 结构：{ 锚点Vector2i: item_id }，一条目 = 一件 = 一个实例；
#   占用格 = 锚点 + SHAPES[物品.shape]（缺省 "1x1"，即老物品一格、完全向后兼容）。
# 形状用【具名表】配置：物品只写 "shape": "2x2"；加新形状 = SHAPES 加一行，全物品可用。
const GRID_W := 4
const GRID_H := 4

const SHAPES: Dictionary = {
	"1x1":  [Vector2i(0, 0)],
	"1x2h": [Vector2i(0, 0), Vector2i(1, 0)],                   # 横 1×2
	"1x2v": [Vector2i(0, 0), Vector2i(0, 1)],                   # 竖 1×2
	"1x3h": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)],   # 横 1×3
	"1x3v": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)],   # 竖 1×3
	"2x2":  [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
}

## 物品的形状名（缺省 1x1；色阶不改形状，见 base_id/item_def）。
static func shape_name(item_id: String) -> String:
	return item_def(item_id).get("shape", "1x1")

## 物品的形状偏移列表（相对锚点）。
static func shape_offsets(item_id: String) -> Array:
	return SHAPES.get(shape_name(item_id), SHAPES["1x1"])

## 一件物品放在 anchor 时占用的所有格子。
static func item_cells(item_id: String, anchor: Vector2i) -> Array:
	var out: Array = []
	for off in shape_offsets(item_id):
		out.append(anchor + off)
	return out

## 格子是否在 GRID_W×GRID_H 界内。
static func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < GRID_W and cell.y >= 0 and cell.y < GRID_H

## grid 的占用图 { 格子 -> 锚点 }。ignore_anchor 可排除某件（拖动它自己时用）。
static func occupied_cells(grid: Dictionary, ignore_anchor = null) -> Dictionary:
	var occ: Dictionary = {}
	for anchor in grid:
		if ignore_anchor != null and anchor == ignore_anchor:
			continue
		for c in item_cells(grid[anchor], anchor):
			occ[c] = anchor
	return occ

## 能否把 item_id 放到 anchor：所有占用格都在界内且不与别件重叠。
## ignore_anchor：移动某件到新位时排除它自身原占用（否则会与自己冲突）。
static func can_place(grid: Dictionary, item_id: String, anchor: Vector2i, ignore_anchor = null) -> bool:
	var occ: Dictionary = occupied_cells(grid, ignore_anchor)
	for c in item_cells(item_id, anchor):
		if not in_bounds(c) or occ.has(c):
			return false
	return true


# ── 邻接协同规则 ──────────────────────────────────────────────────────────────
# 两件不同物品的格子在网格中正交相邻 → 给该背包持有者加成（每对物品每种协同只算一次）
const SYNERGIES: Array = [
	{ "a": "blade",  "b": "sharpen", "bonus": { "atk": 6 },            "name": "开刃" },
	{ "a": "guard",  "b": "armor",   "bonus": { "def": 5, "hp": 12 },  "name": "重装" },
	{ "a": "arcane", "b": "arcane",  "bonus": { "magic": 6 },          "name": "共鸣" },
	{ "a": "vital",  "b": "vital",   "bonus": { "hp": 18 },            "name": "生机" },
]


# 副属性 key 列表：以后加新副属性（吸血/法抗/破甲…）只需往这里加 key，
# 物品声明该 key、战斗公式读 BattleCombatant.get_stat()，compute 自动累加。
const EXTRA_KEYS: Array = ["crit_chance", "crit_dmg", "dodge_chance", "taunt"]

## 计算一个背包的总加成。
## grid: { Vector2i(col,row): item_id }
## 返回: { "atk","def","hp","magic":int, "synergies":Array, "books":Array, "extra":Dictionary }
static func compute(grid: Dictionary) -> Dictionary:
	var atk: int = 0
	var def_v: int = 0
	var hp: int = 0
	var magic: int = 0
	var mp: int = 0
	var fired: Array = []
	var books: Array = []   # [{ "id": skill_id, "cd": cd_turns }]，已按摆放"读序"排序（见下）
	var book_cells: Array = []   # 临时：[{ cell, id, cd }]，收集后按读序排序
	var extra: Dictionary = {}   # 副属性累加（crit_chance 等）

	# 物品基础属性（技能书无属性，只收集到 books）。数值按色阶缩放（item_stat）；
	# 副属性(EXTRA_KEYS)不吃色阶，原样累加。
	for cell in grid:
		var raw_id: String = grid[cell]
		var it: Dictionary = item_def(raw_id)
		if it.get("tag", "") == "skillbook":
			book_cells.append({ "cell": cell, "id": it.get("skill_id", ""), "cd": int(it.get("cd", 0)) })
			continue
		atk   += item_stat(raw_id, "atk")
		def_v += item_stat(raw_id, "def")
		hp    += item_stat(raw_id, "hp")
		magic += item_stat(raw_id, "magic")
		mp    += item_stat(raw_id, "mp")
		# 副属性（通用累加，加新属性无需改这里的逻辑；不吃色阶缩放）
		for k in EXTRA_KEYS:
			if it.has(k):
				extra[k] = float(extra.get(k, 0.0)) + float(it[k])

	# 技能书按"读序"排序（上→下，每行左→右）→ 决定连招释放顺序（中间档：摆位=连招）
	book_cells.sort_custom(func(a, b):
		if a["cell"].y != b["cell"].y:
			return a["cell"].y < b["cell"].y
		return a["cell"].x < b["cell"].x)
	for be in book_cells:
		books.append({ "id": be["id"], "cd": be["cd"] })

	# 邻接协同（形状感知）：两件【不同物品实例】的占用格正交相邻 → 触发一次。
	#   任意一对相邻格即触发，同一对物品的同种协同只算一次（"任意格相邻=触发一次"）。
	var occ: Dictionary = occupied_cells(grid)   # 格子 -> 锚点（物品实例）
	var fired_pairs: Dictionary = {}             # "锚A|锚B|协同名" -> 已触发
	for cell in occ:
		var anchor_a: Vector2i = occ[cell]
		var tag_a: String = item_def(grid[anchor_a]).get("tag", "")
		if tag_a == "":
			continue
		for nb in [cell + Vector2i(1, 0), cell + Vector2i(-1, 0), cell + Vector2i(0, 1), cell + Vector2i(0, -1)]:
			if not occ.has(nb):
				continue
			var anchor_b: Vector2i = occ[nb]
			if anchor_b == anchor_a:
				continue                          # 同一件物品的相邻格，不算协同
			var tag_b: String = item_def(grid[anchor_b]).get("tag", "")
			for s in SYNERGIES:
				var sa: String = s["a"]
				var sb: String = s["b"]
				if not ((tag_a == sa and tag_b == sb) or (tag_a == sb and tag_b == sa)):
					continue
				var pk: String = _pair_key(anchor_a, anchor_b) + "|" + String(s["name"])
				if fired_pairs.has(pk):
					continue                      # 这对物品的这种协同已触发过
				fired_pairs[pk] = true
				var bonus: Dictionary = s["bonus"]
				atk   += int(bonus.get("atk", 0))
				def_v += int(bonus.get("def", 0))
				hp    += int(bonus.get("hp", 0))
				magic += int(bonus.get("magic", 0))
				fired.append(s["name"])

	return { "atk": atk, "def": def_v, "hp": hp, "magic": magic, "mp": mp, "synergies": fired, "books": books, "extra": extra }


# 两个锚点的无序配对键（同一对物品无论谁先都得同一 key）。
static func _pair_key(a: Vector2i, b: Vector2i) -> String:
	var sa := "%d,%d" % [a.x, a.y]
	var sb := "%d,%d" % [b.x, b.y]
	return (sa + "|" + sb) if sa < sb else (sb + "|" + sa)


## 物品显示名（tier>0 时带色阶前缀，如"橙·诱敌面具"；白色/未合成物品与旧行为完全一致）。
static func item_name(item_id: String) -> String:
	var nm: String = item_def(item_id).get("name", base_id(item_id))
	var t: int = item_tier(item_id)
	return "%s·%s" % [tier_name(t), nm] if t > 0 else nm

## 提取一个背包里所有"光环"(aura)，返回 Array[{scope, atk/def/hp/magic/spd/mp...}]。
## 光环是跨英雄效果，不进 compute（那是自身属性）；由 BackpackLoadout 按 scope 注入。
static func grid_auras(grid: Dictionary) -> Array:
	var out: Array = []
	for cell in grid:
		var it: Dictionary = item_def(grid[cell])
		if it.has("aura"):
			out.append(it["aura"])
	return out

const _SCOPE_ZH: Dictionary = { "team": "全队", "adjacent": "相邻", "same_row": "同排", "front_row": "前排", "back_row": "后排" }
const _STAT_ZH: Dictionary = { "atk": "攻", "def": "防", "hp": "血", "magic": "魔", "spd": "速", "mp": "蓝" }

## 光环效果的中文短描述，如 "全队 攻+4"
static func aura_text(aura: Dictionary) -> String:
	var scope: String = _SCOPE_ZH.get(aura.get("scope", "team"), "全队")
	var parts: Array = []
	for k in _STAT_ZH:
		if int(aura.get(k, 0)) != 0:
			parts.append("%s+%d" % [_STAT_ZH[k], int(aura[k])])
	return "%s %s" % [scope, " ".join(parts)]

## 光环范围说明（tooltip 用）——按 scope 说清"加给谁、含不含自己"。
## team/adjacent/same_row 必含持有者本人；front_row/back_row 是绝对排，只在持有者站那排时才含自己。
static func aura_scope_note(scope: String) -> String:
	match scope:
		"team":      return "全队都加（含自己）"
		"adjacent":  return "自己 + 正交相邻格的队友"
		"same_row":  return "持有者所在那一排（含自己）"
		"front_row": return "所有站前排的人（持有者站前排才含自己）"
		"back_row":  return "所有站后排的人（持有者站后排才含自己）"
	return "范围内队友"

## 物品简短属性描述（UI 用）。数值属性按色阶缩放显示；副属性/光环显示原始值。
static func item_desc(item_id: String) -> String:
	var it: Dictionary = item_def(item_id)
	if it.get("tag", "") == "skillbook":
		return "%s(技能·CD%d)" % [item_name(item_id), int(it.get("cd", 0))]
	var parts: Array = []
	var a := item_stat(item_id, "atk");   if a != 0: parts.append("攻+%d" % a)
	var d := item_stat(item_id, "def");   if d != 0: parts.append("防+%d" % d)
	var h := item_stat(item_id, "hp");    if h != 0: parts.append("血+%d" % h)
	var m := item_stat(item_id, "magic"); if m != 0: parts.append("魔+%d" % m)
	var p := item_stat(item_id, "mp");    if p != 0: parts.append("蓝+%d" % p)
	if float(it.get("crit_chance", 0.0)) != 0.0: parts.append("暴击+%d%%" % int(it["crit_chance"] * 100))
	if float(it.get("crit_dmg", 0.0)) != 0.0:    parts.append("暴伤+%d%%" % int(it["crit_dmg"] * 100))
	if float(it.get("dodge_chance", 0.0)) != 0.0: parts.append("闪避+%d%%" % int(it["dodge_chance"] * 100))
	if int(it.get("taunt", 0)) != 0:             parts.append("嘲讽")
	if it.has("aura"):                           parts.append("光环:" + aura_text(it["aura"]))
	return "%s(%s)" % [item_name(item_id), ", ".join(parts)]


const _RARITY_ZH: Dictionary = { "common": "普通", "rare": "稀有", "epic": "史诗" }
const _TAG_HINT: Dictionary = {
	"blade": "刃 · 与磨刀石相邻 = 开刃(攻+6)",
	"sharpen": "磨 · 与刀刃相邻 = 开刃(攻+6)",
	"guard": "盾 · 与护甲相邻 = 重装(防+5血+12)",
	"armor": "甲 · 与盾相邻 = 重装(防+5血+12)",
	"arcane": "法器 · 两件相邻 = 共鸣(魔+6)",
	"vital": "生命 · 两件相邻 = 生机(血+18)",
}

## 物品详细信息（鼠标悬浮 tooltip 用，多行）。数值属性按色阶缩放显示。
static func item_tooltip(item_id: String) -> String:
	var it: Dictionary = item_def(item_id)
	if it.is_empty():
		return item_id
	var lines: Array = []
	lines.append("%s 【%s】" % [item_name(item_id), _RARITY_ZH.get(it.get("rarity", "common"), "普通")])
	if item_tier(item_id) > 0:
		lines.append("色阶：%s（数值 ×%d）" % [tier_name(item_tier(item_id)), int(tier_multiplier(item_tier(item_id)))])

	if it.get("tag", "") == "skillbook":
		var sid: String = it.get("skill_id", "")
		lines.append("技能书 · 冷却 %d 回合（占格、和装备抢空间）" % int(it.get("cd", 0)))
		lines.append("认职业：%s" % _class_zh(SkillTable.get_skill(sid).get("hero_class", "")))
		lines.append("效果：" + _skill_effect_text(sid))
		return "\n".join(lines)

	# 装备：属性 + 协同提示
	var stats: Array = []
	var a := item_stat(item_id, "atk");   if a != 0: stats.append("攻 +%d" % a)
	var d := item_stat(item_id, "def");   if d != 0: stats.append("防 +%d" % d)
	var h := item_stat(item_id, "hp");    if h != 0: stats.append("血 +%d" % h)
	var m := item_stat(item_id, "magic"); if m != 0: stats.append("魔 +%d" % m)
	var p := item_stat(item_id, "mp");    if p != 0: stats.append("蓝 +%d" % p)
	if float(it.get("crit_chance", 0.0)) != 0.0: stats.append("暴击 +%d%%" % int(it["crit_chance"] * 100))
	if float(it.get("crit_dmg", 0.0)) != 0.0:    stats.append("暴伤 +%d%%" % int(it["crit_dmg"] * 100))
	if float(it.get("dodge_chance", 0.0)) != 0.0: stats.append("闪避 +%d%%" % int(it["dodge_chance"] * 100))
	if int(it.get("taunt", 0)) != 0:             stats.append("嘲讽（站前排时优先被攻击）")
	if not stats.is_empty():
		lines.append("属性：" + "  ".join(stats))
	var hint: String = _TAG_HINT.get(it.get("tag", ""), "")
	if hint != "":
		lines.append("协同：" + hint)
	if it.has("aura"):
		lines.append("光环：" + aura_text(it["aura"]))
		lines.append("范围：" + aura_scope_note(it["aura"].get("scope", "team")))
	if is_mergeable(item_id) and item_tier(item_id) < TIER_MAX:
		lines.append("合成：与另一件同色阶 %s 合成 → %s" % [item_name(item_id), tier_name(item_tier(item_id) + 1)])
	return "\n".join(lines)


static func _class_zh(c: String) -> String:
	match c:
		"warrior": return "战士"
		"mage":    return "法师"
		"priest":  return "牧师"
		"rogue":   return "盗贼"
		"archer":  return "猎人"
	return c if c != "" else "通用"

# 把 SkillTable 的技能数据转成一句人话效果
static func _skill_effect_text(sid: String) -> String:
	var s: Dictionary = SkillTable.get_skill(sid)
	if s.is_empty():
		return sid
	var t: String = s.get("type", "damage")
	var mp: String = "（耗蓝 %d）" % int(s.get("mp_cost", 0)) if int(s.get("mp_cost", 0)) > 0 else ""
	if t == "heal_ally":
		return "治疗血量最少的友军，回血 = %.1f×魔力 %s" % [float(s.get("power", 1.0)), mp]
	if t == "buff_self":
		var b: Array = []
		if int(s.get("buff_attack", 0)) != 0:  b.append("攻+%d" % s["buff_attack"])
		if int(s.get("buff_defense", 0)) != 0: b.append("防+%d" % s["buff_defense"])
		if int(s.get("buff_speed", 0)) != 0:   b.append("速+%d" % s["buff_speed"])
		if int(s.get("buff_magic", 0)) != 0:   b.append("魔+%d" % s["buff_magic"])
		var dur: String = "全程" if int(s.get("buff_turns", -1)) < 0 else "%d回合" % int(s.get("buff_turns", 0))
		return "强化自身 %s（%s）%s" % [", ".join(b), dur, mp]
	# damage 类
	var attr: String = "魔法" if s.get("use_magic", false) else "物理"
	var parts: Array = ["造成 %.1f×%s 伤害" % [float(s.get("power", 1.0)), attr]]
	if s.get("aoe", false):        parts.append("群体")
	if s.get("ignore_def", false): parts.append("无视防御")
	elif s.get("half_def", false): parts.append("半防")
	if int(s.get("stun_turns", 0)) > 0:  parts.append("眩晕%d回合" % int(s["stun_turns"]))
	if int(s.get("slow_turns", 0)) > 0:  parts.append("减速%d回合" % int(s["slow_turns"]))
	if float(s.get("dot_power", 0.0)) > 0.0: parts.append("中毒%d回合" % int(s.get("dot_turns", 0)))
	return "，".join(parts) + " " + mp
