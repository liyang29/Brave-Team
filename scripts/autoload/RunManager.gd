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
signal node_changed(new_node_id)

const LootTable = preload("res://scripts/systems/LootTable.gd")
const NodeTypes = preload("res://scripts/systems/run/NodeTypes.gd")
const MapConfig = preload("res://scripts/systems/run/MapConfig.gd")
const MapGenerator = preload("res://scripts/systems/run/MapGenerator.gd")
const EventTable = preload("res://scripts/systems/run/EventTable.gd")
const Backpack = preload("res://scripts/systems/backpack/BackpackModel.gd")

enum State { NONE, MAP, ENCOUNTER, DRAFT, VILLAGE, REST, EVENT, VICTORY, GAME_OVER }

const START_GOLD := 500
const SHOP_STOCK_SIZE := 6
const REST_HEAL_PCT := 0.5   # 泉水/休息点：全员回复最大血的比例（消耗战泄压阀）
const MAX_PARTY := 5         # 队伍上限（起手 3，酒馆最多招到 5）
const RECRUIT_COST := 120    # 招募一个英雄的金币价（和买装备抢钱）
const MIN_PARTY_TO_LEAVE := 2  # 至少 2 人才能出发（1 人打不过第一关；本作是小队游戏）

# 英雄池：跑局可用的英雄模板（加英雄/调数值=加一行；盗贼/猎人已纳入）。
# base = 低裸属性（战力靠背包）；技能在背包书注入，故此处不配技能。
const HERO_TEMPLATES: Dictionary = {
	"warrior": { "cls": Hero.HeroClass.WARRIOR, "name": "战士", "hp": 90, "atk": 6, "def": 8, "spd": 9,  "magic": 0, "mp": 40 },
	"mage":    { "cls": Hero.HeroClass.MAGE,    "name": "法师", "hp": 55, "atk": 3, "def": 3, "spd": 12, "magic": 5, "mp": 70 },
	"priest":  { "cls": Hero.HeroClass.PRIEST,  "name": "牧师", "hp": 65, "atk": 3, "def": 4, "spd": 9,  "magic": 5, "mp": 70 },
	"rogue":   { "cls": Hero.HeroClass.ROGUE,   "name": "盗贼", "hp": 70, "atk": 7, "def": 5, "spd": 16, "magic": 0, "mp": 50 },
	"archer":  { "cls": Hero.HeroClass.ARCHER,  "name": "猎人", "hp": 80, "atk": 7, "def": 6, "spd": 12, "magic": 0, "mp": 50 },
}
# 酒馆每次上几个候选：全部职业都上——避免"这村没战士"的抽卡挫败感。
# ⚠️ GDScript 常量表达式不能调 HERO_TEMPLATES.size()（非编译期常量），手动同步：
#    加/删英雄职业时这个数字要跟着改，否则要么漏显示、要么多要不存在的候选。
const TAVERN_OFFERS := 5     # = HERO_TEMPLATES.size()（当前 5 职业：战法牧盗猎）

# 手动限定招募池（跟 MetaProgress 局外解锁是两回事，互不影响存档）：
#   留空 [] = 默认——招募池 = HERO_TEMPLATES 里"局外已解锁"的职业（正常玩法）。
#   填了 id = 只从这些 id 里抽，哪怕其它职业已经解锁也不会出现（想临时只玩战法牧就填这三个）。
# 随时改随时生效，不影响存档里的解锁记录——清空这个数组就恢复原样，解锁进度还在。
# 用 var（不是 const）纯粹是方便测试临时重置；日常改玩法直接改这行的初始值即可。
var RECRUIT_POOL_OVERRIDE: Array = []
# 起手队伍：空——在起手村庄招募组建（决定：初始空队）。
const STARTER_TEAM: Array = []

var state: int = State.NONE
var party: Array = []        # Array[Hero]，整局复用，HP 累积
var gold: int = 0
var last_result = null       # 上一场 BattleResult（结果界面用）

# ── 分支地图（尖塔式分层 DAG；取代旧"线性数组 + depth 索引"）─────────────────
# map_nodes：id -> { id, layer, col, type, name, enemies, gold, next:Array[id] }
#   next = 后继节点 id（有向边）；"严格连线约束" = 只能去当前节点 next 里的节点。
var map_nodes: Dictionary = {}
var current_node_id: String = ""   # 玩家当前所在/刚打完的节点 id（取代 depth）
var map_layers: int = 0            # 总层数（RunMap 分层渲染 + 进度显示）
var map_seed: int = -1             # 本局地图种子（复现/存档/调试）

# ── 背包构筑状态（Step 2：跨整局保留，供将来 prep 界面 + BackpackLoadout 用）──
# roster：队伍名册，每个元素 = { "hero": Hero, "base": Dictionary, "grid": Dictionary }
#   base = 英雄"光身"裸属性 { hp,atk,def,magic,spd,mp }（builder 幂等的算起点）
#   grid = { Vector2i(col,row): item_id } 该英雄背包摆放
#   ⚠️ 这是背包相关状态的"真相源"；party 是其英雄列表视图（向后兼容旧代码）。
var roster: Array = []
# mule_grid：驮兽仓库——拥有但未摆入任何英雄背包的物品，空间化存放
# （{ Vector2i(锚点): item_id }，跟英雄 grid 同一套形状/占格逻辑，尺寸见
#   Backpack.MULE_GRID_W/H，目前 6×6）。起手为空——力量靠战利品积累（决定⑤）。
#   容量有限：满了拿不到新东西，得先在驮兽里丢弃/卖出腾地方（"驮兽"主题——
#   驮不动就得取舍，不是无限背包）。
var mule_grid: Dictionary = {}
# squad_slots：站位摆放 Vector2i(col,row) -> Hero。row0=前排 / row1=后排（soft_row）。
var squad_slots: Dictionary = {}

# tavern_offers：当前酒馆在招的候选英雄模板 id 数组（招一个移除一个）。
var tavern_offers: Array = []

# pending_draft：上一场非 boss 胜利抽出的待选战利品（item_id 数组），Draft 界面读它。
var pending_draft: Array = []
# shop_stock：当前商店在售物品（item_id 数组，买一件移除一件），进商店时生成。
var shop_stock: Array = []

# ── 事件节点状态（存档友好：只存 String id）───────────────────────────────────
# current_event：当前事件 id（EventScreen 读它）；used_events：本局遇过的事件 id（不重复）。
var current_event: String = ""
var used_events: Array = []


# ── 跑局生命周期 ──────────────────────────────────────────────────────────────

func start_run(config: Dictionary = MapConfig.DEFAULT, seed: int = -1) -> void:
	roster = _make_starter_roster()
	party = roster.map(func(e): return e["hero"])   # 英雄列表视图（向后兼容）
	mule_grid = {}                                   # 空驮兽起手，靠商店/战利品积累
	squad_slots = _default_formation()
	tavern_offers = []
	pending_draft = []
	shop_stock = []
	current_event = ""
	used_events = []
	gold = START_GOLD                                # 起步金币，开局村庄商店采购
	var map: Dictionary = MapGenerator.generate(config, seed)
	map_nodes = map["nodes"]
	current_node_id = map["start_id"]                # 起点 = 第 0 层村庄
	map_layers = int(map["layers"])
	map_seed = int(map["seed"])
	MetaProgress.record_layer(current_layer())       # 起手也算"到过第 0 层"（局外成长）
	last_result = null
	_set_state(State.MAP)


func current_node() -> Dictionary:
	return map_nodes.get(current_node_id, {})

func current_layer() -> int:
	return int(current_node().get("layer", 0))

func is_boss_node() -> bool:
	return current_node().get("type", "") == "boss"

func alive_party() -> Array:
	return party.filter(func(h): return h.is_alive())


# ── 地图导航（严格连线约束：只能去当前节点的后继）──────────────────────────────

## 当前节点可前往的后继 id 列表（RunMap 据此点亮可选节点）。
func reachable_next() -> Array:
	return (current_node().get("next", []) as Array).duplicate()

## 能否前往 next_id：必须是当前节点的直接后继。
func can_travel_to(next_id: String) -> bool:
	return next_id in current_node().get("next", [])

## 前往一个后继节点并进入它（尖塔式：在地图点节点 = 走过去 + 进房间）。
## 由 RunMap 在玩家点选后调用；enter_current_node 会跑 on_enter + 切到房间状态。
func travel_to(next_id: String) -> bool:
	if not can_travel_to(next_id):
		return false
	current_node_id = next_id
	node_changed.emit(current_node_id)
	MetaProgress.record_layer(current_layer())   # 局外成长：刷新历史最深层，可能解锁新内容
	enter_current_node()
	return true


## 进入当前节点：由 NodeTypes 注册表决定进哪个状态 + 是否要进入前准备。
## 加节点类型只改 NodeTypes.REGISTRY 一处（不再在这里逐类型 match）。
func enter_current_node() -> void:
	var def: Dictionary = NodeTypes.get_def(current_node().get("type", ""))
	var hook: String = def.get("on_enter", "")
	if hook != "" and has_method(hook):
		call(hook)                                       # 进入前准备（如村庄上货/招募）
	_set_state(State[def.get("state", "ENCOUNTER")])     # 枚举名字符串 → State 枚举

## 村庄进入前准备：商店按 rarity 上货 + 随机招募候选（由 NodeTypes 的 on_enter 调）。
func _enter_village() -> void:
	shop_stock = LootTable.draw_draft(SHOP_STOCK_SIZE, current_layer())
	tavern_offers = _roll_recruits(TAVERN_OFFERS)


# ── 事件节点 ──────────────────────────────────────────────────────────────────

## 进入事件节点前准备：随机挑一个本局未遇过的事件（全遇过则任意）。
func _enter_event() -> void:
	var pool: Array = EventTable.all_ids().filter(func(id): return not (id in used_events))
	if pool.is_empty():
		pool = EventTable.all_ids()          # 兜底：都遇过了就允许重复
	current_event = pool[randi() % pool.size()] if not pool.is_empty() else ""

## 当前事件的选项列表。
func event_choices() -> Array:
	return EventTable.get_event(current_event).get("choices", [])

## 第 index 个选项是否可选（门槛满足）。UI 据此灰掉不可选项。
func event_choice_available(index: int) -> bool:
	var choices: Array = event_choices()
	if index < 0 or index >= choices.size():
		return false
	return _meets_require(choices[index].get("require", {}))

## 选择事件选项：判门槛 → 应用效果（确定 or 风险 roll）→ 记为遇过。
## forced_roll≥0 时用它代替随机（测试注入）；返回 { ok, text }。
func resolve_event_choice(index: int, forced_roll: float = -1.0) -> Dictionary:
	var choices: Array = event_choices()
	if index < 0 or index >= choices.size():
		return { "ok": false, "text": "" }
	var choice: Dictionary = choices[index]
	if not _meets_require(choice.get("require", {})):
		return { "ok": false, "text": "条件不满足。" }

	var text: String = ""
	if choice.has("risk"):
		var risk: Dictionary = choice["risk"]
		var roll: float = forced_roll if forced_roll >= 0.0 else randf()
		if roll < float(risk.get("chance", 0.0)):
			_apply_event_effects(risk.get("win", []))
			text = String(choice.get("result_win", "成功了。"))
		else:
			_apply_event_effects(risk.get("lose", []))
			text = String(choice.get("result_lose", "失败了。"))
	else:
		_apply_event_effects(choice.get("effects", []))
		text = String(choice.get("result", ""))

	if current_event != "" and not (current_event in used_events):
		used_events.append(current_event)
	return { "ok": true, "text": text }

## 离开事件 → 回地图选后继。
func leave_event() -> void:
	_return_to_map()


# 门槛判定：gold(队伍金≥N) / item(库存或任一背包里有) / class(队里有该职业)。
func _meets_require(require: Dictionary) -> bool:
	if require.is_empty():
		return true
	if require.has("gold") and gold < int(require["gold"]):
		return false
	if require.has("item") and not _has_item(String(require["item"])):
		return false
	if require.has("class") and not _party_has_class(String(require["class"])):
		return false
	return true

# 队伍(驮兽 + 所有背包)里是否有某物品。
func _has_item(id: String) -> bool:
	if id in mule_grid.values():
		return true
	for entry in roster:
		if id in (entry.get("grid", {}) as Dictionary).values():
			return true
	return false

# 队里是否有某职业英雄。
func _party_has_class(class_key: String) -> bool:
	for h in party:
		if _class_key_of(h) == class_key:
			return true
	return false

func _class_key_of(hero) -> String:
	match int(hero.hero_class):
		Hero.HeroClass.WARRIOR: return "warrior"
		Hero.HeroClass.MAGE:    return "mage"
		Hero.HeroClass.PRIEST:  return "priest"
		Hero.HeroClass.ROGUE:   return "rogue"
		Hero.HeroClass.ARCHER:  return "archer"
	return ""

# 应用一组效果。
func _apply_event_effects(effects: Array) -> void:
	for e in effects:
		_apply_event_effect(e)

# 应用单个效果（精简 3 种；加新效果类型 = 加一个 match 分支，这就是"升级口"）。
func _apply_event_effect(effect: Dictionary) -> void:
	match String(effect.get("type", "")):
		"gold":
			gold = max(0, gold + int(effect.get("amount", 0)))
			gold_changed.emit(gold)
		"item":
			var id: String = String(effect.get("id", ""))
			if id != "":
				for i in range(int(effect.get("count", 1))):
					_try_add_to_mule(id)   # 驮兽满了就少给（低频事件效果，不做专门提示）
		"hp_pct":
			var pct: float = float(effect.get("amount", 0.0))
			for h in party:
				if not h.is_alive():
					continue
				var mx: int = h.get_max_hp()
				var delta: int = int(round(mx * pct))
				h.current_hp = clampi(h.current_hp + delta, 1, mx)   # 钳 ≥1：事件不猝死


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


## 打完/离开当前节点 → 回地图让玩家选后继（分支图下"前进"由玩家在 RunMap 点选，
## 经 travel_to 完成；这里只负责"结束当前节点、回到地图"）。
## 通关是走到魔王节点打赢（resolve_encounter 里判），不再靠"走到数组末尾"。
func _return_to_map() -> void:
	_set_state(State.MAP)


## 离开休息点 → 回地图选后继。
func leave_rest() -> void:
	_return_to_map()


## 商店购买：金币够、在售、驮兽装得下 → 扣钱、入库、下架。返回是否成功。
## 驮兽满了（塞不下这件的形状）直接拒绝——不做"超载"状态，逼玩家先腾地方。
func buy_item(item_id: String) -> bool:
	if not (item_id in shop_stock):
		return false
	var cost: int = LootTable.price(item_id)
	if gold < cost:
		return false
	if not mule_has_room(item_id):
		return false
	gold -= cost
	gold_changed.emit(gold)
	shop_stock.erase(item_id)
	_try_add_to_mule(item_id)
	return true


# ── 驮兽仓库（公共装备栏，空间化：Backpack.MULE_GRID_W/H，跟英雄背包同一套形状逻辑）──

## 驮兽还有没有地方放得下这件（UI 按钮置灰用）。
func mule_has_room(item_id: String) -> bool:
	return Backpack.has_room(mule_grid, item_id, Backpack.MULE_GRID_W, Backpack.MULE_GRID_H)

## 自动找个空位塞进驮兽（购买/战利品/事件奖励用；玩家手动整理走拖放，不走这条）。
## 返回是否成功——满了放不下时返回 false，调用方决定要不要提示玩家。
func _try_add_to_mule(item_id: String) -> bool:
	var anchor: Vector2i = Backpack.first_free_anchor(mule_grid, item_id, Backpack.MULE_GRID_W, Backpack.MULE_GRID_H)
	if anchor == Vector2i(-1, -1):
		return false
	mule_grid[anchor] = item_id
	return true

## 卖出驮兽里某个锚点的物品：进价五折算金币，格子腾空。返回是否成功（锚点没东西则失败）。
func sell_mule_item(anchor: Vector2i) -> bool:
	if not mule_grid.has(anchor):
		return false
	add_gold(LootTable.sell_price(mule_grid[anchor]))
	mule_grid.erase(anchor)
	return true

## 丢弃驮兽里某个锚点的物品：直接消失，无任何回报（腾地方用）。返回是否成功。
func discard_mule_item(anchor: Vector2i) -> bool:
	if not mule_grid.has(anchor):
		return false
	mule_grid.erase(anchor)
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

## 能否离开村庄出发：达到最小人数（≥2）；或已≥1人但实在招不动了（没钱/没候选）→ 放行，避免卡死。
func can_leave_village() -> bool:
	if roster.size() >= MIN_PARTY_TO_LEAVE:
		return true
	if roster.size() >= 1 and (gold < RECRUIT_COST or tavern_offers.is_empty()):
		return true
	return false


## 离开村庄 → 回地图选后继（商店+招募都在村庄；村庄不会是魔王节点）。
func leave_village() -> void:
	shop_stock = []
	tavern_offers = []
	_return_to_map()

# 抽 n 个英雄池模板作候选（同一次不重复，避免同店出现两个同样的人）。
func _roll_recruits(n: int) -> Array:
	# 只从"局外已解锁"的职业里抽（MetaProgress；未解锁的职业压根不会被招到，
	# 想让玩家提前看到"还有职业待解锁"用 MetaProgress.locked_summary() 走 UI）。
	var ids: Array = HERO_TEMPLATES.keys().filter(func(id): return MetaProgress.is_unlocked(id))
	# 手动覆盖（RECRUIT_POOL_OVERRIDE 非空时生效）：再交叉一遍，缩小到指定职业。
	if not RECRUIT_POOL_OVERRIDE.is_empty():
		ids = ids.filter(func(id): return id in RECRUIT_POOL_OVERRIDE)
	ids.shuffle()
	return ids.slice(0, min(n, ids.size()))

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
##   普通/精英胜 → 拿钱 + 抽 3 件战利品进入 DRAFT（draft 完成后回地图选后继）。
func resolve_encounter(won: bool, result = null) -> void:
	last_result = result
	if result != null:
		_vacate_dead_from_squad(result.dead_heroes)
	if not won:
		_set_state(State.GAME_OVER)
		return
	add_gold(int(current_node().get("gold", 0)))
	if is_boss_node():
		_set_state(State.VICTORY)               # 打赢魔王 = 通关（魔王是唯一汇点）
		return
	pending_draft = LootTable.draw_draft(3, current_layer())
	_set_state(State.DRAFT)


## 阵亡英雄自动腾出站位格（活人不用先把尸体换到别处才能补位）；装备/背包留在她身上不动
## （"随葬品"——阵亡永久，不退回公共栏，roster 也不删她，只是不再占战位）。
func _vacate_dead_from_squad(dead_heroes: Array) -> void:
	for cell in squad_slots.keys():
		if squad_slots[cell] in dead_heroes:
			squad_slots.erase(cell)


## 战利品 draft 结束：留下的物品进驮兽 → 回地图选后继。
## 驮兽满了装不下的那件会被跳过（best-effort，不因为"选了却装不下"卡住整条 draft 流程）；
## 返回没装下的 item_id 列表，UI 可选择性提示"驮兽满，某件没能带走"。
func finish_draft(kept: Array) -> Array:
	var overflow: Array = []
	for id in kept:
		if not _try_add_to_mule(id):
			overflow.append(id)
	pending_draft = []
	_return_to_map()
	return overflow


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


# 地图现由 MapGenerator.generate(MapConfig.DEFAULT) 随机生成（尖塔式分层 DAG）。
# 群系/规模/类型分布/内容池全在 MapConfig 配置——加怪=改 MonsterFactory + MapConfig 内容池。
