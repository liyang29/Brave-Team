extends Node

# ─────────────────────────────────────────────────────────────────────────────
# RunManager — roguelike 跑局状态单例（Autoload）
#
# 取代旧公会项目里 GameManager/HeroManager/GuildManager/DataManager 中 roguelike
# 真正需要的那部分：游戏状态机 + 队伍 + 金币 + 地图进度。
#
# 当前为最小骨架：标题 → 节点地图 → 遭遇(自动战斗) → 回地图 → 打到魔王。
# 起手队伍暂用占位数值（待"背包构筑 prep 界面"接入后由玩家搭背包决定战力）。
# HP 跨节点保留（消耗战），阵亡永久（is_alive=false 不再参战）。
# ─────────────────────────────────────────────────────────────────────────────

signal state_changed(new_state)
signal gold_changed(new_gold)
signal depth_changed(new_depth)

const LootTable = preload("res://scripts/systems/LootTable.gd")

enum State { NONE, MAP, ENCOUNTER, DRAFT, SHOP, VICTORY, GAME_OVER }

const START_GOLD := 500
const SHOP_STOCK_SIZE := 6

var state: int = State.NONE
var party: Array = []        # Array[Hero]，整局复用，HP 累积
var gold: int = 0
var depth: int = 0           # 当前所在节点索引（0 起）
var nodes: Array = []        # [{ type, name, enemies:Array[EnemyData], gold:int }]
var last_result = null       # 上一场 BattleResult（结果界面用）

# ── 背包构筑状态（Step 2：跨整局保留，供将来 prep 界面 + BackpackLoadout 用）──
# roster：队伍名册，每个元素 = { "hero": Hero, "base": Dictionary, "grid": Dictionary }
#   base = 英雄"光身"裸属性 { hp,atk,def,magic,spd,mp }（builder 幂等的算起点）
#   grid = { Vector2i(col,row): item_id } 该英雄背包摆放
#   ⚠️ 这是背包相关状态的"真相源"；party 是其英雄列表视图（向后兼容旧代码）。
var roster: Array = []
# owned_items：拥有但未摆入任何背包的物品库存（item_id -> 数量）。
#   起手为空——力量靠战利品积累（决定⑤）。Step 4 战利品 draft 往这里加。
var owned_items: Dictionary = {}
# squad_slots：站位摆放 Vector2i(col,row) -> Hero。row0=前排 / row1=后排（soft_row）。
var squad_slots: Dictionary = {}

# pending_draft：上一场非 boss 胜利抽出的待选战利品（item_id 数组），Draft 界面读它。
var pending_draft: Array = []
# shop_stock：当前商店在售物品（item_id 数组，买一件移除一件），进商店时生成。
var shop_stock: Array = []


# ── 跑局生命周期 ──────────────────────────────────────────────────────────────

func start_run() -> void:
	roster = _make_starter_roster()
	party = roster.map(func(e): return e["hero"])   # 英雄列表视图（向后兼容）
	owned_items = {}                                 # 空背包起手，靠商店/战利品积累
	squad_slots = _default_formation()
	pending_draft = []
	shop_stock = []
	gold = START_GOLD                                # 起步金币，开局村庄商店采购
	depth = 0
	nodes = _build_map()
	last_result = null
	_set_state(State.MAP)


func current_node() -> Dictionary:
	return nodes[depth] if depth < nodes.size() else {}

func is_boss_node() -> bool:
	return current_node().get("type", "") == "boss"

func alive_party() -> Array:
	return party.filter(func(h): return h.is_alive())


## 进入当前节点：村庄 → 商店；其它 → 遭遇。
func enter_current_node() -> void:
	if current_node().get("type", "") == "shop":
		shop_stock = LootTable.draw_draft(SHOP_STOCK_SIZE)   # 按 rarity 随机上货
		_set_state(State.SHOP)
	else:
		_set_state(State.ENCOUNTER)


## 商店购买：金币够且在售 → 扣钱、入库、下架。返回是否成功。
func buy_item(item_id: String) -> bool:
	if not (item_id in shop_stock):
		return false
	var cost: int = LootTable.price(item_id)
	if gold < cost:
		return false
	gold -= cost
	gold_changed.emit(gold)
	shop_stock.erase(item_id)
	owned_items[item_id] = int(owned_items.get(item_id, 0)) + 1
	return true


## 离开商店 → 前进到下一节点（商店不会是最后一个节点）。
func leave_shop() -> void:
	shop_stock = []
	depth += 1
	depth_changed.emit(depth)
	if depth >= nodes.size():
		_set_state(State.VICTORY)
	else:
		_set_state(State.MAP)


## 遭遇结束回报：
##   负 → 全灭游戏结束；
##   魔王胜 → 直接通关（不抽战利品）；
##   普通胜 → 拿钱 + 抽 3 件战利品进入 DRAFT（depth 待 finish_draft 后再前进）。
func resolve_encounter(won: bool, result = null) -> void:
	last_result = result
	if not won:
		_set_state(State.GAME_OVER)
		return
	add_gold(int(current_node().get("gold", 0)))
	if is_boss_node():
		depth += 1
		depth_changed.emit(depth)
		_set_state(State.VICTORY)
		return
	pending_draft = LootTable.draw_draft(3)
	_set_state(State.DRAFT)


## 战利品 draft 结束：留下的物品进库存 → 前进到下一节点（或通关）。
func finish_draft(kept: Array) -> void:
	for id in kept:
		owned_items[id] = int(owned_items.get(id, 0)) + 1
	pending_draft = []
	depth += 1
	depth_changed.emit(depth)
	if depth >= nodes.size():
		_set_state(State.VICTORY)
	else:
		_set_state(State.MAP)


func add_gold(n: int) -> void:
	gold += n
	gold_changed.emit(gold)


func _set_state(s: int) -> void:
	state = s
	state_changed.emit(s)


# ── 起手名册（占位数值：现保持现状，低裸base 留到 Step 3 接背包时再调）─────────
# 返回 Array[{ "hero": Hero, "base": Dictionary, "grid": Dictionary }]。
# base 暂等于英雄当前占位数值（裸base 真相源）；grid 空（起手空背包，靠战利品）。

func _make_starter_roster() -> Array:
	return [
		_starter_entry(Hero.HeroClass.WARRIOR, "战士", 130, 16, 12, 8, 0, 60, ["slash"]),
		_starter_entry(Hero.HeroClass.MAGE,    "法师", 70, 8, 4, 13, 19, 80, ["fireball"]),
		_starter_entry(Hero.HeroClass.PRIEST,  "牧师", 85, 6, 7, 9, 16, 80, ["holy_heal", "purify"]),
	]

# 造一个名册条目：英雄 + 裸base 字典 + 空背包
func _starter_entry(cls: int, nm: String, hp: int, atk: int, def_v: int, spd: int,
					magic: int, mp: int, skills: Array) -> Dictionary:
	var hero: Hero = _starter(cls, nm, hp, atk, def_v, spd, magic, mp, skills)
	var base: Dictionary = { "hp": hp, "atk": atk, "def": def_v, "magic": magic, "spd": spd, "mp": mp }
	return { "hero": hero, "base": base, "grid": {} }

# 默认站位：战士前排，法师/牧师后排（row0 前 / row1 后；soft_row）
func _default_formation() -> Dictionary:
	var slots: Dictionary = {}
	if roster.size() >= 1: slots[Vector2i(0, 0)] = roster[0]["hero"]
	if roster.size() >= 2: slots[Vector2i(0, 1)] = roster[1]["hero"]
	if roster.size() >= 3: slots[Vector2i(1, 1)] = roster[2]["hero"]
	return slots

func _starter(cls: int, nm: String, hp: int, atk: int, def_v: int, spd: int,
			  magic: int, mp: int, skills: Array) -> Hero:
	var hero: Hero = HeroFactory.create(cls)
	hero.set("base_max_hp", hp)
	hero.set("base_attack", atk)
	hero.set("base_defense", def_v)
	hero.set("base_speed",  spd)
	hero.set("base_magic",  magic)
	hero.set("base_mp",     mp)
	var sk = hero.get("skills")
	if sk != null:
		sk.clear()
	for s in skills:
		hero.learn_skill(s)
	hero.stat_block.rebuild()
	hero.entity_name = nm
	hero.current_hp = hero.get_max_hp()
	return hero


# ── 地图（占位：线性 3 战斗 + 1 魔王）────────────────────────────────────────

func _build_map() -> Array:
	return [
		_node("shop", "村庄", [], 0),
		_node("battle", "林间遭遇", [_e("野狼", 70, 12, 4, 9), _e("野狼", 70, 12, 4, 9)], 20),
		_node("battle", "剧毒巢穴", [_e("毒虫", 55, 11, 3, 11, "back", true), _e("石卫", 120, 13, 9, 6)], 25),
		_node("battle", "废墟伏击", [_e("强盗", 95, 15, 6, 10), _e("游侠", 70, 14, 5, 12, "back", true)], 30),
		_node("boss",   "魔王",     [_e("魔王", 260, 22, 12, 10), _e("爪牙", 90, 14, 6, 9)], 100),
	]

func _node(type: String, nm: String, enemies: Array, g: int) -> Dictionary:
	return { "type": type, "name": nm, "enemies": enemies, "gold": g }

func _e(nm: String, hp: int, atk: int, def_v: int, spd: int,
		prow: String = "front", ranged: bool = false) -> EnemyData:
	var en: EnemyData = EnemyData.new()
	en.entity_name = nm
	en.base_max_hp = hp
	en.base_attack = atk
	en.base_defense = def_v
	en.base_speed = spd
	en.base_magic = atk
	en.preferred_row = prow
	en.is_ranged = ranged
	en.ai_type = EnemyData.AI_BASIC_ATTACK
	return en
