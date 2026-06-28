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

enum State { NONE, MAP, ENCOUNTER, DRAFT, VILLAGE, REST, VICTORY, GAME_OVER }

const START_GOLD := 500
const SHOP_STOCK_SIZE := 6
const REST_HEAL_PCT := 0.5   # 泉水/休息点：全员回复最大血的比例（消耗战泄压阀）
const MAX_PARTY := 5         # 队伍上限（起手 3，酒馆最多招到 5）
const TAVERN_OFFERS := 3     # 酒馆每次上几个候选
const RECRUIT_COST := 120    # 招募一个英雄的金币价（和买装备抢钱）

# 英雄池：跑局可用的英雄模板（加英雄/调数值=加一行；盗贼/猎人已纳入）。
# base = 低裸属性（战力靠背包）；技能在背包书注入，故此处不配技能。
const HERO_TEMPLATES: Dictionary = {
	"warrior": { "cls": Hero.HeroClass.WARRIOR, "name": "战士", "hp": 90, "atk": 6, "def": 8, "spd": 9,  "magic": 0, "mp": 40 },
	"mage":    { "cls": Hero.HeroClass.MAGE,    "name": "法师", "hp": 55, "atk": 3, "def": 3, "spd": 12, "magic": 5, "mp": 70 },
	"priest":  { "cls": Hero.HeroClass.PRIEST,  "name": "牧师", "hp": 65, "atk": 3, "def": 4, "spd": 9,  "magic": 5, "mp": 70 },
	"rogue":   { "cls": Hero.HeroClass.ROGUE,   "name": "盗贼", "hp": 70, "atk": 7, "def": 5, "spd": 16, "magic": 0, "mp": 50 },
	"archer":  { "cls": Hero.HeroClass.ARCHER,  "name": "猎人", "hp": 80, "atk": 7, "def": 6, "spd": 12, "magic": 0, "mp": 50 },
}
# 起手队伍：空——在起手村庄招募组建（决定：初始空队）。
const STARTER_TEAM: Array = []

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

# tavern_offers：当前酒馆在招的候选英雄模板 id 数组（招一个移除一个）。
var tavern_offers: Array = []

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
	tavern_offers = []
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


## 进入当前节点：村庄 → 商店；泉水 → 休息；其它 → 遭遇。
func enter_current_node() -> void:
	match current_node().get("type", ""):
		"village":
			shop_stock = LootTable.draw_draft(SHOP_STOCK_SIZE)   # 商店：按 rarity 随机上货
			tavern_offers = _roll_recruits(TAVERN_OFFERS)        # 招募：随机候选
			_set_state(State.VILLAGE)
		"rest":
			_set_state(State.REST)
		_:
			_set_state(State.ENCOUNTER)


## 泉水/休息：全员存活英雄回复 REST_HEAL_PCT 比例的最大血（钳到上限）。
## 返回 [{ name, before, after, max }]，供界面展示回血前后。
func rest_heal() -> Array:
	var report: Array = []
	for h in party:
		if not h.is_alive():
			continue
		var mx: int = h.get_max_hp()
		var before: int = h.current_hp
		h.current_hp = min(mx, before + int(ceil(mx * REST_HEAL_PCT)))
		report.append({ "name": h.entity_name, "before": before, "after": h.current_hp, "max": mx })
	return report


## 离开休息点 → 前进到下一节点。
func leave_rest() -> void:
	depth += 1
	depth_changed.emit(depth)
	if depth >= nodes.size():
		_set_state(State.VICTORY)
	else:
		_set_state(State.MAP)


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


# ── 招募 ──────────────────────────────────────────────────────────────────────

## 是否还能再招（未满队）
func party_is_full() -> bool:
	return roster.size() >= MAX_PARTY

## 招募一个候选英雄：队伍没满 + 金币够 + 在招 → 入队、扣钱、下架、自动站位。
func recruit(template_id: String) -> bool:
	if party_is_full():
		return false
	if not (template_id in tavern_offers):
		return false
	if gold < RECRUIT_COST:
		return false
	gold -= RECRUIT_COST
	gold_changed.emit(gold)
	tavern_offers.erase(template_id)
	var entry: Dictionary = make_hero_entry(template_id)
	roster.append(entry)
	party.append(entry["hero"])
	_place_in_empty_slot(entry["hero"])
	return true

## 离开村庄 → 前进到下一节点（商店+招募都在村庄；村庄不会是最后一个节点）。
func leave_village() -> void:
	shop_stock = []
	tavern_offers = []
	depth += 1
	depth_changed.emit(depth)
	if depth >= nodes.size():
		_set_state(State.VICTORY)
	else:
		_set_state(State.MAP)

# 抽 n 个英雄池模板作候选（可重复职业；允许已在队的职业再来）。
func _roll_recruits(n: int) -> Array:
	var ids: Array = HERO_TEMPLATES.keys()
	var out: Array = []
	for i in range(n):
		out.append(ids[randi() % ids.size()])
	return out

# 把新英雄放进第一个空站位格（优先后排 row1，再前排 row0）。
func _place_in_empty_slot(hero) -> void:
	for row in [1, 0]:
		for col in range(3):
			var cell := Vector2i(col, row)
			if not squad_slots.has(cell):
				squad_slots[cell] = hero
				return


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


# ── 起手名册（从英雄池 HERO_TEMPLATES 取 STARTER_TEAM）─────────────────────────
# 返回 Array[{ "hero": Hero, "base": Dictionary, "grid": Dictionary }]。
# base = 英雄"光身"裸属性（裸base 真相源）；grid 空（起手空背包）。
# 注：技能在 BackpackLoadout.build_party 里按背包技能书重置，故此处不配技能。

func _make_starter_roster() -> Array:
	var out: Array = []
	for tid in STARTER_TEAM:
		out.append(make_hero_entry(tid))
	return out

# 按英雄池模板 id 造一个名册条目（起手/招募共用）。
func make_hero_entry(template_id: String) -> Dictionary:
	var t: Dictionary = HERO_TEMPLATES.get(template_id, {})
	var hero: Hero = _starter(int(t.get("cls", Hero.HeroClass.WARRIOR)), String(t.get("name", template_id)),
		int(t.get("hp", 60)), int(t.get("atk", 5)), int(t.get("def", 5)),
		int(t.get("spd", 10)), int(t.get("magic", 0)), int(t.get("mp", 50)), [])
	var base: Dictionary = { "hp": int(t.get("hp", 60)), "atk": int(t.get("atk", 5)),
		"def": int(t.get("def", 5)), "magic": int(t.get("magic", 0)),
		"spd": int(t.get("spd", 10)), "mp": int(t.get("mp", 50)) }
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


# ── 地图（村庄 → 3 战斗 + 中途泉水 + 魔王）────────────────────────────────────
# 怪物数值见 MonsterFactory.ENEMIES（加怪=加一行）；难度由平衡 harness + 试玩拧。

func _build_map() -> Array:
	return [
		_node("village", "村庄", [], 0),
		_node("battle", "林间遭遇", MonsterFactory.create_group(["wolf", "wolf"]), 20),
		_node("village", "村镇", [], 0),
		_node("battle", "剧毒巢穴", MonsterFactory.create_group(["venom_bug", "stone_guard"]), 25),
		_node("rest",   "泉水", [], 0),
		_node("battle", "废墟伏击", MonsterFactory.create_group(["bandit", "ranger"]), 30),
		_node("boss",   "魔王",     MonsterFactory.create_group(["demon_lord", "claw_minion"]), 100),
	]

func _node(type: String, nm: String, enemies: Array, g: int) -> Dictionary:
	return { "type": type, "name": nm, "enemies": enemies, "gold": g }
